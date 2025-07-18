#!/bin/bash
# RTPI-PEN Manual Initialization Script
# Manually initializes all configurations and dependencies

set -e

echo "🔧 Starting Manual Initialization for RTPI-PEN..."

# Function to create directory structure
create_directory_structure() {
    echo "📁 Creating directory structure..."
    
    local dirs=(
        # Kasm directories
        "/opt/kasm/1.15.0/conf/app"
        "/opt/kasm/1.15.0/conf/database"
        "/opt/kasm/1.15.0/conf/nginx"
        "/opt/kasm/1.15.0/tmp/api"
        "/opt/kasm/1.15.0/tmp/guac"
        "/opt/kasm/1.15.0/tmp/guac/.npm"
        "/opt/kasm/1.15.0/log"
        "/opt/kasm/1.15.0/log/nginx"
        "/opt/kasm/1.15.0/log/postgres"
        "/opt/kasm/1.15.0/log/logrotate"
        "/opt/kasm/1.15.0/certs"
        "/opt/kasm/1.15.0/www"
        "/opt/kasm/1.15.0/share"
        # Empire directories
        "/opt/empire/data"
        "/opt/empire/data/logs"
        # Orchestrator directories
        "/opt/rtpi-orchestrator/data"
        "/opt/rtpi-orchestrator/data/certs"
        "/opt/rtpi-orchestrator/data/portainer"
        # Healer directories
        "/var/log/rtpi-healer"
        "/data/rtpi-healer"
        "/data/backups"
        "/data/configs"
        # Application data directories
        "/var/lib/kasm"
        "/var/lib/kasm/shares"
        "/var/log/kasm"
        "/var/log/kasm/recordings"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            echo "Creating directory: $dir"
            sudo mkdir -p "$dir"
            sudo chown -R 1000:1000 "$dir"
            sudo chmod -R 755 "$dir"
        fi
    done
    
    # Create symbolic link for current version
    if [ ! -L "/opt/kasm/current" ]; then
        sudo ln -sf "/opt/kasm/1.15.0" "/opt/kasm/current"
        echo "✅ Created symbolic link: /opt/kasm/current"
    fi
    
    echo "✅ Directory structure created"
}

# Function to generate SSL certificates
generate_ssl_certificates() {
    echo "🔐 Generating SSL certificates..."
    
    local cert_dir="/opt/kasm/1.15.0/certs"
    
    # Generate Kasm nginx certificates
    if [ ! -f "$cert_dir/kasm_nginx.crt" ]; then
        echo "Generating Kasm nginx certificates..."
        sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$cert_dir/kasm_nginx.key" \
            -out "$cert_dir/kasm_nginx.crt" \
            -subj "/C=US/ST=State/L=City/O=RTPI-PEN/CN=localhost"
        
        sudo chown 1000:1000 "$cert_dir/kasm_nginx.key" "$cert_dir/kasm_nginx.crt"
        sudo chmod 600 "$cert_dir/kasm_nginx.key"
        sudo chmod 644 "$cert_dir/kasm_nginx.crt"
        echo "✅ Kasm nginx certificates generated"
    fi
    
    # Generate database certificates
    if [ ! -f "$cert_dir/db_server.crt" ]; then
        echo "Generating database certificates..."
        sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$cert_dir/db_server.key" \
            -out "$cert_dir/db_server.crt" \
            -subj "/C=US/ST=State/L=City/O=RTPI-PEN/CN=kasm_db"
        
        sudo chown 1000:1000 "$cert_dir/db_server.key" "$cert_dir/db_server.crt"
        sudo chmod 600 "$cert_dir/db_server.key"
        sudo chmod 644 "$cert_dir/db_server.crt"
        echo "✅ Database certificates generated"
    fi
    
    echo "✅ SSL certificates generated"
}

# Function to create Kasm configurations
create_kasm_configurations() {
    echo "📝 Creating Kasm configurations..."
    
    local config_dir="/opt/kasm/1.15.0/conf/app"
    
    # API configuration
    sudo tee "$config_dir/api.app.config.yaml" > /dev/null << 'EOF'
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
  auth_token: "rtpi-pen-auth-token-2025-secure"
  logging:
    level: INFO
    directory: /var/log/kasm
    file: api.log
    max_size: 10MB
    max_files: 3
EOF
    
    # Agent configuration
    sudo tee "$config_dir/agent.app.config.yaml" > /dev/null << 'EOF'
agent:
  public_hostname: localhost
  listen_port: 443
  api_hostname: kasm_api
  api_port: 8080
  api_ssl: false
  auto_scaling:
    enabled: false
  security:
    auth_token: "rtpi-pen-auth-token-2025-secure"
  logging:
    level: INFO
    directory: /var/log/kasm
    file: agent.log
    max_size: 10MB
    max_files: 3
EOF
    
    # Manager configuration
    sudo tee "$config_dir/manager.app.config.yaml" > /dev/null << 'EOF'
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
  logging:
    level: INFO
    directory: /var/log/kasm
    file: manager.log
    max_size: 10MB
    max_files: 3
EOF
    
    # Share configuration
    sudo tee "$config_dir/share.app.config.yaml" > /dev/null << 'EOF'
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
  logging:
    level: INFO
    directory: /var/log/kasm
    file: share.log
    max_size: 10MB
    max_files: 3
EOF
    
    # Guacamole configuration
    sudo tee "$config_dir/kasmguac.app.config.yaml" > /dev/null << 'EOF'
guacamole:
  server:
    hostname: 0.0.0.0
    port: 3000
    ssl: false
  api:
    hostname: kasm_api
    port: 8080
    ssl: false
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
EOF
    
    # Set permissions
    sudo chown -R 1000:1000 "$config_dir"
    sudo chmod -R 644 "$config_dir"/*.yaml
    
    echo "✅ Kasm configurations created"
}

# Function to create database configurations
create_database_configurations() {
    echo "🗄️ Creating database configurations..."
    
    local db_config_dir="/opt/kasm/1.15.0/conf/database"
    
    # PostgreSQL configuration
    sudo tee "$db_config_dir/postgresql.conf" > /dev/null << 'EOF'
# PostgreSQL Configuration for Kasm
listen_addresses = '*'
port = 5432
max_connections = 100
shared_buffers = 128MB
effective_cache_size = 512MB
work_mem = 4MB
maintenance_work_mem = 64MB
wal_level = minimal
checkpoint_completion_target = 0.9
log_destination = 'stderr'
logging_collector = on
log_directory = '/var/log/postgres'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_line_prefix = '%t [%p-%l] %q%u@%d '
password_encryption = md5
EOF
    
    # Host-based authentication
    sudo tee "$db_config_dir/pg_hba.conf" > /dev/null << 'EOF'
# PostgreSQL Client Authentication Configuration File
local   all             all                                     peer
host    all             all             127.0.0.1/32            md5
host    all             all             0.0.0.0/0               md5
host    all             all             ::1/128                 md5
local   replication     all                                     peer
host    replication     all             127.0.0.1/32            md5
host    replication     all             ::1/128                 md5
host    kasm            kasmapp         172.0.0.0/8             md5
host    kasm            kasmapp         10.0.0.0/8              md5
host    kasm            kasmapp         192.168.0.0/16          md5
EOF
    
    # Database initialization script
    sudo tee "$db_config_dir/data.sql" > /dev/null << 'EOF'
-- Kasm Database Initialization Script
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

DO
$$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'kasmapp') THEN
        CREATE USER kasmapp WITH PASSWORD 'SjenXuTppFFSWIIKjaAJ';
    END IF;
END
$$;

CREATE DATABASE kasm OWNER kasmapp;
GRANT ALL PRIVILEGES ON DATABASE kasm TO kasmapp;

\c kasm;

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

INSERT INTO users (username, password_hash, email) 
VALUES ('admin', '$2b$12$8x1ZUJZGTUEYFOZPJJQ.ZuRNmZhTDHwvgOjh9hPJGNXtFXCwvr6y6', 'admin@kasm.local')
ON CONFLICT (username) DO NOTHING;

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO kasmapp;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO kasmapp;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO kasmapp;
EOF
    
    # Set permissions
    sudo chown -R 1000:1000 "$db_config_dir"
    sudo chmod 644 "$db_config_dir"/*.conf "$db_config_dir"/*.sql
    
    echo "✅ Database configurations created"
}

# Function to create nginx configurations
create_nginx_configurations() {
    echo "🌐 Creating nginx configurations..."
    
    local nginx_config_dir="/opt/kasm/1.15.0/conf/nginx"
    
    sudo tee "$nginx_config_dir/default.conf" > /dev/null << 'EOF'
# Kasm Nginx Configuration
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
    
    # Set permissions
    sudo chown -R 1000:1000 "$nginx_config_dir"
    sudo chmod 644 "$nginx_config_dir/default.conf"
    
    echo "✅ Nginx configurations created"
}

# Function to create Empire configurations
create_empire_configurations() {
    echo "👑 Creating Empire configurations..."
    
    local empire_dir="/opt/empire/data"
    
    sudo tee "$empire_dir/empire.yaml" > /dev/null << 'EOF'
# Empire Configuration
api:
  port: 1337
  host: 0.0.0.0
  cert_path: ""
  key_path: ""

database:
  location: "data/empire.db"
  
plugins:
  directories:
    - "plugins/"

logging:
  level: "INFO"
  directory: "logs/"

stagers:
  generate_stagers: true
  
listeners:
  default_port: 80
  default_cert_path: ""
  default_key_path: ""

reporting:
  enabled: false
EOF
    
    # Set permissions
    sudo chown -R 1000:1000 "$empire_dir"
    sudo chmod 644 "$empire_dir/empire.yaml"
    
    echo "✅ Empire configurations created"
}

# Function to create web content
create_web_content() {
    echo "🌐 Creating web content..."
    
    local web_dir="/opt/kasm/1.15.0/www"
    
    sudo tee "$web_dir/index.html" > /dev/null << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Kasm Workspaces - RTPI-PEN</title>
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
        .status {
            background-color: #e8f5e8;
            border: 1px solid #4CAF50;
            padding: 10px;
            border-radius: 4px;
            margin: 20px 0;
        }
        .info {
            color: #666;
            line-height: 1.6;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🏥 Kasm Workspaces - RTPI-PEN</h1>
        <div class="status">
            <strong>Status:</strong> System initialized and ready
        </div>
        <div class="info">
            <p>Welcome to Kasm Workspaces in the RTPI-PEN environment.</p>
            <p>This system has been automatically configured by the Self-Healing Service.</p>
            <p><strong>Initialization completed at:</strong> <script>document.write(new Date().toLocaleString())</script></p>
        </div>
    </div>
</body>
</html>
EOF
    
    # Set permissions
    sudo chown -R 1000:1000 "$web_dir"
    sudo chmod 644 "$web_dir/index.html"
    
    echo "✅ Web content created"
}

# Function to fix all permissions
fix_permissions() {
    echo "🔒 Fixing permissions..."
    
    # Fix main directories
    sudo chown -R 1000:1000 /opt/kasm/1.15.0
    sudo chown -R 1000:1000 /opt/empire
    sudo chown -R 1000:1000 /opt/rtpi-orchestrator
    sudo chown -R 1000:1000 /var/log/rtpi-healer
    sudo chown -R 1000:1000 /data
    
    # Fix specific permission requirements
    sudo chmod 755 /opt/kasm/1.15.0/tmp/api
    sudo chmod 755 /opt/kasm/1.15.0/tmp/guac
    sudo chmod 755 /opt/kasm/1.15.0/tmp/guac/.npm
    sudo chmod 755 /var/log/rtpi-healer
    sudo chmod 755 /data/rtpi-healer
    
    # Fix certificate permissions
    sudo chmod 600 /opt/kasm/1.15.0/certs/*.key
    sudo chmod 644 /opt/kasm/1.15.0/certs/*.crt
    
    echo "✅ Permissions fixed"
}

# Function to validate configurations
validate_configurations() {
    echo "✅ Validating configurations..."
    
    local errors=0
    
    # Check required files exist
    local required_files=(
        "/opt/kasm/1.15.0/conf/app/api.app.config.yaml"
        "/opt/kasm/1.15.0/conf/app/agent.app.config.yaml"
        "/opt/kasm/1.15.0/conf/app/manager.app.config.yaml"
        "/opt/kasm/1.15.0/conf/app/share.app.config.yaml"
        "/opt/kasm/1.15.0/conf/app/kasmguac.app.config.yaml"
        "/opt/kasm/1.15.0/conf/database/postgresql.conf"
        "/opt/kasm/1.15.0/conf/database/pg_hba.conf"
        "/opt/kasm/1.15.0/conf/database/data.sql"
        "/opt/kasm/1.15.0/conf/nginx/default.conf"
        "/opt/kasm/1.15.0/certs/kasm_nginx.crt"
        "/opt/kasm/1.15.0/certs/kasm_nginx.key"
        "/opt/empire/data/empire.yaml"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            echo "❌ Missing file: $file"
            ((errors++))
        fi
    done
    
    # Check required directories exist
    local required_dirs=(
        "/opt/kasm/1.15.0/tmp/api"
        "/opt/kasm/1.15.0/tmp/guac"
        "/opt/kasm/1.15.0/log"
        "/var/log/rtpi-healer"
        "/data/rtpi-healer"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            echo "❌ Missing directory: $dir"
            ((errors++))
        fi
    done
    
    if [ $errors -eq 0 ]; then
        echo "✅ All configurations validated successfully"
        return 0
    else
        echo "❌ Configuration validation failed with $errors errors"
        return 1
    fi
}

# Main execution
main() {
    echo "Starting manual initialization at $(date)"
    
    # Check if running as root or with sudo access
    if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
        echo "❌ This script requires sudo privileges"
        exit 1
    fi
    
    # Check if OpenSSL is installed
    if ! command -v openssl &> /dev/null; then
        echo "❌ OpenSSL is required but not installed"
        exit 1
    fi
    
    # Create directory structure
    create_directory_structure
    
    # Generate SSL certificates
    generate_ssl_certificates
    
    # Create configurations
    create_kasm_configurations
    create_database_configurations
    create_nginx_configurations
    create_empire_configurations
    create_web_content
    
    # Fix permissions
    fix_permissions
    
    # Validate configurations
    if validate_configurations; then
        echo "✅ Manual initialization completed successfully!"
        echo "📝 Next step: Run sequential-startup.sh to start services"
        echo "🔍 Logs available at: /var/log/rtpi-pen-repair/"
    else
        echo "❌ Manual initialization completed with errors"
        echo "🔍 Check the validation errors above and fix them before proceeding"
        exit 1
    fi
}

# Execute main function
main "$@"
