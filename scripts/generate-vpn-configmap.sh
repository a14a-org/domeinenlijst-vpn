#!/bin/bash

# Script to generate Kubernetes ConfigMap from VPN configuration files

set -e

OUTPUT_FILE="k8s/manifests/configmap-vpn-configs-generated.yaml"

cat > "$OUTPUT_FILE" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: vpn-configs
  namespace: vpn-proxy
data:
EOF

# Function to add a VPN config file to the ConfigMap
add_vpn_config() {
    local provider=$1
    local filename=$2
    local filepath="vpn-configs/$provider/$filename"
    
    if [ -f "$filepath" ]; then
        echo "  $provider/$filename: |" >> "$OUTPUT_FILE"
        # Indent each line with 4 spaces for YAML formatting
        sed 's/^/    /' "$filepath" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    else
        echo "Warning: $filepath not found"
    fi
}

# Add Surfshark configurations
add_vpn_config "surfshark" "nl-ams.prod.surfshark.com_tcp.ovpn"
add_vpn_config "surfshark" "de-fra.prod.surfshark.com_tcp.ovpn"
add_vpn_config "surfshark" "be-bru.prod.surfshark.com_tcp.ovpn"
add_vpn_config "surfshark" "uk-lon.prod.surfshark.com_tcp.ovpn"
add_vpn_config "surfshark" "fr-par.prod.surfshark.com_tcp.ovpn"

# Add NordVPN configurations
add_vpn_config "nordvpn" "nl716.nordvpn.com.tcp.ovpn"
add_vpn_config "nordvpn" "nl717.nordvpn.com.tcp.ovpn"

# Add Namecheap configurations
add_vpn_config "namecheap" "NCVPN-NL-Amsterdam-TCP.ovpn"
add_vpn_config "namecheap" "NCVPN-DE-Frankfurt-TCP.ovpn"
add_vpn_config "namecheap" "NCVPN-UK-London-TCP.ovpn"

echo "ConfigMap generated at $OUTPUT_FILE"