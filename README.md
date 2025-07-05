# Domeinenlijst VPN Proxy Service

A Kubernetes-native VPN proxy service that provides SOCKS5 proxies through multiple VPN providers (Surfshark, NordVPN, Namecheap) for web scraping infrastructure.

## Architecture

The service consists of:
- **VPN Containers**: Alpine-based containers running OpenVPN + Dante SOCKS5 server
- **API Service**: Node.js/TypeScript REST API for proxy management
- **PostgreSQL Database**: Stores proxy configurations, health metrics, and usage statistics

## Features

- Multiple VPN provider support (Surfshark, NordVPN, Namecheap)
- Automatic health monitoring and failover
- Multiple rotation strategies:
  - Round-robin
  - Random selection
  - Performance-based (weighted by success rate and response time)
  - Location-based (by country code)
- REST API for proxy management
- Kubernetes-native with StatefulSets for VPN containers
- Prometheus-ready metrics endpoints
- Automatic CI/CD with GitHub Actions and ArgoCD

## API Endpoints

- `GET /api/v1/proxy` - Get next available proxy
  - Query params: `strategy` (round-robin|random|performance|location), `countryCode` (2-letter ISO)
- `GET /api/v1/proxy/random` - Get random proxy
- `GET /api/v1/proxy/geo/{countryCode}` - Get proxy from specific country
- `GET /api/v1/proxy/stats` - Get proxy statistics
- `POST /api/v1/proxy/{proxyId}/error` - Report proxy error
- `GET /api/v1/health` - Health check
- `GET /api/v1/ready` - Readiness check

## Deployment

### Prerequisites

1. Kubernetes cluster with ArgoCD installed
2. VPN provider credentials (Surfshark, NordVPN, Namecheap)
3. GitHub container registry access

### Setup Steps

1. **Add VPN Configuration Files**: 
   ```bash
   # Copy your VPN .ovpn files to the appropriate directories:
   mkdir -p vpn-configs/{surfshark,nordvpn,namecheap}
   # Add your .ovpn files to these directories
   
   # Generate the ConfigMap from the VPN files:
   ./scripts/generate-vpn-configmap.sh
   ```

2. **Update Secrets**: Create the secret with your VPN credentials:
   ```bash
   kubectl create secret generic vpn-credentials \
     --from-literal=SURFSHARK_USERNAME=your_username \
     --from-literal=SURFSHARK_PASSWORD=your_password \
     --from-literal=NORDVPN_USERNAME=your_username \
     --from-literal=NORDVPN_PASSWORD=your_password \
     --from-literal=NAMECHEAP_USERNAME=your_username \
     --from-literal=NAMECHEAP_PASSWORD=your_password \
     --from-literal=DB_PASSWORD=secure_password \
     -n vpn-proxy
   ```

2. **Apply the generated ConfigMap**: 
   ```bash
   kubectl apply -f k8s/manifests/configmap-vpn-configs-generated.yaml
   ```

3. **Deploy with ArgoCD**: The application will be automatically deployed via ArgoCD when you push to the main branch

4. **Verify Deployment**:
   ```bash
   kubectl get pods -n vpn-proxy
   kubectl logs -n vpn-proxy -l app=vpn-proxy-api
   ```

## Local Development

1. **Install dependencies**:
   ```bash
   npm install
   ```

2. **Set environment variables**:
   ```bash
   cp .env.example .env
   # Edit .env with your database credentials
   ```

3. **Run development server**:
   ```bash
   npm run dev
   ```

4. **Run tests**:
   ```bash
   npm test
   ```

## Configuration

### Environment Variables

- `DB_HOST` - PostgreSQL host
- `DB_PORT` - PostgreSQL port (default: 5432)
- `DB_NAME` - Database name (default: vpnproxy)
- `DB_USER` - Database user
- `DB_PASSWORD` - Database password
- `PORT` - API server port (default: 3000)

### VPN Providers

Each VPN provider requires:
- Username and password credentials
- OpenVPN configuration files (.ovpn)
- Proper DNS configuration

## Monitoring

The service exposes:
- Health endpoints for Kubernetes probes
- Proxy statistics including success rates and response times
- Usage metrics per proxy

## Security Considerations

- VPN containers run with NET_ADMIN capability (required for VPN)
- Credentials stored in Kubernetes secrets
- No authentication on SOCKS5 proxies (rely on network isolation)
- API service runs as non-root user

## Troubleshooting

### VPN Connection Issues
```bash
# Check VPN container logs
kubectl logs -n vpn-proxy vpn-proxy-surfshark-0

# Check if tun0 interface exists
kubectl exec -n vpn-proxy vpn-proxy-surfshark-0 -- ip link show tun0
```

### Proxy Health Issues
```bash
# Check proxy statistics
curl http://vpn-proxy-api.vpn-proxy.svc.cluster.local/api/v1/proxy/stats

# Check specific proxy health
kubectl exec -n vpn-proxy vpn-proxy-surfshark-0 -- /healthcheck.sh
```

## License

MIT