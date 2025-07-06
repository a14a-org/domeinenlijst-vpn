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
        echo "Username: ${SURFSHARK_USERNAME}"
        ;;
    "nordvpn")
        # Check provider-specific first, then fall back to SURFSHARK_ for compatibility
        if [ -z "$NORDVPN_USERNAME" ] && [ -z "$SURFSHARK_USERNAME" ]; then
            echo "Error: Neither NORDVPN_USERNAME nor SURFSHARK_USERNAME is set"
            exit 1
        fi
        if [ -z "$NORDVPN_PASSWORD" ] && [ -z "$SURFSHARK_PASSWORD" ]; then
            echo "Error: Neither NORDVPN_PASSWORD nor SURFSHARK_PASSWORD is set"
            exit 1
        fi
        echo "Configuring NordVPN..."
        echo "Username: ${NORDVPN_USERNAME:-$SURFSHARK_USERNAME}"
        ;;
    "namecheap")
        # Check provider-specific first, then fall back to SURFSHARK_ for compatibility
        if [ -z "$NAMECHEAP_USERNAME" ] && [ -z "$SURFSHARK_USERNAME" ]; then
            echo "Error: Neither NAMECHEAP_USERNAME nor SURFSHARK_USERNAME is set"
            exit 1
        fi
        if [ -z "$NAMECHEAP_PASSWORD" ] && [ -z "$SURFSHARK_PASSWORD" ]; then
            echo "Error: Neither NAMECHEAP_PASSWORD nor SURFSHARK_PASSWORD is set"
            exit 1
        fi
        echo "Configuring Namecheap VPN..."
        echo "Username: ${NAMECHEAP_USERNAME:-$SURFSHARK_USERNAME}"
        ;;
    *)
        echo "Error: Unknown VPN_PROVIDER: $VPN_PROVIDER"
        exit 1
        ;;
esac

# Copy VPN configuration
echo "Using VPN config: $VPN_CONFIG"
# Convert the config filename to the ConfigMap key format
CONFIG_KEY=$(echo "${VPN_PROVIDER}_${VPN_CONFIG}" | sed 's/[\/\-]/_/g')
if [ ! -f "/etc/openvpn-configs/${CONFIG_KEY}" ]; then
    echo "Error: VPN config file not found at /etc/openvpn-configs/${CONFIG_KEY}"
    exit 1
fi

cp "/etc/openvpn-configs/${CONFIG_KEY}" /etc/openvpn/client.conf

# Create auth file based on provider
# Note: For compatibility, also check SURFSHARK_USERNAME/PASSWORD for all providers
case "$VPN_PROVIDER" in
    "surfshark")
        echo "${SURFSHARK_USERNAME}" > /etc/openvpn/auth.txt
        echo "${SURFSHARK_PASSWORD}" >> /etc/openvpn/auth.txt
        ;;
    "nordvpn")
        # Try provider-specific first, fall back to SURFSHARK_ for compatibility
        USERNAME="${NORDVPN_USERNAME:-$SURFSHARK_USERNAME}"
        PASSWORD="${NORDVPN_PASSWORD:-$SURFSHARK_PASSWORD}"
        echo "$USERNAME" > /etc/openvpn/auth.txt
        echo "$PASSWORD" >> /etc/openvpn/auth.txt
        ;;
    "namecheap")
        # Try provider-specific first, fall back to SURFSHARK_ for compatibility
        USERNAME="${NAMECHEAP_USERNAME:-$SURFSHARK_USERNAME}"
        PASSWORD="${NAMECHEAP_PASSWORD:-$SURFSHARK_PASSWORD}"
        echo "$USERNAME" > /etc/openvpn/auth.txt
        echo "$PASSWORD" >> /etc/openvpn/auth.txt
        ;;
esac

# Update OpenVPN config to use auth file
echo "auth-user-pass /etc/openvpn/auth.txt" >> /etc/openvpn/client.conf

# Prevent OpenVPN from modifying resolv.conf
echo "pull-filter ignore \"dhcp-option DNS\"" >> /etc/openvpn/client.conf

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
# Check which dante binary is available
if command -v sockd &> /dev/null; then
    echo "Found sockd binary"
    DANTE_CMD="sockd"
elif command -v danted &> /dev/null; then
    echo "Found danted binary"
    DANTE_CMD="danted"
else
    echo "Error: Neither sockd nor danted found"
    # List available binaries for debugging
    echo "Available binaries in /usr/sbin:"
    ls -la /usr/sbin/ | grep -i dante || true
    echo "Available binaries in /usr/bin:"
    ls -la /usr/bin/ | grep -i dante || true
    exit 1
fi

# Start Dante with debugging
echo "Starting $DANTE_CMD with config /etc/dante.conf"
$DANTE_CMD -f /etc/dante.conf -d 2

# Give it a moment to start
sleep 2

# Check if it's running
if pgrep -f "$DANTE_CMD" > /dev/null; then
    echo "Dante started successfully"
    netstat -tln | grep 1080 || echo "Warning: Port 1080 not listening yet"
else
    echo "Error: Dante failed to start"
    echo "Checking logs..."
    cat /var/log/dante.log 2>/dev/null || echo "No log file found"
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
    if ! pgrep -f "$DANTE_CMD" > /dev/null; then
        echo "Dante died, restarting..."
        $DANTE_CMD -f /etc/dante.conf -d 2
    fi
    
    sleep 10
done