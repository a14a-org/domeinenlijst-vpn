FROM alpine:3.18

# Install required packages
RUN apk add --no-cache \
    openvpn \
    dante-server \
    supervisor \
    curl \
    bash \
    iptables \
    jq \
    net-tools

# Create directories
RUN mkdir -p /etc/openvpn /var/log/supervisor /app

# Copy configurations
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY dante.conf /etc/dante.conf
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/healthcheck.sh /healthcheck.sh
COPY scripts/check_vpn_then_start_dante.sh /check_vpn_then_start_dante.sh

# Make scripts executable
RUN chmod +x /entrypoint.sh /healthcheck.sh /check_vpn_then_start_dante.sh

# Expose SOCKS5 port
EXPOSE 1080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD /healthcheck.sh || exit 1

ENTRYPOINT ["/entrypoint.sh"]