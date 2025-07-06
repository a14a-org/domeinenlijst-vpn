#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== VPN Pod Status Check ===${NC}"
echo ""

# Check if we can access the cluster
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    echo "You may need to SSH to your cluster or set KUBECONFIG environment variable."
    exit 1
fi

# Show pod status
echo -e "${YELLOW}Current VPN pods:${NC}"
kubectl get pods -n vpn-proxy -o wide 2>/dev/null || {
    echo -e "${RED}Failed to get pods. The namespace 'vpn-proxy' might not exist.${NC}"
    echo "Available namespaces:"
    kubectl get namespaces | grep -E "(vpn|proxy)"
    exit 1
}

echo ""
echo -e "${YELLOW}Pod details:${NC}"
kubectl describe pods -n vpn-proxy | grep -E "(Name:|Status:|Ready:|Restart|Last State:|Message:)" | grep -B1 -A3 "Name:"

echo ""
echo -e "${YELLOW}Recent events:${NC}"
kubectl get events -n vpn-proxy --sort-by='.lastTimestamp' | tail -10

echo ""
echo -e "${GREEN}To restart the pods with the new image, run:${NC}"
echo "./scripts/monitor-vpn-rollout.sh"