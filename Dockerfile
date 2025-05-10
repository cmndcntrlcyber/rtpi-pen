FROM alpine:3.19

# Environment variables
ENV KASM_UID=1000
ENV KASM_GID=1000
ENV PORTAINER_VERSION=2.19.1

# Install required packages
RUN apk add --no-cache wget curl ca-certificates bash

# Install Portainer
RUN mkdir -p /opt/portainer && \
    wget -q "https://github.com/portainer/portainer/releases/download/${PORTAINER_VERSION}/portainer-${PORTAINER_VERSION}-linux-amd64.tar.gz" -O portainer.tar.gz && \
    tar -xzf portainer.tar.gz -C /opt/portainer --strip-components=1 && \
    rm portainer.tar.gz

# Copy configuration files
COPY configs/ /opt/rtpi-pen/configs/
COPY setup/ /opt/rtpi-pen/setup/

# Set up directory structure
RUN mkdir -p /opt/rtpi-pen/data \
    && mkdir -p /opt/kasm/1.15.0/conf/nginx \
    && mkdir -p /opt/kasm/1.15.0/certs \
    && mkdir -p /opt/kasm/1.15.0/www \
    && mkdir -p /opt/kasm/1.15.0/log/nginx \
    && mkdir -p /opt/kasm/1.15.0/log/logrotate \
    && mkdir -p /opt/kasm/1.15.0/log/postgres \
    && mkdir -p /opt/kasm/1.15.0/conf/database \
    && mkdir -p /opt/kasm/1.15.0/tmp/api \
    && mkdir -p /opt/kasm/1.15.0/tmp/guac \
    && mkdir -p /opt/sysreptor/deploy/caddy

# Make scripts executable
RUN chmod +x /opt/rtpi-pen/setup/*.sh \
    && chmod +x /opt/rtpi-pen/configs/*/*.sh || true

# Create an entrypoint script
RUN echo '#!/bin/sh' > /entrypoint.sh \
    && echo 'if [ "$1" = "setup" ]; then' >> /entrypoint.sh \
    && echo '  /opt/rtpi-pen/setup/fresh-rtpi.sh' >> /entrypoint.sh \
    && echo 'elif [ "$1" = "portainer" ]; then' >> /entrypoint.sh \
    && echo '  /opt/portainer/portainer' >> /entrypoint.sh \
    && echo 'else' >> /entrypoint.sh \
    && echo '  exec "$@"' >> /entrypoint.sh \
    && echo 'fi' >> /entrypoint.sh \
    && chmod +x /entrypoint.sh

VOLUME /data
VOLUME /var/run/docker.sock

EXPOSE 9000 9443

ENTRYPOINT ["/entrypoint.sh"]
CMD ["portainer"]
