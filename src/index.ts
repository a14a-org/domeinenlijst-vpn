import express from 'express';
import { Pool } from 'pg';
import pino from 'pino';
import dotenv from 'dotenv';
import { ProxyManager } from './proxy-manager/ProxyManager';
import { createProxyRoutes } from './api/routes';
import { initializeDatabase } from './database/init';

dotenv.config();

const logger = pino({
  transport: {
    target: 'pino-pretty',
    options: {
      colorize: true
    }
  }
});

async function main() {
  // Database configuration
  const dbConfig = {
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432'),
    database: process.env.DB_NAME || 'vpnproxy',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || 'postgres',
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 2000,
  };

  const db = new Pool(dbConfig);

  try {
    // Test database connection
    await db.query('SELECT NOW()');
    logger.info('Database connected successfully');

    // Initialize database schema
    await initializeDatabase(db);
    logger.info('Database schema initialized');

    // Initialize proxy manager
    const proxyManager = new ProxyManager(db);
    await proxyManager.initialize();
    logger.info('Proxy manager initialized');

    // Create Express app
    const app = express();
    app.use(express.json());

    // Add request logging
    app.use((req, res, next) => {
      logger.info({ method: req.method, url: req.url }, 'Incoming request');
      next();
    });

    // Mount proxy routes
    app.use('/api/v1', createProxyRoutes(proxyManager));

    // Error handling
    app.use((err: Error, req: express.Request, res: express.Response, next: express.NextFunction) => {
      logger.error({ error: err.message, stack: err.stack }, 'Unhandled error');
      res.status(500).json({ error: 'Internal server error' });
    });

    // Start server
    const port = parseInt(process.env.PORT || '3000');
    app.listen(port, '0.0.0.0', () => {
      logger.info(`VPN Proxy Service listening on port ${port}`);
    });

    // Graceful shutdown
    process.on('SIGTERM', async () => {
      logger.info('SIGTERM received, shutting down gracefully');
      await db.end();
      process.exit(0);
    });

    process.on('SIGINT', async () => {
      logger.info('SIGINT received, shutting down gracefully');
      await db.end();
      process.exit(0);
    });

  } catch (error) {
    logger.error({ error }, 'Failed to start application');
    process.exit(1);
  }
}

main().catch(error => {
  logger.error({ error }, 'Unhandled error in main');
  process.exit(1);
});