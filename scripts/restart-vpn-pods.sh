#!/bin/bash

echo "=== Restarting VPN Pods with Updated Image ==="
echo ""

# Check current status first
echo "Current pod status:"
kubectl get pods -n vpn-proxy
echo ""

# Restart StatefulSets
echo "Restarting Surfshark StatefulSet..."
kubectl rollout restart statefulset vpn-proxy-surfshark -n vpn-proxy

echo "Restarting Namecheap StatefulSet..."
kubectl rollout restart statefulset vpn-proxy-namecheap -n vpn-proxy

echo "Restarting NordVPN StatefulSet..."
kubectl rollout restart statefulset vpn-proxy-nordvpn -n vpn-proxy

echo "Restarting API Deployment..."
kubectl rollout restart deployment vpn-proxy-api -n vpn-proxy

echo ""
echo "Waiting for rollouts to complete..."
echo ""

# Monitor the rollout status
echo "Monitoring Surfshark rollout..."
kubectl rollout status statefulset vpn-proxy-surfshark -n vpn-proxy --timeout=300s

echo "Monitoring Namecheap rollout..."
kubectl rollout status statefulset vpn-proxy-namecheap -n vpn-proxy --timeout=300s

echo "Monitoring NordVPN rollout..."
kubectl rollout status statefulset vpn-proxy-nordvpn -n vpn-proxy --timeout=300s

echo "Monitoring API rollout..."
kubectl rollout status deployment vpn-proxy-api -n vpn-proxy --timeout=300s

echo ""
echo "=== Rollout Complete ==="
echo ""

# Show final status
echo "Final pod status:"
kubectl get pods -n vpn-proxy
echo ""

# Check logs from one of each provider to see if our fixes are working
echo "=== Checking Surfshark Pod Logs ==="
kubectl logs -n vpn-proxy $(kubectl get pods -n vpn-proxy -l provider=surfshark -o jsonpath='{.items[0].metadata.name}') --tail=50

echo ""
echo "=== Checking Namecheap Pod Logs ==="
kubectl logs -n vpn-proxy $(kubectl get pods -n vpn-proxy -l provider=namecheap -o jsonpath='{.items[0].metadata.name}') --tail=50

echo ""
echo "=== Checking API Pod Health ==="
kubectl logs -n vpn-proxy $(kubectl get pods -n vpn-proxy -l app=vpn-proxy-api -o jsonpath='{.items[0].metadata.name}') --tail=20