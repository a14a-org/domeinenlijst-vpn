#!/bin/bash

# Check 1: VPN connection
if ! ip link show tun0 &> /dev/null; then
    echo "Health check failed: No VPN connection"
    exit 1
fi

echo "VPN connection OK (tun0 exists)"

# Check 2: SOCKS5 proxy is listening
if ! netstat -tln | grep -q ":1080 "; then
    echo "Health check failed: SOCKS5 proxy not listening on port 1080"
    echo "Current listening ports:"
    netstat -tln | grep LISTEN
    echo "Dante process check:"
    ps aux | grep -E "(dante|sockd)" | grep -v grep
    exit 1
fi

echo "SOCKS5 proxy listening OK"

# Check 3: Test SOCKS5 proxy functionality
# Try to connect through the proxy
HTTP_CODE=$(timeout 5 curl -x socks5h://localhost:1080 -s -o /dev/null -w "%{http_code}" https://api.ipify.org 2>&1) || {
    echo "Health check failed: Cannot connect through SOCKS5 proxy"
    echo "Curl exit code: $?"
    echo "HTTP code: $HTTP_CODE"
    echo "Testing direct connection:"
    curl -s https://api.ipify.org || echo "Direct connection also failed"
    exit 1
}

echo "Health check passed (HTTP code: $HTTP_CODE)"
exit 0