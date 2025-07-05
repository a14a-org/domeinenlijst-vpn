import { Pool } from 'pg';
import { SocksProxyAgent } from 'socks-proxy-agent';
import axios from 'axios';
import pino from 'pino';
import {
  ProxyConfig,
  ProxyHealth,
  ProxyUsage,
  ProxyStats,
  ProxyRotationStrategy,
  ProxyUrl
} from '../models/proxy';

export class ProxyManager {
  private db: Pool;
  private logger = pino({ name: 'ProxyManager' });
  private currentProxyIndex = 0;
  private proxies: ProxyConfig[] = [];
  private healthMap: Map<string, ProxyHealth> = new Map();
  private usageMap: Map<string, ProxyUsage> = new Map();
  
  constructor(db: Pool) {
    this.db = db;
  }

  async initialize(): Promise<void> {
    await this.loadProxies();
    await this.loadHealthData();
    await this.loadUsageData();
    this.startHealthChecks();
  }

  private async loadProxies(): Promise<void> {
    const result = await this.db.query<ProxyConfig>(
      'SELECT * FROM proxy_configs WHERE is_active = true ORDER BY id'
    );
    this.proxies = result.rows;
    this.logger.info(`Loaded ${this.proxies.length} active proxies`);
  }

  private async loadHealthData(): Promise<void> {
    const result = await this.db.query<ProxyHealth>(
      'SELECT * FROM proxy_health'
    );
    result.rows.forEach(health => {
      this.healthMap.set(health.proxyId, health);
    });
  }

  private async loadUsageData(): Promise<void> {
    const result = await this.db.query<ProxyUsage>(
      'SELECT * FROM proxy_usage'
    );
    result.rows.forEach(usage => {
      this.usageMap.set(usage.proxyId, usage);
    });
  }

  private startHealthChecks(): void {
    setInterval(() => {
      this.checkAllProxies();
    }, 60000); // Check every minute
    
    // Initial check
    this.checkAllProxies();
  }

  private async checkAllProxies(): Promise<void> {
    for (const proxy of this.proxies) {
      await this.checkProxyHealth(proxy);
    }
  }

  private async checkProxyHealth(proxy: ProxyConfig): Promise<boolean> {
    const startTime = Date.now();
    let isHealthy = false;
    let error: string | undefined;

    try {
      const agent = new SocksProxyAgent(`socks5://${proxy.host}:${proxy.port}`);
      const response = await axios.get('https://api.ipify.org?format=json', {
        httpAgent: agent,
        httpsAgent: agent,
        timeout: 10000
      });

      if (response.status === 200 && response.data.ip) {
        isHealthy = true;
      }
    } catch (err) {
      error = err instanceof Error ? err.message : 'Unknown error';
      this.logger.error({ proxy: proxy.name, error }, 'Proxy health check failed');
    }

    const responseTime = Date.now() - startTime;
    await this.updateProxyHealth(proxy, isHealthy, responseTime, error);
    
    return isHealthy;
  }

  private async updateProxyHealth(
    proxy: ProxyConfig, 
    isHealthy: boolean, 
    responseTime: number,
    error?: string
  ): Promise<void> {
    const existingHealth = this.healthMap.get(proxy.id) || {
      proxyId: proxy.id,
      isHealthy: true,
      lastCheckTime: new Date(),
      successCount: 0,
      failureCount: 0,
      avgResponseTime: 0
    };

    const newHealth: ProxyHealth = {
      ...existingHealth,
      isHealthy,
      lastCheckTime: new Date(),
      successCount: isHealthy ? existingHealth.successCount + 1 : existingHealth.successCount,
      failureCount: isHealthy ? existingHealth.failureCount : existingHealth.failureCount + 1,
      avgResponseTime: this.calculateAvgResponseTime(existingHealth.avgResponseTime, responseTime, existingHealth.successCount),
      lastError: error
    };

    this.healthMap.set(proxy.id, newHealth);

    await this.db.query(
      `INSERT INTO proxy_health (proxy_id, is_healthy, last_check_time, success_count, failure_count, avg_response_time, last_error)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       ON CONFLICT (proxy_id) DO UPDATE SET
         is_healthy = $2,
         last_check_time = $3,
         success_count = $4,
         failure_count = $5,
         avg_response_time = $6,
         last_error = $7`,
      [proxy.id, isHealthy, new Date(), newHealth.successCount, newHealth.failureCount, newHealth.avgResponseTime, error]
    );
  }

  private calculateAvgResponseTime(currentAvg: number, newTime: number, count: number): number {
    return (currentAvg * count + newTime) / (count + 1);
  }

