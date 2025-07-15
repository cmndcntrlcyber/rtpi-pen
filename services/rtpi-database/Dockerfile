# RTPI-PEN Database Service
FROM postgres:14

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install additional tools for database management
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy initialization scripts
COPY init-scripts/ /docker-entrypoint-initdb.d/

# Create additional directories for logs
RUN mkdir -p /var/log/postgresql

# Expose PostgreSQL port
EXPOSE 5432

# Set default environment variables
ENV POSTGRES_DB=rtpi_main
ENV POSTGRES_USER=rtpi
ENV POSTGRES_PASSWORD=rtpi_secure_password

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD pg_isready -U $POSTGRES_USER -d $POSTGRES_DB
