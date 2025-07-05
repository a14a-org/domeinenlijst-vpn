#!/bin/bash
set -e

echo "Starting VPN Proxy Container..."

# Validate required environment variables
if [ -z "$VPN_PROVIDER" ]; then
    echo "Error: VPN_PROVIDER not set"
    exit 1
fi

# Check if we have a selected config from init container
if [ -f "/tmp/selected-vpn-config" ]; then
    VPN_CONFIG=$(cat /tmp/selected-vpn-config)
    echo "Using VPN config from init container: $VPN_CONFIG"
elif [ -z "$VPN_CONFIG" ]; then
    echo "Error: VPN_CONFIG not set"
    exit 1
fi

# Setup VPN configuration based on provider
case "$VPN_PROVIDER" in
    "surfshark")
        if [ -z "$SURFSHARK_USERNAME" ] || [ -z "$SURFSHARK_PASSWORD" ]; then
            echo "Error: SURFSHARK_USERNAME and SURFSHARK_PASSWORD must be set"
            exit 1
        fi
        echo "Configuring Surfshark VPN..."
        ;;
    "nordvpn")
        if [ -z "$NORDVPN_USERNAME" ] || [ -z "$NORDVPN_PASSWORD" ]; then
            echo "Error: NORDVPN_USERNAME and NORDVPN_PASSWORD must be set"
            exit 1
        fi
        echo "Configuring NordVPN..."
        ;;
    "namecheap")
        if [ -z "$NAMECHEAP_USERNAME" ] || [ -z "$NAMECHEAP_PASSWORD" ]; then
            echo "Error: NAMECHEAP_USERNAME and NAMECHEAP_PASSWORD must be set"
            exit 1
        fi
        echo "Configuring Namecheap VPN..."
        ;;
    *)
        echo "Error: Unknown VPN_PROVIDER: $VPN_PROVIDER"
        exit 1
        ;;
esac

# Copy VPN configuration
echo "Using VPN config: $VPN_CONFIG"
if [ ! -f "/etc/openvpn-configs/${VPN_PROVIDER}/${VPN_CONFIG}" ]; then
    echo "Error: VPN config file not found"
    exit 1
fi

cp "/etc/openvpn-configs/${VPN_PROVIDER}/${VPN_CONFIG}" /etc/openvpn/client.conf

# Create auth file based on provider
case "$VPN_PROVIDER" in
    "surfshark")
        echo "$SURFSHARK_USERNAME" > /etc/openvpn/auth.txt
        echo "$SURFSHARK_PASSWORD" >> /etc/openvpn/auth.txt
        ;;
    "nordvpn")
        echo "$NORDVPN_USERNAME" > /etc/openvpn/auth.txt
        echo "$NORDVPN_PASSWORD" >> /etc/openvpn/auth.txt
        ;;
    "namecheap")
        echo "$NAMECHEAP_USERNAME" > /etc/openvpn/auth.txt
        echo "$NAMECHEAP_PASSWORD" >> /etc/openvpn/auth.txt
        ;;
esac

# Update OpenVPN config to use auth file
echo "auth-user-pass /etc/openvpn/auth.txt" >> /etc/openvpn/client.conf

# Start OpenVPN daemon
echo "Starting OpenVPN..."
openvpn --config /etc/openvpn/client.conf --daemon

# Wait for VPN connection
echo "Waiting for VPN connection..."
for i in {1..30}; do
    if ip link show tun0 &> /dev/null; then
        echo "VPN connected!"
        break
    fi
    echo "Waiting for tun0 interface... ($i/30)"
    sleep 2
done

if ! ip link show tun0 &> /dev/null; then
    echo "Error: VPN connection failed"
    exit 1
fi

# Get VPN IP
VPN_IP=$(ip addr show tun0 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
echo "VPN IP: $VPN_IP"

# Enable IP forwarding
echo "Enabling IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward

# Configure iptables for SOCKS5 proxy
echo "Configuring iptables..."
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT
iptables -A FORWARD -i tun0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Start Dante SOCKS5 server
echo "Starting Dante SOCKS5 server..."
# Try sockd first, fall back to danted
if command -v sockd &> /dev/null; then
    sockd -f /etc/dante.conf
elif command -v danted &> /dev/null; then
    danted -f /etc/dante.conf
else
    echo "Error: Neither sockd nor danted found"
    exit 1
fi

# Monitor services
echo "VPN Proxy container started successfully"
while true; do
    # Check if OpenVPN is running
    if ! pgrep openvpn > /dev/null; then
        echo "OpenVPN died, restarting..."
        openvpn --config /etc/openvpn/client.conf --daemon
    fi
    
    # Check if Dante is running
    if ! pgrep -f "dante|sockd" > /dev/null; then
        echo "Dante died, restarting..."
        if command -v sockd &> /dev/null; then
            sockd -f /etc/dante.conf
        else
            danted -f /etc/dante.conf
        fi
    fi
    
    sleep 10
done