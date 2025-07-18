#!/bin/bash
# RTPI-PEN Kasm Initialization Script
# Ensures proper setup before Kasm containers start

set -e

echo "🚀 Initializing Kasm Workspaces environment..."

# Define paths
KASM_ROOT="/opt/kasm/1.15.0"
KASM_CURRENT="/opt/kasm/current"

# Create directory structure with proper permissions
create_kasm_dirs() {
    local dirs=(
        "$KASM_ROOT/conf/app"
        "$KASM_ROOT/conf/database"
        "$KASM_ROOT/conf/nginx"
        "$KASM_ROOT/tmp/api"
        "$KASM_ROOT/tmp/guac"
        "$KASM_ROOT/tmp/guac/.npm"
        "$KASM_ROOT/log"
        "$KASM_ROOT/log/nginx"
        "$KASM_ROOT/log/postgres"
        "$KASM_ROOT/log/logrotate"
        "$KASM_ROOT/certs"
        "$KASM_ROOT/www"
        "$KASM_ROOT/share"
    )
    
    echo "Creating Kasm directory structure..."
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        chown -R 1000:1000 "$dir"
        chmod -R 755 "$dir"
        echo "✓ Created: $dir"
    done
    
    # Create symbolic link for current version
    if [ ! -L "$KASM_CURRENT" ]; then
        ln -sf "$KASM_ROOT" "$KASM_CURRENT"
        echo "✓ Created symbolic link: $KASM_CURRENT -> $KASM_ROOT"
    fi
}

# Generate SSL certificates
generate_ssl_certs() {
    echo "Generating SSL certificates..."
    
    local cert_dir="$KASM_ROOT/certs"
    
    # Generate self-signed certificates for Kasm
    if [ ! -f "$cert_dir/kasm_nginx.crt" ]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$cert_dir/kasm_nginx.key" \
            -out "$cert_dir/kasm_nginx.crt" \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
        
        chown 1000:1000 "$cert_dir/kasm_nginx.key" "$cert_dir/kasm_nginx.crt"
        chmod 600 "$cert_dir/kasm_nginx.key"
        chmod 644 "$cert_dir/kasm_nginx.crt"
        echo "✓ Generated Kasm nginx certificates"
    fi
    
    # Generate database certificates
    if [ ! -f "$cert_dir/db_server.crt" ]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$cert_dir/db_server.key" \
            -out "$cert_dir/db_server.crt" \
            -subj "/C=US/ST=State/L=City/O=Organization/CN=kasm_db"
        
        chown 1000:1000 "$cert_dir/db_server.key" "$cert_dir/db_server.crt"
        chmod 600 "$cert_dir/db_server.key"
        chmod 644 "$cert_dir/db_server.crt"
        echo "✓ Generated database certificates"
    fi
}

# Create API configuration
create_api_config() {
    local config_file="$KASM_ROOT/conf/app/api.app.config.yaml"
    
    if [ ! -f "$config_file" ]; then
        echo "Creating API configuration..."
        cat > "$config_file" << 'EOF'
api:
  server:
    hostname: 0.0.0.0
    port: 8080
    ssl: false
    ssl_port: 8443
  database:
    hostname: kasm_db
    port: 5432
    name: kasm
    user: kasmapp
    password: SjenXuTppFFSWIIKjaAJ
    ssl: false
  redis:
    hostname: kasm_redis
    port: 6379
    password: CwoZWGpBk5PZ3zD79fIK
  manager:
    hostname: kasm_manager
    port: 8181
    ssl: false
  agent:
    hostname: kasm_agent
    port: 443
    ssl: true
  guacamole:
    hostname: kasm_guac
    port: 3000
    ssl: false
  share:
    hostname: kasm_share
    port: 8182
    ssl: false
  session:
    timeout: 3600
    cleanup_interval: 300
  admin:
    default_username: admin@kasm.local
    default_password: password
  security:
    jwt_secret: "rtpi-pen-jwt-secret-key-2025"
    session_secret: "rtpi-pen-session-secret-2025"
    auth_token: "rtpi-pen-auth-token-2025-secure"
  auth_token: "rtpi-pen-auth-token-2025-secure"

api_server:
  hostname: 0.0.0.0
  port: 8080
  ssl: false
  ssl_port: 8443
  auth_token: "rtpi-pen-auth-token-2025-secure"

logging:
  level: INFO
  directory: /var/log/kasm
  file: api.log
  max_size: 10MB
  max_files: 3
EOF
        
        chown 1000:1000 "$config_file"
        chmod 644 "$config_file"
        echo "✓ Created API configuration"
    fi
}

