import { Pool } from 'pg';

export async function initializeDatabase(db: Pool): Promise<void> {
  // Create tables if they don't exist
  await db.query(`
    CREATE TABLE IF NOT EXISTS proxy_configs (
      id VARCHAR(50) PRIMARY KEY,
      name VARCHAR(100) NOT NULL,
      provider VARCHAR(20) NOT NULL CHECK (provider IN ('surfshark', 'nordvpn', 'namecheap')),
      host VARCHAR(255) NOT NULL,
      port INTEGER NOT NULL,
      location VARCHAR(100),
      country_code VARCHAR(2),
      is_active BOOLEAN DEFAULT true,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS proxy_health (
      proxy_id VARCHAR(50) PRIMARY KEY REFERENCES proxy_configs(id) ON DELETE CASCADE,
      is_healthy BOOLEAN DEFAULT true,
      last_check_time TIMESTAMP DEFAULT NOW(),
      success_count INTEGER DEFAULT 0,
      failure_count INTEGER DEFAULT 0,
      avg_response_time NUMERIC DEFAULT 0,
      last_error TEXT,
      updated_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS proxy_usage (
      proxy_id VARCHAR(50) PRIMARY KEY REFERENCES proxy_configs(id) ON DELETE CASCADE,
      usage_count INTEGER DEFAULT 0,
      last_used_at TIMESTAMP DEFAULT NOW(),
      total_bytes BIGINT DEFAULT 0,
      errors INTEGER DEFAULT 0,
      created_at TIMESTAMP DEFAULT NOW(),
      updated_at TIMESTAMP DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS proxy_usage_log (
      id SERIAL PRIMARY KEY,
      proxy_id VARCHAR(50) REFERENCES proxy_configs(id) ON DELETE CASCADE,
      timestamp TIMESTAMP DEFAULT NOW(),
      success BOOLEAN DEFAULT true,
      response_time INTEGER,
      bytes_transferred BIGINT DEFAULT 0,
      error_message TEXT,
      client_id VARCHAR(100)
    );

    CREATE INDEX IF NOT EXISTS idx_proxy_health_is_healthy ON proxy_health(is_healthy);
    CREATE INDEX IF NOT EXISTS idx_proxy_configs_is_active ON proxy_configs(is_active);
    CREATE INDEX IF NOT EXISTS idx_proxy_configs_country_code ON proxy_configs(country_code);
    CREATE INDEX IF NOT EXISTS idx_proxy_usage_log_timestamp ON proxy_usage_log(timestamp);
    CREATE INDEX IF NOT EXISTS idx_proxy_usage_log_proxy_id ON proxy_usage_log(proxy_id);
  `);

  // Create or replace the performance stats view
  await db.query(`
    CREATE OR REPLACE VIEW proxy_performance_stats AS
    SELECT 
      pc.id,
      pc.name,
      pc.provider,
      pc.location,
      pc.country_code,
      pc.is_active,
      ph.is_healthy,
      ph.last_check_time,
      ph.success_count,
      ph.failure_count,
      ph.avg_response_time,
      pu.usage_count,
      pu.last_used_at,
      CASE 
        WHEN ph.success_count + ph.failure_count > 0 
        THEN ph.success_count::float / (ph.success_count + ph.failure_count) * 100
        ELSE 0 
      END as success_rate,
      CASE
        WHEN ph.is_healthy AND pc.is_active THEN 
          (ph.success_count::float / GREATEST(ph.success_count + ph.failure_count, 1)) * 
          (1000.0 / GREATEST(ph.avg_response_time, 1))
        ELSE 0
      END as performance_score
    FROM proxy_configs pc
    LEFT JOIN proxy_health ph ON pc.id = ph.proxy_id
    LEFT JOIN proxy_usage pu ON pc.id = pu.proxy_id
    ORDER BY performance_score DESC;
  `);

  // Insert initial proxy configurations if they don't exist
  await insertInitialProxyConfigs(db);
}

async function insertInitialProxyConfigs(db: Pool): Promise<void> {
  // Check if we already have proxy configs
  const { rows } = await db.query('SELECT COUNT(*) FROM proxy_configs');
  if (parseInt(rows[0].count) > 0) {
    return; // Already initialized
  }

  // Insert default proxy configurations based on the VPN containers
  const proxyConfigs = [
    // Surfshark proxies
    { id: 'surfshark-nl1', name: 'Surfshark Netherlands 1', provider: 'surfshark', host: 'vpn-proxy-surfshark-nl1', port: 1080, location: 'Amsterdam', country_code: 'NL' },
    { id: 'surfshark-nl2', name: 'Surfshark Netherlands 2', provider: 'surfshark', host: 'vpn-proxy-surfshark-nl2', port: 1080, location: 'Amsterdam', country_code: 'NL' },
    { id: 'surfshark-nl3', name: 'Surfshark Netherlands 3', provider: 'surfshark', host: 'vpn-proxy-surfshark-nl3', port: 1080, location: 'Amsterdam', country_code: 'NL' },
    { id: 'surfshark-de1', name: 'Surfshark Germany 1', provider: 'surfshark', host: 'vpn-proxy-surfshark-de1', port: 1080, location: 'Frankfurt', country_code: 'DE' },
    { id: 'surfshark-be1', name: 'Surfshark Belgium 1', provider: 'surfshark', host: 'vpn-proxy-surfshark-be1', port: 1080, location: 'Brussels', country_code: 'BE' },
    { id: 'surfshark-uk1', name: 'Surfshark UK 1', provider: 'surfshark', host: 'vpn-proxy-surfshark-uk1', port: 1080, location: 'London', country_code: 'GB' },
    { id: 'surfshark-fr1', name: 'Surfshark France 1', provider: 'surfshark', host: 'vpn-proxy-surfshark-fr1', port: 1080, location: 'Paris', country_code: 'FR' },
    
    // NordVPN proxies
    { id: 'nordvpn-nl1', name: 'NordVPN Netherlands 1', provider: 'nordvpn', host: 'vpn-proxy-nordvpn-nl1', port: 1080, location: 'Amsterdam', country_code: 'NL' },
    { id: 'nordvpn-nl2', name: 'NordVPN Netherlands 2', provider: 'nordvpn', host: 'vpn-proxy-nordvpn-nl2', port: 1080, location: 'Amsterdam', country_code: 'NL' },
    
    // Namecheap proxies
    { id: 'namecheap-nl1', name: 'Namecheap Netherlands 1', provider: 'namecheap', host: 'vpn-proxy-namecheap-nl1', port: 1080, location: 'Amsterdam', country_code: 'NL' },
    { id: 'namecheap-de1', name: 'Namecheap Germany 1', provider: 'namecheap', host: 'vpn-proxy-namecheap-de1', port: 1080, location: 'Frankfurt', country_code: 'DE' },
    { id: 'namecheap-uk1', name: 'Namecheap UK 1', provider: 'namecheap', host: 'vpn-proxy-namecheap-uk1', port: 1080, location: 'London', country_code: 'GB' },
  ];

  for (const config of proxyConfigs) {
    await db.query(
      `INSERT INTO proxy_configs (id, name, provider, host, port, location, country_code) 
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [config.id, config.name, config.provider, config.host, config.port, config.location, config.country_code]
    );
  }

  console.log(`Inserted ${proxyConfigs.length} proxy configurations`);
}