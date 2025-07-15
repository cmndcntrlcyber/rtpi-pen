# RTPI-PEN Proxy Service (Nginx + Dashboard)
FROM nginx:alpine

# Install additional tools
RUN apk add --no-cache curl openssl

# Copy nginx configuration
COPY nginx/ /etc/nginx/

# Copy web dashboard
COPY www/ /usr/share/nginx/html/

# Create directories for SSL certificates
RUN mkdir -p /etc/nginx/ssl

# Generate self-signed certificates
RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/rtpi.key \
    -out /etc/nginx/ssl/rtpi.crt \
    -subj "/C=US/ST=State/L=City/O=RTPI-PEN/CN=rtpi-pen"

# Create nginx entrypoint script
RUN cat > /usr/local/bin/nginx-entrypoint.sh << 'EOF'
#!/bin/sh
set -e

echo "🌐 Starting RTPI-PEN Proxy Service"

# Ensure SSL certificates exist
if [ ! -f /etc/nginx/ssl/rtpi.crt ] || [ ! -f /etc/nginx/ssl/rtpi.key ]; then
    echo "Generating SSL certificates..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/rtpi.key \
        -out /etc/nginx/ssl/rtpi.crt \
        -subj "/C=US/ST=State/L=City/O=RTPI-PEN/CN=rtpi-pen"
fi

# Test nginx configuration
nginx -t

# Start nginx
echo "✅ Proxy service ready"
exec nginx -g 'daemon off;'
EOF

RUN chmod +x /usr/local/bin/nginx-entrypoint.sh

# Expose HTTP and HTTPS ports
EXPOSE 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

ENTRYPOINT ["/usr/local/bin/nginx-entrypoint.sh"]