# Create manager configuration
create_manager_config() {
    local config_file="$KASM_ROOT/conf/app/manager.app.config.yaml"
    
    if [ ! -f "$config_file" ]; then
        echo "Creating manager configuration..."
        cat > "$config_file" << 'EOF'
manager:
  server:
    hostname: 0.0.0.0
    port: 8181
    ssl: false
  database:
    hostname: kasm_db
    port: 5432
    name: kasm
    user: kasmapp
    password: SjenXuTppFFSWIIKjaAJ
    ssl: false
  redis:
    hostname: kasm_redis
    port: 6379
    password: CwoZWGpBk5PZ3zD79fIK
  api:
    hostname: kasm_api
    port: 8080
    ssl: false
    auth_token: "rtpi-pen-auth-token-2025-secure"
  agent:
    hostname: kasm_agent
    port: 443
    ssl: true
  session:
    timeout: 3600
    cleanup_interval: 300
  logging:
    level: INFO
    directory: /var/log/kasm
    file: manager.log
    max_size: 10MB
    max_files: 3
  workspaces:
    auto_scaling:
      enabled: false
      min_instances: 1
      max_instances: 10
    image_registry:
      enabled: false
      hostname: localhost
      port: 5000
  security:
    auth_token: "rtpi-pen-auth-token-2025-secure"
EOF
        
        chown 1000:1000 "$config_file"
        chmod 644 "$config_file"
        echo "✓ Created manager configuration"
    fi
}

# Create share configuration
create_share_config() {
    local config_file="$KASM_ROOT/conf/app/share.app.config.yaml"
    
    if [ ! -f "$config_file" ]; then
        echo "Creating share configuration..."
        cat > "$config_file" << 'EOF'
share:
  server:
    hostname: 0.0.0.0
    port: 8182
    ssl: false
  database:
    hostname: kasm_db
    port: 5432
    name: kasm
    user: kasmapp
    password: SjenXuTppFFSWIIKjaAJ
    ssl: false
  redis:
    hostname: kasm_redis
    port: 6379
    password: CwoZWGpBk5PZ3zD79fIK
  api:
    hostname: kasm_api
    port: 8080
    ssl: false
    auth_token: "rtpi-pen-auth-token-2025-secure"
  session:
    timeout: 3600
    cleanup_interval: 300
  logging:
    level: INFO
    directory: /var/log/kasm
    file: share.log
    max_size: 10MB
    max_files: 3
  sharing:
    enabled: true
    max_file_size: 100MB
    allowed_extensions: ["txt", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "zip", "tar", "gz"]
    storage_path: /var/lib/kasm/shares
  security:
    auth_token: "rtpi-pen-auth-token-2025-secure"
    encryption: true
EOF
        
        chown 1000:1000 "$config_file"
        chmod 644 "$config_file"
        echo "✓ Created share configuration"
    fi
}