  async getNextProxy(strategy: ProxyRotationStrategy = 'round-robin', countryCode?: string): Promise<ProxyUrl | null> {
    const healthyProxies = this.getHealthyProxies(countryCode);
    
    if (healthyProxies.length === 0) {
      this.logger.warn('No healthy proxies available');
      return null;
    }

    let selectedProxy: ProxyConfig;

    switch (strategy) {
      case 'round-robin':
        selectedProxy = this.roundRobinSelection(healthyProxies);
        break;
      case 'random':
        selectedProxy = this.randomSelection(healthyProxies);
        break;
      case 'performance':
        selectedProxy = this.performanceBasedSelection(healthyProxies);
        break;
      case 'location':
        selectedProxy = countryCode 
          ? this.locationBasedSelection(healthyProxies, countryCode)
          : this.randomSelection(healthyProxies);
        break;
      default:
        selectedProxy = this.roundRobinSelection(healthyProxies);
    }

    await this.recordUsage(selectedProxy);

    return {
      url: `socks5://${selectedProxy.host}:${selectedProxy.port}`,
      proxy: selectedProxy
    };
  }

  private getHealthyProxies(countryCode?: string): ProxyConfig[] {
    return this.proxies.filter(proxy => {
      const health = this.healthMap.get(proxy.id);
      const isHealthy = health ? health.isHealthy : true; // Assume healthy if no data
      const matchesCountry = !countryCode || proxy.countryCode === countryCode;
      return proxy.isActive && isHealthy && matchesCountry;
    });
  }

  private roundRobinSelection(proxies: ProxyConfig[]): ProxyConfig {
    const proxy = proxies[this.currentProxyIndex % proxies.length];
    this.currentProxyIndex++;
    return proxy;
  }

  private randomSelection(proxies: ProxyConfig[]): ProxyConfig {
    const index = Math.floor(Math.random() * proxies.length);
    return proxies[index];
  }

  private performanceBasedSelection(proxies: ProxyConfig[]): ProxyConfig {
    // Calculate weights based on health metrics
    const weights = proxies.map(proxy => {
      const health = this.healthMap.get(proxy.id);
      if (!health) return 1;
      
      const successRate = health.successCount / (health.successCount + health.failureCount) || 0;
      const performanceScore = successRate * (1000 / (health.avgResponseTime || 1000));
      return Math.max(performanceScore, 0.1); // Minimum weight
    });

    // Weighted random selection
    const totalWeight = weights.reduce((a, b) => a + b, 0);
    let random = Math.random() * totalWeight;
    
    for (let i = 0; i < proxies.length; i++) {
      random -= weights[i];
      if (random <= 0) {
        return proxies[i];
      }
    }
    
    return proxies[proxies.length - 1];
  }

  private locationBasedSelection(proxies: ProxyConfig[], countryCode: string): ProxyConfig {
    const countryProxies = proxies.filter(p => p.countryCode === countryCode);
    return countryProxies.length > 0 
      ? this.randomSelection(countryProxies)
      : this.randomSelection(proxies);
  }

  private async recordUsage(proxy: ProxyConfig): Promise<void> {
    const usage = this.usageMap.get(proxy.id) || {
      proxyId: proxy.id,
      usageCount: 0,
      lastUsedAt: new Date(),
      totalBytes: 0,
      errors: 0
    };

    usage.usageCount++;
    usage.lastUsedAt = new Date();
    
    this.usageMap.set(proxy.id, usage);

    await this.db.query(
      `INSERT INTO proxy_usage (proxy_id, usage_count, last_used_at)
       VALUES ($1, $2, $3)
       ON CONFLICT (proxy_id) DO UPDATE SET
         usage_count = proxy_usage.usage_count + 1,
         last_used_at = $3`,
      [proxy.id, 1, new Date()]
    );
  }

  async getProxyStats(): Promise<ProxyStats[]> {
    return this.proxies.map(proxy => ({
      proxy,
      health: this.healthMap.get(proxy.id) || {
        proxyId: proxy.id,
        isHealthy: true,
        lastCheckTime: new Date(),
        successCount: 0,
        failureCount: 0,
        avgResponseTime: 0
      },
      usage: this.usageMap.get(proxy.id) || {
        proxyId: proxy.id,
        usageCount: 0,
        lastUsedAt: new Date(),
        totalBytes: 0,
        errors: 0
      }
    }));
  }

  async markProxyAsUnhealthy(proxyId: string, error: string): Promise<void> {
    const proxy = this.proxies.find(p => p.id === proxyId);
    if (proxy) {
      await this.updateProxyHealth(proxy, false, 0, error);
    }
  }
}