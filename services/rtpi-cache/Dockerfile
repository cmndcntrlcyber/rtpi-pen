# RTPI-PEN Redis Cache Service
FROM redis:7.2-alpine

# Install additional tools
RUN apk add --no-cache bash curl

# Copy Redis configurations
COPY redis-configs/ /etc/redis/

# Create directories for Redis data and logs
RUN mkdir -p /var/lib/redis /var/log/redis && \
    chown redis:redis /var/lib/redis /var/log/redis

# Expose Redis ports (main, kasm, sysreptor)
EXPOSE 6379 6380 6381

# Create startup script for multiple Redis instances
RUN cat > /usr/local/bin/redis-startup.sh << 'EOF'
#!/bin/bash
set -e

echo "Starting Redis instances..."

# Create data directories
mkdir -p /var/lib/redis/{main,kasm,sysreptor}
chown -R redis:redis /var/lib/redis

# Start main Redis instance
redis-server /etc/redis/redis-main.conf --daemonize yes

# Start Kasm Redis instance  
redis-server /etc/redis/redis-kasm.conf --daemonize yes

# Start SysReptor Redis instance
redis-server /etc/redis/redis-sysreptor.conf --daemonize yes

echo "All Redis instances started"

# Keep container running by tailing logs
tail -f /var/log/redis/*.log
EOF

RUN chmod +x /usr/local/bin/redis-startup.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD redis-cli -p 6379 ping && redis-cli -p 6380 ping && redis-cli -p 6381 ping

# Start with our custom script
CMD ["/usr/local/bin/redis-startup.sh"]