# Create guacamole configuration
create_guacamole_config() {
    local config_file="$KASM_ROOT/conf/app/kasmguac.app.config.yaml"
    
    if [ ! -f "$config_file" ]; then
        echo "Creating guacamole configuration..."
        cat > "$config_file" << 'EOF'
guacamole:
  server:
    hostname: 0.0.0.0
    port: 3000
    ssl: false
  api:
    hostname: kasm_api
    port: 8080
    ssl: false
    username: admin@kasm.local
    password: password
    auth_token: "rtpi-pen-auth-token-2025-secure"
  database:
    hostname: kasm_db
    port: 5432
    name: kasm
    user: kasmapp
    password: SjenXuTppFFSWIIKjaAJ
    ssl: false
  redis:
    hostname: kasm_redis
    port: 6379
    password: CwoZWGpBk5PZ3zD79fIK
  logging:
    level: INFO
    directory: /var/log/kasm
    file: guacamole.log
    max_size: 10MB
    max_files: 3
  session:
    timeout: 3600
    cleanup_interval: 300
  vnc:
    enabled: true
    port_range: "5900-5999"
  rdp:
    enabled: true
    port_range: "3389-3489"
  ssh:
    enabled: true
    port_range: "22-122"
  recording:
    enabled: true
    path: /var/log/kasm/recordings
    max_size: 1GB
  connection:
    max_connections: 100
    idle_timeout: 1800
  security:
    encryption: true
    certificate_path: /opt/kasm/current/certs/kasm_nginx.crt
    key_path: /opt/kasm/current/certs/kasm_nginx.key
EOF
        
        chown 1000:1000 "$config_file"
        chmod 644 "$config_file"
        echo "✓ Created guacamole configuration"
    fi
}

# Create agent configuration
create_agent_config() {
    local config_file="$KASM_ROOT/conf/app/agent.app.config.yaml"
    
    if [ ! -f "$config_file" ]; then
        echo "Creating agent configuration..."
        cat > "$config_file" << 'EOF'
agent:
  public_hostname: localhost
  listen_port: 443
  api_hostname: kasm_api
  api_port: 8080
  api_ssl: false
  auto_scaling:
    enabled: false
  server_hostname: localhost
  server_port: 8443
  server_ssl: true
  api_server_ssl: false
  redis_hostname: kasm_redis
  redis_port: 6379
  redis_password: "CwoZWGpBk5PZ3zD79fIK"
  provider: docker
  docker_network: kasm_default_network
  docker_volume_driver: local
  docker_registry: null
  docker_private_registry: null
  docker_auth_config: null
  compute_resources:
    cpu_shares: 1024
    memory: 2048
    cpus: 1
    memory_reservation: 512
    pids_limit: 1000
  docker_log_driver: json-file
  docker_log_opts:
    max-size: "10m"
    max-file: "3"
  security:
    auth_token: "rtpi-pen-auth-token-2025-secure"
  logging:
    level: INFO
    directory: /var/log/kasm
    file: agent.log
    max_size: 10MB
    max_files: 3
EOF
        
        chown 1000:1000 "$config_file"
        chmod 644 "$config_file"
        echo "✓ Created agent configuration"
    fi
}

# Create database configuration
create_database_config() {
    local config_dir="$KASM_ROOT/conf/database"
    
    # PostgreSQL configuration
    cat > "$config_dir/postgresql.conf" << 'EOF'
# PostgreSQL Configuration for Kasm
# Generated by RTPI-PEN Self-Healing Service

# Connection settings
listen_addresses = '*'
port = 5432
max_connections = 100

# Memory settings
shared_buffers = 128MB
effective_cache_size = 512MB
work_mem = 4MB
maintenance_work_mem = 64MB

# WAL settings
wal_level = minimal
checkpoint_completion_target = 0.9

# Logging
log_destination = 'stderr'
logging_collector = on
log_directory = '/var/log/postgres'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_line_prefix = '%t [%p-%l] %q%u@%d '

# Authentication
password_encryption = md5
EOF
    
    # Host-based authentication
    cat > "$config_dir/pg_hba.conf" << 'EOF'
# PostgreSQL Client Authentication Configuration File
# For Kasm Workspaces

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     peer

# IPv4 local connections:
host    all             all             127.0.0.1/32            md5
host    all             all             0.0.0.0/0               md5

# IPv6 local connections:
host    all             all             ::1/128                 md5

# Allow replication connections from localhost, by a user with the
# replication privilege.
local   replication     all                                     peer
host    replication     all             127.0.0.1/32            md5
host    replication     all             ::1/128                 md5

# Kasm specific connections
host    kasm            kasmapp         172.0.0.0/8             md5
host    kasm            kasmapp         10.0.0.0/8              md5
host    kasm            kasmapp         192.168.0.0/16          md5
EOF
    
    # Database initialization script
    cat > "$config_dir/data.sql" << 'EOF'
-- Kasm Database Initialization Script
-- Generated by RTPI-PEN Self-Healing Service

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create the main kasm user if it doesn't exist
DO
$$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'kasmapp') THEN
        CREATE USER kasmapp WITH PASSWORD 'SjenXuTppFFSWIIKjaAJ';
    END IF;
