#!/bin/bash

# Script to select VPN config based on pod ordinal

set -e

# Extract pod ordinal from pod name (e.g., vpn-proxy-surfshark-0 -> 0)
POD_ORDINAL=$(echo $POD_NAME | rev | cut -d'-' -f1 | rev)

case "$VPN_PROVIDER" in
    "surfshark")
        # Surfshark config mapping
        case "$POD_ORDINAL" in
            "0") export VPN_CONFIG="nl-ams.prod.surfshark.com_tcp.ovpn" ;;
            "1") export VPN_CONFIG="nl-ams.prod.surfshark.com_tcp.ovpn" ;;  # Can use same
            "2") export VPN_CONFIG="nl-ams.prod.surfshark.com_tcp.ovpn" ;;  # Can use same
            "3") export VPN_CONFIG="de-fra.prod.surfshark.com_tcp.ovpn" ;;
            "4") export VPN_CONFIG="be-bru.prod.surfshark.com_tcp.ovpn" ;;
            "5") export VPN_CONFIG="uk-lon.prod.surfshark.com_tcp.ovpn" ;;
            "6") export VPN_CONFIG="fr-par.prod.surfshark.com_tcp.ovpn" ;;
            *) export VPN_CONFIG="nl-ams.prod.surfshark.com_tcp.ovpn" ;;
        esac
        ;;
    "nordvpn")
        # NordVPN config mapping
        case "$POD_ORDINAL" in
            "0") export VPN_CONFIG="nl716.nordvpn.com.tcp.ovpn" ;;
            "1") export VPN_CONFIG="nl717.nordvpn.com.tcp.ovpn" ;;
            *) export VPN_CONFIG="nl716.nordvpn.com.tcp.ovpn" ;;
        esac
        ;;
    "namecheap")
        # Namecheap config mapping
        case "$POD_ORDINAL" in
            "0") export VPN_CONFIG="NCVPN-NL-Amsterdam-TCP.ovpn" ;;
            "1") export VPN_CONFIG="NCVPN-DE-Frankfurt-TCP.ovpn" ;;
            "2") export VPN_CONFIG="NCVPN-UK-London-TCP.ovpn" ;;
            *) export VPN_CONFIG="NCVPN-NL-Amsterdam-TCP.ovpn" ;;
        esac
        ;;
esac

echo "Pod $POD_NAME will use VPN config: $VPN_CONFIG"

# Write the selected config to a file for the main container
echo "$VPN_CONFIG" > /tmp/selected-vpn-config