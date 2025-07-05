import { Router, Request, Response } from 'express';
import { ProxyManager } from '../proxy-manager/ProxyManager';
import { ProxyRotationStrategy } from '../models/proxy';
import Joi from 'joi';

export function createProxyRoutes(proxyManager: ProxyManager): Router {
  const router = Router();

  // Get next available proxy
  router.get('/proxy', async (req: Request, res: Response) => {
    try {
      const schema = Joi.object({
        strategy: Joi.string().valid('round-robin', 'random', 'performance', 'location').optional(),
        countryCode: Joi.string().length(2).uppercase().optional()
      });

      const { error, value } = schema.validate(req.query);
      if (error) {
        return res.status(400).json({ error: error.details[0].message });
      }

      const strategy = (value.strategy as ProxyRotationStrategy) || 'round-robin';
      const proxyUrl = await proxyManager.getNextProxy(strategy, value.countryCode);
      
      if (!proxyUrl) {
        return res.status(503).json({ error: 'No healthy proxies available' });
      }

      res.json({
        url: proxyUrl.url,
        proxy: {
          id: proxyUrl.proxy.id,
          name: proxyUrl.proxy.name,
          provider: proxyUrl.proxy.provider,
          location: proxyUrl.proxy.location,
          countryCode: proxyUrl.proxy.countryCode
        }
      });
    } catch (error) {
      console.error('Error getting proxy:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // Get random proxy
  router.get('/proxy/random', async (req: Request, res: Response) => {
    try {
      const proxyUrl = await proxyManager.getNextProxy('random');
      
      if (!proxyUrl) {
        return res.status(503).json({ error: 'No healthy proxies available' });
      }

      res.json({
        url: proxyUrl.url,
        proxy: {
          id: proxyUrl.proxy.id,
          name: proxyUrl.proxy.name,
          provider: proxyUrl.proxy.provider,
          location: proxyUrl.proxy.location,
          countryCode: proxyUrl.proxy.countryCode
        }
      });
    } catch (error) {
      console.error('Error getting random proxy:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // Get proxy by country
  router.get('/proxy/geo/:countryCode', async (req: Request, res: Response) => {
    try {
      const countryCode = req.params.countryCode.toUpperCase();
      
      if (countryCode.length !== 2) {
        return res.status(400).json({ error: 'Country code must be 2 characters' });
      }

      const proxyUrl = await proxyManager.getNextProxy('location', countryCode);
      
      if (!proxyUrl) {
        return res.status(503).json({ error: `No healthy proxies available for country ${countryCode}` });
      }

      res.json({
        url: proxyUrl.url,
        proxy: {
          id: proxyUrl.proxy.id,
          name: proxyUrl.proxy.name,
          provider: proxyUrl.proxy.provider,
          location: proxyUrl.proxy.location,
          countryCode: proxyUrl.proxy.countryCode
        }
      });
    } catch (error) {
      console.error('Error getting geo proxy:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // Get proxy statistics
  router.get('/proxy/stats', async (req: Request, res: Response) => {
    try {
      const stats = await proxyManager.getProxyStats();
      
      const summary = stats.map(stat => ({
        id: stat.proxy.id,
        name: stat.proxy.name,
        provider: stat.proxy.provider,
        location: stat.proxy.location,
        countryCode: stat.proxy.countryCode,
        isActive: stat.proxy.isActive,
        health: {
          isHealthy: stat.health.isHealthy,
          lastCheckTime: stat.health.lastCheckTime,
          successRate: stat.health.successCount / (stat.health.successCount + stat.health.failureCount) || 0,
          avgResponseTime: Math.round(stat.health.avgResponseTime),
          lastError: stat.health.lastError
        },
        usage: {
          usageCount: stat.usage.usageCount,
          lastUsedAt: stat.usage.lastUsedAt
        }
      }));

      res.json({
        totalProxies: stats.length,
        healthyProxies: stats.filter(s => s.health.isHealthy).length,
        proxies: summary
      });
    } catch (error) {
      console.error('Error getting proxy stats:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // Report proxy error
  router.post('/proxy/:proxyId/error', async (req: Request, res: Response) => {
    try {
      const { proxyId } = req.params;
      const { error } = req.body;

      if (!error) {
        return res.status(400).json({ error: 'Error message is required' });
      }

      await proxyManager.markProxyAsUnhealthy(proxyId, error);
      res.json({ message: 'Proxy marked as unhealthy' });
    } catch (error) {
      console.error('Error reporting proxy error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  });

  // Health check endpoint
  router.get('/health', (req: Request, res: Response) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
  });

  // Ready check endpoint
  router.get('/ready', async (req: Request, res: Response) => {
    try {
      const stats = await proxyManager.getProxyStats();
      const healthyProxies = stats.filter(s => s.health.isHealthy).length;
      
      if (healthyProxies === 0) {
        return res.status(503).json({ 
          status: 'not ready', 
          reason: 'No healthy proxies available' 
        });
      }

      res.json({ 
        status: 'ready', 
        healthyProxies,
        totalProxies: stats.length 
      });
    } catch (error) {
      res.status(503).json({ 
        status: 'not ready', 
        error: 'Failed to check proxy status' 
      });
    }
  });

  return router;
}