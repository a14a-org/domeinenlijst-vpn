#!/bin/bash

export KUBECONFIG=~/.kube/config-prod-platform

echo "=== VPN Proxy API Debugging ==="
echo ""

# 1. Check database entries
echo "1. Database proxy entries:"
kubectl exec postgres-0 -n vpn-proxy -- psql -U vpnproxy -d vpnproxy -c \
  "SELECT id, name, provider, is_active FROM proxy_configs WHERE provider != 'namecheap' ORDER BY provider;" 2>/dev/null

echo ""
echo "2. Health status in database:"
kubectl exec postgres-0 -n vpn-proxy -- psql -U vpnproxy -d vpnproxy -c \
  "SELECT pc.name, ph.is_healthy, ph.success_count, ph.failure_count, ph.last_check_time 
   FROM proxy_configs pc 
   LEFT JOIN proxy_health ph ON pc.id = ph.proxy_id 
   WHERE pc.provider != 'namecheap' 
   ORDER BY pc.provider, pc.name;" 2>/dev/null

echo ""
echo "3. Testing individual proxies:"
for pod in vpn-proxy-surfshark-0 vpn-proxy-nordvpn-0; do
    echo -n "   $pod: "
    if kubectl exec $pod -n vpn-proxy -- curl -s -x socks5h://localhost:1080 https://ipinfo.io/ip --max-time 3 >/dev/null 2>&1; then
        echo "✅ Working"
    else
        echo "❌ Failed"
    fi
done

echo ""
echo "4. API endpoints test:"
echo -n "   Health: "
kubectl run -it --rm test-health --image=curlimages/curl --restart=Never -n vpn-proxy -- \
  curl -s http://vpn-proxy-api/api/v1/health 2>/dev/null | jq -r '.status' 2>/dev/null || echo "Failed"

echo -n "   Ready: "
kubectl run -it --rm test-ready --image=curlimages/curl --restart=Never -n vpn-proxy -- \
  curl -s http://vpn-proxy-api/api/v1/ready 2>/dev/null | jq -r '.ready' 2>/dev/null || echo "Failed"

echo -n "   Proxy: "
kubectl run -it --rm test-proxy --image=curlimages/curl --restart=Never -n vpn-proxy -- \
  curl -s http://vpn-proxy-api/api/v1/proxy 2>/dev/null | jq -r '.error // .url' 2>/dev/null || echo "Failed"

echo ""
echo "5. Recent API logs:"
kubectl logs -l app=vpn-proxy-api -n vpn-proxy --tail=50 | grep -E "(Loaded.*proxies|health check|getHealthyProxies)" | tail -5

echo ""
echo "=== Summary ==="
echo "If proxies work individually but API returns 'No healthy proxies',"
echo "the issue is likely in the ProxyManager logic or data loading."