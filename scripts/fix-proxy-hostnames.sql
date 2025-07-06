-- Fix proxy hostnames for Kubernetes StatefulSet DNS
-- Add .vpn-proxy.svc.cluster.local suffix for proper DNS resolution

-- Update Surfshark proxies to use different pod instances
UPDATE proxy_configs SET host = 'vpn-proxy-surfshark-0.vpn-proxy-surfshark.vpn-proxy.svc.cluster.local' WHERE id = 'surfshark-nl1';
UPDATE proxy_configs SET host = 'vpn-proxy-surfshark-1.vpn-proxy-surfshark.vpn-proxy.svc.cluster.local' WHERE id = 'surfshark-nl2';
UPDATE proxy_configs SET host = 'vpn-proxy-surfshark-2.vpn-proxy-surfshark.vpn-proxy.svc.cluster.local' WHERE id = 'surfshark-nl3';
UPDATE proxy_configs SET host = 'vpn-proxy-surfshark-0.vpn-proxy-surfshark.vpn-proxy.svc.cluster.local' WHERE id = 'surfshark-de1';
UPDATE proxy_configs SET host = 'vpn-proxy-surfshark-1.vpn-proxy-surfshark.vpn-proxy.svc.cluster.local' WHERE id = 'surfshark-be1';
UPDATE proxy_configs SET host = 'vpn-proxy-surfshark-2.vpn-proxy-surfshark.vpn-proxy.svc.cluster.local' WHERE id = 'surfshark-uk1';
UPDATE proxy_configs SET host = 'vpn-proxy-surfshark-0.vpn-proxy-surfshark.vpn-proxy.svc.cluster.local' WHERE id = 'surfshark-fr1';

-- Update NordVPN proxies
UPDATE proxy_configs SET host = 'vpn-proxy-nordvpn-0.vpn-proxy-nordvpn.vpn-proxy.svc.cluster.local' WHERE id = 'nordvpn-nl1';
UPDATE proxy_configs SET host = 'vpn-proxy-nordvpn-1.vpn-proxy-nordvpn.vpn-proxy.svc.cluster.local' WHERE id = 'nordvpn-nl2';

-- Update Namecheap proxies
UPDATE proxy_configs SET host = 'vpn-proxy-namecheap-0.vpn-proxy-namecheap.vpn-proxy.svc.cluster.local' WHERE id = 'namecheap-nl1';
UPDATE proxy_configs SET host = 'vpn-proxy-namecheap-0.vpn-proxy-namecheap.vpn-proxy.svc.cluster.local' WHERE id = 'namecheap-de1';
UPDATE proxy_configs SET host = 'vpn-proxy-namecheap-0.vpn-proxy-namecheap.vpn-proxy.svc.cluster.local' WHERE id = 'namecheap-uk1';

-- Update timestamps
UPDATE proxy_configs SET updated_at = NOW();