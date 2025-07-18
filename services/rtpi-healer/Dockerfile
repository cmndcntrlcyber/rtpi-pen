# RTPI-PEN Self-Healing Service
# Monitors and auto-repairs container issues
FROM alpine:latest

# Install required packages including build dependencies
RUN apk add --no-cache \
    curl \
    wget \
    bash \
    docker-cli \
    ca-certificates \
    jq \
    python3 \
    py3-pip \
    postgresql-client \
    redis \
    coreutils \
    findutils \
    procps \
    net-tools \
    gcc \
    python3-dev \
    musl-dev \
    linux-headers

# Create virtual environment and install Python dependencies
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir \
    docker \
    requests \
    psutil \
    redis \
    psycopg2-binary \
    pyyaml \
    schedule

# Create directories
RUN mkdir -p \
    /opt/rtpi-healer \
    /var/log/rtpi-healer \
    /data/rtpi-healer \
    /data/backups \
    /data/configs

# Create healer user
RUN addgroup -g 1000 healer && \
    adduser -u 1000 -G healer -s /bin/sh -D healer

# Copy scripts and configurations
COPY scripts/ /opt/rtpi-healer/scripts/
COPY configs/ /opt/rtpi-healer/configs/
COPY templates/ /opt/rtpi-healer/templates/

# Set permissions
RUN chown -R healer:healer /opt/rtpi-healer /var/log/rtpi-healer /data && \
    chmod +x /opt/rtpi-healer/scripts/*.sh

# Create main entrypoint
RUN cat > /usr/local/bin/healer-entrypoint.sh << 'EOF'
#!/bin/bash
set -e

echo "🏥 Starting RTPI-PEN Self-Healing Service"

# Ensure directories exist
mkdir -p /var/log/rtpi-healer /data/rtpi-healer /data/backups /data/configs

# Wait for Docker socket
echo "Waiting for Docker socket..."
while [ ! -S /var/run/docker.sock ]; do
    echo "Docker socket not available, waiting..."
    sleep 2
done

echo "Docker socket detected, checking connectivity..."
# Try to fix Docker socket permissions if needed
chmod 666 /var/run/docker.sock 2>/dev/null || true

# Test Docker connectivity with retry
for i in {1..10}; do
    if docker info >/dev/null 2>&1; then
        echo "✅ Docker connectivity confirmed"
        break
    elif [ $i -eq 10 ]; then
        echo "⚠️ Docker not accessible after 10 attempts, continuing anyway..."
        break
    else
        echo "Docker connectivity attempt $i/10 failed, retrying..."
        sleep 2
    fi
done

# Start the healer service
echo "🚀 Starting Self-Healing Monitor..."
exec python3 /opt/rtpi-healer/scripts/healer.py
EOF

RUN chmod +x /usr/local/bin/healer-entrypoint.sh

# Keep as root for Docker socket access
# USER healer

# Expose monitoring port
EXPOSE 8888

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:8888/health || exit 1

ENTRYPOINT ["/usr/local/bin/healer-entrypoint.sh"]
