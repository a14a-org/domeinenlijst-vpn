export interface ProxyConfig {
  id: string;
  name: string;
  provider: 'surfshark' | 'nordvpn' | 'namecheap';
  host: string;
  port: number;
  location?: string;
  countryCode?: string;
  isActive: boolean;
  createdAt?: Date;
  updatedAt?: Date;
}

export interface ProxyHealth {
  proxyId: string;
  isHealthy: boolean;
  lastCheckTime: Date;
  successCount: number;
  failureCount: number;
  avgResponseTime: number;
  lastError?: string;
}

export interface ProxyUsage {
  proxyId: string;
  usageCount: number;
  lastUsedAt: Date;
  totalBytes: number;
  errors: number;
}

export interface ProxyStats {
  proxy: ProxyConfig;
  health: ProxyHealth;
  usage: ProxyUsage;
}

export type ProxyRotationStrategy = 'round-robin' | 'random' | 'performance' | 'location';

export interface ProxyUrl {
  url: string;
  proxy: ProxyConfig;
}