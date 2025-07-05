#!/bin/bash

# This script is used by supervisor to start Dante only after VPN is ready

echo "Checking if VPN is ready..."

# Wait for tun0 interface
while ! ip link show tun0 &> /dev/null; do
    echo "Waiting for VPN connection (tun0)..."
    sleep 2
done

echo "VPN is ready, starting Dante..."
supervisorctl start dante

exit 0