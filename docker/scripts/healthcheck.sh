#!/bin/bash

# Check 1: VPN connection
if ! ip link show tun0 &> /dev/null; then
    echo "Health check failed: No VPN connection"
    exit 1
fi

# Check 2: SOCKS5 proxy is listening
if ! netstat -tln | grep -q ":1080 "; then
    echo "Health check failed: SOCKS5 proxy not listening"
    exit 1
fi

# Check 3: Test SOCKS5 proxy functionality
# Try to connect through the proxy
if ! timeout 5 curl -x socks5h://localhost:1080 -s -o /dev/null -w "%{http_code}" https://api.ipify.org > /dev/null; then
    echo "Health check failed: Cannot connect through SOCKS5 proxy"
    exit 1
fi

echo "Health check passed"
exit 0