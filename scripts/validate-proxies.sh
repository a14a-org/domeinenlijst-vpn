#!/bin/bash

export KUBECONFIG=~/.kube/config-prod-platform

echo "=== VPN Proxy Validation Report ==="
echo "Date: $(date)"
echo ""

# Count ready pods
TOTAL_PODS=$(kubectl get pods -n vpn-proxy | grep -E "(surfshark|nordvpn|namecheap)" | wc -l)
READY_PODS=$(kubectl get pods -n vpn-proxy | grep -E "(surfshark|nordvpn|namecheap)" | grep "1/1" | wc -l)

echo "Pod Status Summary:"
echo "- Total VPN pods: $TOTAL_PODS"
echo "- Ready pods: $READY_PODS"
echo ""

echo "=== Ready VPN Pods ==="
kubectl get pods -n vpn-proxy | grep "1/1" | grep -E "(surfshark|nordvpn|namecheap)" | while read line; do
    POD=$(echo $line | awk '{print $1}')
    echo -n "✅ $POD - "
    
    # Test proxy functionality
    IP=$(kubectl exec $POD -n vpn-proxy -- curl -s -x socks5h://localhost:1080 https://ipinfo.io/ip --max-time 5 2>/dev/null || echo "Failed")
    if [[ "$IP" != "Failed" ]] && [[ -n "$IP" ]]; then
        LOCATION=$(kubectl exec $POD -n vpn-proxy -- curl -s -x socks5h://localhost:1080 https://ipinfo.io/json --max-time 5 2>/dev/null | jq -r '"\(.country)-\(.city)"' 2>/dev/null || echo "Unknown")
        echo "Working ($IP - $LOCATION)"
    else
        echo "Proxy test failed"
    fi
done

echo ""
echo "=== Not Ready VPN Pods ==="
kubectl get pods -n vpn-proxy | grep "0/1" | grep -E "(surfshark|nordvpn|namecheap)" | while read line; do
    POD=$(echo $line | awk '{print $1}')
    RESTARTS=$(echo $line | awk '{print $4}')
    echo "❌ $POD - Restarts: $RESTARTS"
done

echo ""
echo "=== API Service Status ==="
API_READY=$(kubectl get pods -n vpn-proxy | grep "vpn-proxy-api" | grep "1/1" | wc -l)
echo "API pods ready: $API_READY/2"

# Test API health
echo -n "API Health Check: "
kubectl run -it --rm test-api --image=curlimages/curl --restart=Never -n vpn-proxy -- curl -s http://vpn-proxy-api/api/v1/health 2>/dev/null | jq -r '.status' 2>/dev/null || echo "Failed"

echo ""
echo "=== Summary ==="
echo "Working VPN Providers:"
echo -n "- NordVPN: "
kubectl get pods -n vpn-proxy | grep nordvpn | grep "1/1" | wc -l
echo -n "- Surfshark: "
kubectl get pods -n vpn-proxy | grep surfshark | grep "1/1" | wc -l
echo -n "- Namecheap: "
kubectl get pods -n vpn-proxy | grep namecheap | grep "1/1" | wc -l

echo ""
echo "=== Recommendations ==="
if [[ $READY_PODS -lt $TOTAL_PODS ]]; then
    echo "⚠️  Some pods are not ready. Check logs with:"
    echo "   kubectl logs <pod-name> -n vpn-proxy"
fi

echo ""
echo "To test a proxy manually:"
echo "kubectl exec <pod-name> -n vpn-proxy -- curl -x socks5h://localhost:1080 https://ipinfo.io/json"