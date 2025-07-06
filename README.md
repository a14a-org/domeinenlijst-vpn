# Domeinenlijst VPN Proxy Service

![Build Status](https://github.com/a14a-org/domeinenlijst-vpn/actions/workflows/build-and-push.yml/badge.svg)

A Kubernetes-native VPN proxy service that provides SOCKS5 proxies through multiple VPN providers (Surfshark, NordVPN, Namecheap, CyberGhost) for web scraping infrastructure.

## Quick Start

1. Clone the repository
2. Add your VPN configuration files to `vpn-configs/`
3. Create Kubernetes secrets with your VPN credentials
4. Deploy to Kubernetes using the manifests in `k8s/`
5. Access proxies via the API at `http://vpn-proxy-api:3000/api/v1/proxy`

## Architecture

The service consists of:
- **VPN Containers**: Alpine-based containers running OpenVPN + Dante SOCKS5 server
- **API Service**: Node.js/TypeScript REST API for proxy management
- **PostgreSQL Database**: Stores proxy configurations, health metrics, and usage statistics

## Directory Structure

```
domeinenlijst-vpn/
├── docker/                    # Docker build files
│   ├── Dockerfile            # Main container image
│   └── scripts/
│       ├── entrypoint.sh     # VPN container entrypoint
│       └── healthcheck.sh    # Health check script
├── k8s/                      # Kubernetes manifests
│   ├── configmaps/           # Provider-specific ConfigMaps
│   ├── manifests/            # Core Kubernetes resources
│   └── statefulsets/         # VPN StatefulSet definitions
├── src/                      # API service source code
├── vpn-configs/              # VPN configuration files
│   ├── surfshark/            # Surfshark .ovpn files
│   ├── nordvpn/              # NordVPN .ovpn files
│   ├── namecheap/            # Namecheap .ovpn files
│   └── cyberghost/           # CyberGhost configs
│       ├── instance-0/       # First instance
│       ├── instance-1/       # Second instance
│       └── instance-2/       # Third instance
└── scripts/                  # Utility scripts
    └── generate-vpn-configmap.sh
```

## Features

- Multiple VPN provider support (Surfshark, NordVPN, Namecheap, CyberGhost)
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
2. VPN provider credentials (Surfshark, NordVPN, Namecheap, CyberGhost)
3. GitHub container registry access
4. `kubectl` configured to access your cluster

### Setup Steps

1. **Create namespace**:
   ```bash
   kubectl create namespace vpn-proxy
   ```

2. **Add VPN Configuration Files**: 
   ```bash
   # Copy your VPN .ovpn files to the appropriate directories:
   mkdir -p vpn-configs/{surfshark,nordvpn,namecheap,cyberghost}
   # Add your .ovpn files to these directories
   
   # For providers with separate certificate files (like CyberGhost):
   # Place ca.crt, client.crt, and client.key alongside the .ovpn file
   
   # Generate the ConfigMap from the VPN files:
   ./scripts/generate-vpn-configmap.sh
   ```

3. **Create Secrets**: 
   ```bash
   # Create the main credentials secret
   kubectl create secret generic vpn-credentials \
     --from-literal=SURFSHARK_USERNAME=your_username \
     --from-literal=SURFSHARK_PASSWORD=your_password \
     --from-literal=NORDVPN_USERNAME=your_username \
     --from-literal=NORDVPN_PASSWORD=your_password \
     --from-literal=NAMECHEAP_USERNAME=your_username \
     --from-literal=NAMECHEAP_PASSWORD=your_password \
     --from-literal=CYBERGHOST_USERNAME=your_username \
     --from-literal=CYBERGHOST_PASSWORD=your_password \
     --from-literal=DB_PASSWORD=secure_password \
     -n vpn-proxy
   
   # For multiple instances of the same provider (e.g., CyberGhost):
   kubectl patch secret vpn-credentials -n vpn-proxy --type='json' -p='[
     {"op": "add", "path": "/data/CYBERGHOST_USERNAME_1", "value": "'$(echo -n "username2" | base64)'"},
     {"op": "add", "path": "/data/CYBERGHOST_PASSWORD_1", "value": "'$(echo -n "password2" | base64)'"}
   ]'
   ```

4. **Apply Kubernetes manifests**: 
   ```bash
   # Apply ConfigMaps
   kubectl apply -f k8s/manifests/configmap-vpn-configs-generated.yaml
   kubectl apply -f k8s/configmaps/
   
   # Apply other manifests
   kubectl apply -f k8s/manifests/
   ```

5. **Deploy with ArgoCD**: The application will be automatically deployed via ArgoCD when you push to the main branch

6. **Verify Deployment**:
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
- Certificate files (if not embedded in .ovpn)

#### Currently Supported Providers:
- **Surfshark**: Uses embedded certificates in .ovpn files
- **NordVPN**: Uses embedded certificates in .ovpn files  
- **Namecheap**: Uses embedded certificates in .ovpn files
- **CyberGhost**: Requires separate ca.crt, client.crt, and client.key files

### Adding a New VPN Provider

To add a new VPN provider to the system:

1. **Update the entrypoint script** (`docker/scripts/entrypoint.sh`):
   ```bash
   # Add a case for your provider in the VPN_PROVIDER switch
   "newprovider")
       if [ -z "$NEWPROVIDER_USERNAME" ]; then
           echo "Error: NEWPROVIDER_USERNAME is not set"
           exit 1
       fi
       echo "Configuring NewProvider VPN..."
       echo "Username: $NEWPROVIDER_USERNAME"
       ;;
   ```

2. **Add VPN configuration files**:
   ```bash
   # Create provider directory
   mkdir -p vpn-configs/newprovider
   
   # Add .ovpn files and any required certificates
   cp your-config.ovpn vpn-configs/newprovider/
   # If separate certificates are needed:
   cp ca.crt client.crt client.key vpn-configs/newprovider/
   ```

3. **Create Kubernetes ConfigMap**:
   ```yaml
   # k8s/configmaps/newprovider-configs.yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: newprovider-vpn-configs
     namespace: vpn-proxy
   data:
     newprovider_config.ovpn: |
       # Your OpenVPN config here
   ```

4. **Update credentials secret**:
   ```bash
   kubectl patch secret vpn-credentials -n vpn-proxy --type='json' -p='[
     {"op": "add", "path": "/data/NEWPROVIDER_USERNAME", "value": "'$(echo -n "username" | base64)'"},
     {"op": "add", "path": "/data/NEWPROVIDER_PASSWORD", "value": "'$(echo -n "password" | base64)'"}
   ]'
   ```

5. **Create StatefulSet** (k8s/statefulsets/newprovider-vpn.yaml):
   ```yaml
   apiVersion: apps/v1
   kind: StatefulSet
   metadata:
     name: vpn-proxy-newprovider
     namespace: vpn-proxy
   spec:
     # Copy from existing provider and adjust accordingly
   ```

6. **Deploy and test**:
   ```bash
   kubectl apply -f k8s/configmaps/newprovider-configs.yaml
   kubectl apply -f k8s/statefulsets/newprovider-vpn.yaml
   kubectl logs -n vpn-proxy vpn-proxy-newprovider-0
   ```

### Adding Multiple Instances of the Same Provider

For providers that support multiple simultaneous connections (like CyberGhost):

1. **Organize configuration files**:
   ```bash
   vpn-configs/cyberghost/
   ├── instance-0/
   │   ├── openvpn.ovpn
   │   ├── ca.crt
   │   ├── client.crt
   │   └── client.key
   ├── instance-1/
   │   └── ... (same structure)
   └── instance-2/
       └── ... (same structure)
   ```

2. **Create separate ConfigMaps** for each instance
3. **Add numbered credentials** to the secret (e.g., CYBERGHOST_USERNAME_1, CYBERGHOST_USERNAME_2)
4. **Create separate StatefulSets** for each instance

### Updating VPN Credentials

To update credentials for an existing provider:

```bash
# First, encode the new credentials
NEW_USERNAME_BASE64=$(echo -n "new_username" | base64)
NEW_PASSWORD_BASE64=$(echo -n "new_password" | base64)

# Update the secret
kubectl patch secret vpn-credentials -n vpn-proxy --type='json' -p='[
  {"op": "replace", "path": "/data/PROVIDER_USERNAME", "value": "'$NEW_USERNAME_BASE64'"},
  {"op": "replace", "path": "/data/PROVIDER_PASSWORD", "value": "'$NEW_PASSWORD_BASE64'"}
]'

# Restart the affected pods
kubectl delete pod -n vpn-proxy -l provider=providername
```

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

# Check external IP
kubectl exec -n vpn-proxy vpn-proxy-surfshark-0 -- curl -s ifconfig.me
```

### Proxy Health Issues
```bash
# Check proxy statistics
curl http://vpn-proxy-api.vpn-proxy.svc.cluster.local/api/v1/proxy/stats

# Check specific proxy health
kubectl exec -n vpn-proxy vpn-proxy-surfshark-0 -- /healthcheck.sh
```

### Known Issues

- **CyberGhost Support**: Currently, CyberGhost uses the Surfshark provider type as a workaround until the container image is updated with native CyberGhost support in `entrypoint.sh`. This works because both providers use similar OpenVPN configurations.

## License

MIT