#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== VPN Pod Rollout and Monitoring Script ===${NC}"
echo ""

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}kubectl command not found. Please ensure kubectl is installed and configured.${NC}"
        exit 1
    fi
}

# Function to get pod logs with error handling
get_pod_logs() {
    local pod_name=$1
    local lines=${2:-50}
    
    if [ -n "$pod_name" ]; then
        echo -e "${YELLOW}Logs from $pod_name:${NC}"
        kubectl logs -n vpn-proxy "$pod_name" --tail="$lines" 2>/dev/null || echo "Unable to fetch logs"
    else
        echo "No pod found"
    fi
}

# Check kubectl availability
check_kubectl

# Show current status
echo -e "${YELLOW}Current pod status:${NC}"
kubectl get pods -n vpn-proxy -o wide
echo ""

# Ask for confirmation
read -p "Do you want to restart all VPN pods? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Rollout cancelled."
    exit 0
fi

echo ""
echo -e "${GREEN}Starting rollout...${NC}"
echo ""

# Restart StatefulSets
echo "Restarting Surfshark StatefulSet..."
kubectl rollout restart statefulset vpn-proxy-surfshark -n vpn-proxy 2>/dev/null || echo "Surfshark StatefulSet not found"

echo "Restarting Namecheap StatefulSet..."
kubectl rollout restart statefulset vpn-proxy-namecheap -n vpn-proxy 2>/dev/null || echo "Namecheap StatefulSet not found"

echo "Restarting NordVPN StatefulSet..."
kubectl rollout restart statefulset vpn-proxy-nordvpn -n vpn-proxy 2>/dev/null || echo "NordVPN StatefulSet not found"

echo "Restarting API Deployment..."
kubectl rollout restart deployment vpn-proxy-api -n vpn-proxy 2>/dev/null || echo "API Deployment not found"

echo ""
echo -e "${YELLOW}Waiting for rollouts to complete...${NC}"
echo ""

# Monitor rollouts with timeout
echo "Monitoring Surfshark rollout (timeout: 5 minutes)..."
kubectl rollout status statefulset vpn-proxy-surfshark -n vpn-proxy --timeout=300s 2>/dev/null || echo "Surfshark rollout timeout or not found"

echo "Monitoring Namecheap rollout (timeout: 5 minutes)..."
kubectl rollout status statefulset vpn-proxy-namecheap -n vpn-proxy --timeout=300s 2>/dev/null || echo "Namecheap rollout timeout or not found"

echo "Monitoring NordVPN rollout (timeout: 5 minutes)..."
kubectl rollout status statefulset vpn-proxy-nordvpn -n vpn-proxy --timeout=300s 2>/dev/null || echo "NordVPN rollout timeout or not found"

echo "Monitoring API rollout (timeout: 5 minutes)..."
kubectl rollout status deployment vpn-proxy-api -n vpn-proxy --timeout=300s 2>/dev/null || echo "API rollout timeout or not found"

echo ""
echo -e "${GREEN}=== Rollout Complete ===${NC}"
echo ""

# Wait a bit for pods to stabilize
echo "Waiting 10 seconds for pods to stabilize..."
sleep 10

# Show final status
echo -e "${YELLOW}Final pod status:${NC}"
kubectl get pods -n vpn-proxy -o wide
echo ""

# Get pod names for log checking
SURFSHARK_POD=$(kubectl get pods -n vpn-proxy -l provider=surfshark -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
NAMECHEAP_POD=$(kubectl get pods -n vpn-proxy -l provider=namecheap -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
NORDVPN_POD=$(kubectl get pods -n vpn-proxy -l provider=nordvpn -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
API_POD=$(kubectl get pods -n vpn-proxy -l app=vpn-proxy-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# Check logs from each provider
echo -e "${GREEN}=== Checking Surfshark Pod Logs ===${NC}"
get_pod_logs "$SURFSHARK_POD" 50

echo ""
echo -e "${GREEN}=== Checking Namecheap Pod Logs ===${NC}"
get_pod_logs "$NAMECHEAP_POD" 50

echo ""
echo -e "${GREEN}=== Checking NordVPN Pod Logs ===${NC}"
get_pod_logs "$NORDVPN_POD" 30

echo ""
echo -e "${GREEN}=== Checking API Pod Health ===${NC}"
get_pod_logs "$API_POD" 20

echo ""
echo -e "${GREEN}=== Summary ===${NC}"
echo "Checking pod readiness..."
kubectl get pods -n vpn-proxy --no-headers | while read line; do
    pod=$(echo $line | awk '{print $1}')
    ready=$(echo $line | awk '{print $2}')
    status=$(echo $line | awk '{print $3}')
    
    if [[ "$ready" == "1/1" ]] && [[ "$status" == "Running" ]]; then
        echo -e "✅ $pod - ${GREEN}Ready${NC}"
    else
        echo -e "❌ $pod - ${RED}Not Ready ($ready, $status)${NC}"
    fi
done

echo ""
echo "Script complete. Check the logs above for any errors."