# RTPI-PEN Orchestrator Service (Portainer + Orchestration)
FROM alpine:latest

# Install required packages
RUN apk add --no-cache \
    curl \
    wget \
    bash \
    docker-cli \
    ca-certificates

# Set Portainer version
ENV PORTAINER_VERSION=2.21.0

# Create directories
RUN mkdir -p /opt/portainer /var/log/rtpi

# Download and install Portainer
RUN wget -q "https://github.com/portainer/portainer/releases/download/${PORTAINER_VERSION}/portainer-${PORTAINER_VERSION}-linux-amd64.tar.gz" \
    -O /tmp/portainer.tar.gz && \
    tar -xzf /tmp/portainer.tar.gz -C /opt/portainer --strip-components=1 && \
    rm /tmp/portainer.tar.gz

# Copy orchestrator scripts
COPY scripts/ /opt/rtpi-orchestrator/scripts/

# Create entrypoint script
RUN cat > /usr/local/bin/orchestrator-entrypoint.sh << 'EOF'
#!/bin/bash
set -e

echo "🐳 Starting RTPI-PEN Orchestrator Service"

# Ensure data directory exists
mkdir -p /data

# Wait for Docker socket to be available
echo "Waiting for Docker socket..."
while [ ! -S /var/run/docker.sock ]; do
    echo "Docker socket not available, waiting..."
    sleep 2
done

echo "Docker socket detected, checking connectivity..."
if docker info >/dev/null 2>&1; then
    echo "✅ Docker connectivity confirmed"
else
    echo "⚠️ Docker not accessible, continuing anyway..."
fi

# Start Portainer
echo "🚀 Starting Portainer..."
exec /opt/portainer/portainer \
    --data /data \
    --bind :9000 \
    --admin-password='$2a$10$N8XymdoNDQjHlraNJWM6JOhT8vjjyZO6zGQGFCEzLCYIyIkGxP6oa'
EOF

RUN chmod +x /usr/local/bin/orchestrator-entrypoint.sh

# Create non-root user
RUN addgroup -g 1000 portainer && \
    adduser -u 1000 -G portainer -s /bin/sh -D portainer

# Set proper permissions
RUN chown -R portainer:portainer /opt/portainer /var/log/rtpi

# Switch to non-root user
USER portainer

# Expose Portainer port
EXPOSE 9000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:9000/ || exit 1

ENTRYPOINT ["/usr/local/bin/orchestrator-entrypoint.sh"]