END
$$;

-- Create the database
CREATE DATABASE kasm OWNER kasmapp;

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE kasm TO kasmapp;

-- Connect to the kasm database
\c kasm;

-- Create basic tables structure
CREATE TABLE IF NOT EXISTS users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sessions (
    session_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    session_token VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    active BOOLEAN DEFAULT TRUE
);

-- Insert default admin user if it doesn't exist
INSERT INTO users (username, password_hash, email) 
VALUES ('admin', '$2b$12$8x1ZUJZGTUEYFOZPJJQ.ZuRNmZhTDHwvgOjh9hPJGNXtFXCwvr6y6', 'admin@kasm.local')
ON CONFLICT (username) DO NOTHING;

-- Grant all privileges to kasmapp user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO kasmapp;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO kasmapp;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO kasmapp;
EOF
    
    # Set permissions
    chown -R 1000:1000 "$config_dir"
    chmod 644 "$config_dir"/*.conf "$config_dir"/*.sql
    echo "✓ Created database configuration"
}

# Create nginx configuration
create_nginx_config() {
    local config_dir="$KASM_ROOT/conf/nginx"
    
    cat > "$config_dir/default.conf" << 'EOF'
# Kasm Nginx Configuration
# Generated by RTPI-PEN Self-Healing Service

upstream kasm_api {
    server kasm_api:8080;
}

upstream kasm_manager {
    server kasm_manager:8181;
}

upstream kasm_share {
    server kasm_share:8182;
}

upstream kasm_guac {
    server kasm_guac:3000;
}

server {
    listen 443 ssl;
    server_name _;

    ssl_certificate /etc/ssl/certs/kasm_nginx.crt;
    ssl_certificate_key /etc/ssl/private/kasm_nginx.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
    ssl_prefer_server_ciphers on;

    client_max_body_size 1G;

    location / {
        proxy_pass http://kasm_api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    location /api/ {
        proxy_pass http://kasm_api;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /manager/ {
        proxy_pass http://kasm_manager;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /share/ {
        proxy_pass http://kasm_share;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /guac/ {
        proxy_pass http://kasm_guac;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
    
    chown -R 1000:1000 "$config_dir"
    chmod 644 "$config_dir/default.conf"
    echo "✓ Created nginx configuration"
}

# Create default web content
create_web_content() {
    local web_dir="$KASM_ROOT/www"
    
    cat > "$web_dir/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Kasm Workspaces</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            text-align: center;
        }
        p {
            color: #666;
            line-height: 1.6;
        }
        .status {
            background-color: #e8f5e8;
            border: 1px solid #4CAF50;
            padding: 10px;
            border-radius: 4px;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Kasm Workspaces</h1>
        <div class="status">
            <strong>Status:</strong> System initialized and ready
        </div>
        <p>Welcome to Kasm Workspaces - Your containerized workspace platform.</p>
        <p>This system has been automatically configured by the RTPI-PEN Self-Healing Service.</p>
    </div>
</body>
</html>
EOF
    
    chown -R 1000:1000 "$web_dir"
    chmod 644 "$web_dir/index.html"
    echo "✓ Created web content"
}

# Main initialization
main() {
    echo "Starting Kasm initialization..."
    
    # Check if we're running as root
    if [ "$EUID" -ne 0 ]; then
        echo "❌ This script must be run as root"
        exit 1
    fi
    
    # Create directory structure
    create_kasm_dirs
    
    # Generate SSL certificates
    generate_ssl_certs
    
    # Create configurations
    create_api_config
    create_manager_config
    create_share_config
    create_guacamole_config
    create_agent_config
    create_database_config
    create_nginx_config
    create_web_content
    
    # Final permission check
    chown -R 1000:1000 "$KASM_ROOT"
    
    echo "✅ Kasm initialization completed successfully!"
    echo "📁 Kasm root directory: $KASM_ROOT"
    echo "🔗 Symbolic link: $KASM_CURRENT"
    echo "🔧 Configuration files created and permissions set"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
