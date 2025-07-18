#!/bin/bash

# RTPI-PEN Certificate Manager
# Let's Encrypt SSL certificate automation with DNS-01 challenge
# Version: 1.0.0

set -e

# Configuration
DOMAIN="attck-node.net"
EMAIL="attck.community@gmail.com"
CERT_DIR="/etc/letsencrypt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DNS_MANAGER="$SCRIPT_DIR/cloudflare_dns_manager_working.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] CERT: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] CERT WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] CERT ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] CERT INFO: $1${NC}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root"
        exit 1
    fi
}

# Install dependencies
install_dependencies() {
    log "Installing certificate management dependencies..."
    
    # Update package list
    apt-get update -qq
    
    # Install required packages
    apt-get install -y \
        certbot \
        python3-certbot-dns-cloudflare \
        jq \
        curl \
        dnsutils \
        openssl
    
    log "Dependencies installed successfully"
}

# Create DNS hook scripts for certbot
create_dns_hooks() {
    local hook_dir="$CERT_DIR/renewal-hooks"
    
    # Create hook directories
    mkdir -p "$hook_dir/deploy"
    mkdir -p "$hook_dir/post"
    mkdir -p "$hook_dir/pre"
    
    # Determine absolute path to DNS manager
    local dns_manager_path="$DNS_MANAGER"
    if [ ! -f "$dns_manager_path" ]; then
        error "DNS manager script not found: $dns_manager_path"
        return 1
    fi
    
    # Make DNS manager executable
    chmod +x "$dns_manager_path"
    
    # Create auth hook script with absolute path
    cat > "$hook_dir/auth-hook.sh" << EOF
#!/bin/bash
# Certbot DNS-01 challenge auth hook
set -e

# Use absolute path to DNS manager
DNS_MANAGER="$dns_manager_path"

# Logging function
log() {
    echo "\$(date +'%Y-%m-%d %H:%M:%S') AUTH: \$1" >> /var/log/certbot-dns-hooks.log
}

# Validate DNS manager exists
if [ ! -f "\$DNS_MANAGER" ]; then
    echo "ERROR: DNS manager script not found: \$DNS_MANAGER"
    exit 1
fi

# Extract subdomain from CERTBOT_DOMAIN
SUBDOMAIN=\$(echo "\$CERTBOT_DOMAIN" | sed 's/\.attck-node\.net$//')

log "Creating DNS record for \$SUBDOMAIN with token \$CERTBOT_VALIDATION"

# Create DNS record
if "\$DNS_MANAGER" challenge create "\$SUBDOMAIN" "\$CERTBOT_VALIDATION"; then
    log "DNS record created successfully for \$SUBDOMAIN"
else
    log "ERROR: Failed to create DNS record for \$SUBDOMAIN"
    exit 1
fi

# Additional wait for propagation
log "Waiting 30 seconds for DNS propagation..."
sleep 30
EOF
    
    # Create cleanup hook script with absolute path
    cat > "$hook_dir/cleanup-hook.sh" << EOF
#!/bin/bash
# Certbot DNS-01 challenge cleanup hook
set -e

# Use absolute path to DNS manager
DNS_MANAGER="$dns_manager_path"

# Logging function
log() {
    echo "\$(date +'%Y-%m-%d %H:%M:%S') CLEANUP: \$1" >> /var/log/certbot-dns-hooks.log
}

# Validate DNS manager exists
if [ ! -f "\$DNS_MANAGER" ]; then
    echo "ERROR: DNS manager script not found: \$DNS_MANAGER"
    exit 1
fi

# Extract subdomain from CERTBOT_DOMAIN
SUBDOMAIN=\$(echo "\$CERTBOT_DOMAIN" | sed 's/\.attck-node\.net$//')

log "Cleaning up DNS record for \$SUBDOMAIN"

# Delete DNS record
if "\$DNS_MANAGER" challenge delete "\$SUBDOMAIN"; then
    log "DNS record cleaned up successfully for \$SUBDOMAIN"
else
    log "WARNING: Failed to cleanup DNS record for \$SUBDOMAIN"
fi
EOF
    
    # Make scripts executable
    chmod +x "$hook_dir/auth-hook.sh"
    chmod +x "$hook_dir/cleanup-hook.sh"
    
    # Create log file with proper permissions
    touch /var/log/certbot-dns-hooks.log
    chmod 644 /var/log/certbot-dns-hooks.log
    
    log "DNS hook scripts created with absolute paths"
    log "Hook logs will be written to /var/log/certbot-dns-hooks.log"
}

# Generate certificates for a slug
generate_certificates() {
    local slug=$1
    
    if [ -z "$slug" ]; then
        error "Usage: generate_certificates <slug>"
        return 1
    fi
    
    log "Generating certificates for slug: $slug"
    
    # Define service subdomains
    local services=("$slug" "$slug-reports" "$slug-empire" "$slug-mgmt" "$slug-kasm")
    local domains=()
    
    # Build domain list
    for service in "${services[@]}"; do
        domains+=("-d" "$service.$DOMAIN")
    done
    
    log "Requesting certificates for: ${services[*]}"
    
    # Request certificate using certbot with manual DNS challenge
    if certbot certonly \
        --manual \
        --preferred-challenges=dns \
        --email "$EMAIL" \
        --server https://acme-v02.api.letsencrypt.org/directory \
        --agree-tos \
        --manual-auth-hook "$CERT_DIR/renewal-hooks/auth-hook.sh" \
        --manual-cleanup-hook "$CERT_DIR/renewal-hooks/cleanup-hook.sh" \
        --cert-name "$slug-services" \
        "${domains[@]}" \
        --non-interactive; then
        
        log "✅ Certificates generated successfully for $slug"
        return 0
    else
        error "❌ Failed to generate certificates for $slug"
        return 1
    fi
}

# Deploy certificates to services
deploy_certificates() {
    local slug=$1
    
    if [ -z "$slug" ]; then
        error "Usage: deploy_certificates <slug>"
        return 1
    fi
    
    local cert_path="$CERT_DIR/live/$slug-services"
    
    if [ ! -d "$cert_path" ]; then
        error "Certificate directory not found: $cert_path"
        return 1
    fi
    
    log "Deploying certificates for slug: $slug"
    
    # Create certificate deployment directory
    local deploy_dir="/opt/rtpi-pen/certs/$slug"
    mkdir -p "$deploy_dir"
    
    # Copy certificates with proper permissions
    cp "$cert_path/fullchain.pem" "$deploy_dir/fullchain.pem"
    cp "$cert_path/privkey.pem" "$deploy_dir/privkey.pem"
    cp "$cert_path/cert.pem" "$deploy_dir/cert.pem"
    cp "$cert_path/chain.pem" "$deploy_dir/chain.pem"
    
    # Set proper permissions
    chmod 644 "$deploy_dir/fullchain.pem" "$deploy_dir/cert.pem" "$deploy_dir/chain.pem"
    chmod 600 "$deploy_dir/privkey.pem"
    chown -R root:root "$deploy_dir"
    
    # Create nginx-compatible certificate files
    cat "$cert_path/fullchain.pem" > "$deploy_dir/nginx.crt"
    cat "$cert_path/privkey.pem" > "$deploy_dir/nginx.key"
    
    log "✅ Certificates deployed to $deploy_dir"
}

# Update service configurations
update_service_configs() {
    local slug=$1
    
    if [ -z "$slug" ]; then
        error "Usage: update_service_configs <slug>"
        return 1
    fi
    
    log "Updating service configurations for slug: $slug"
    
    # Update SysReptor configuration
    update_sysreptor_config "$slug"
    
    # Update proxy configuration
    update_proxy_config "$slug"
    
    # Update Docker Compose with SSL configuration
    update_docker_compose "$slug"
    
    log "✅ Service configurations updated"
}

# Update SysReptor configuration
update_sysreptor_config() {
    local slug=$1
    local config_file="configs/rtpi-sysreptor/app.env"
    
    if [ ! -f "$config_file" ]; then
        warn "SysReptor config file not found: $config_file"
        return 0
    fi
    
    # Update ALLOWED_HOSTS
    local allowed_hosts="$slug-reports.$DOMAIN,sysreptor,0.0.0.0,127.0.0.1,$DOMAIN,rtpi-pen-dev"
    
    # Update or add ALLOWED_HOSTS
    if grep -q "^ALLOWED_HOSTS=" "$config_file"; then
        sed -i "s/^ALLOWED_HOSTS=.*/ALLOWED_HOSTS=\"$allowed_hosts\"/" "$config_file"
    else
        echo "ALLOWED_HOSTS=\"$allowed_hosts\"" >> "$config_file"
    fi
    
    # Enable SSL redirect
    if grep -q "^SECURE_SSL_REDIRECT=" "$config_file"; then
        sed -i "s/^#*SECURE_SSL_REDIRECT=.*/SECURE_SSL_REDIRECT=on/" "$config_file"
    else
        echo "SECURE_SSL_REDIRECT=on" >> "$config_file"
    fi
    
    log "SysReptor configuration updated"
}

# Update proxy configuration
update_proxy_config() {
    local slug=$1
    local nginx_config="services/rtpi-proxy/nginx/conf.d/rtpi-pen.conf"
    
    # Create SSL-enabled nginx configuration
    cat > "$nginx_config" << EOF
# RTPI-PEN SSL-enabled proxy configuration
# Generated for slug: $slug

# SSL Configuration
ssl_certificate /opt/rtpi-pen/certs/$slug/nginx.crt;
ssl_certificate_key /opt/rtpi-pen/certs/$slug/nginx.key;
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:50m;
ssl_session_tickets off;

# Modern SSL configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;

# HSTS
add_header Strict-Transport-Security "max-age=63072000" always;

# Main dashboard
server {
    listen 80;
    server_name $slug.$DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $slug.$DOMAIN;
    
    location / {
        proxy_pass http://rtpi-proxy:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# SysReptor
server {
    listen 80;
    server_name $slug-reports.$DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $slug-reports.$DOMAIN;
    
    location / {
        proxy_pass http://sysreptor-caddy:7777;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Empire C2
server {
    listen 80;
    server_name $slug-empire.$DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $slug-empire.$DOMAIN;
    
    location / {
        proxy_pass http://host.docker.internal:1337;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Portainer Management
server {
    listen 80;
    server_name $slug-mgmt.$DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $slug-mgmt.$DOMAIN;
    
    location / {
        proxy_pass http://rtpi-orchestrator:9000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# Kasm Workspaces (native installation)
server {
    listen 80;
    server_name $slug-kasm.$DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $slug-kasm.$DOMAIN;
    
    location / {
        proxy_pass https://localhost:8443;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_ssl_verify off;
    }
}
EOF
    
    log "Proxy configuration updated"
}

# Update Docker Compose for SSL
update_docker_compose() {
    local slug=$1
    
    # Add volume mount for certificates to proxy service
    # This will be handled by the build.sh script that calls this function
    
    log "Docker Compose SSL configuration prepared"
}

# Validate certificates
validate_certificates() {
    local slug=$1
    
    if [ -z "$slug" ]; then
        error "Usage: validate_certificates <slug>"
        return 1
    fi
    
    local cert_path="$CERT_DIR/live/$slug-services"
    
    if [ ! -f "$cert_path/fullchain.pem" ]; then
        error "Certificate not found: $cert_path/fullchain.pem"
        return 1
    fi
    
    log "Validating certificates for slug: $slug"
    
    # Check certificate validity
    local expiry=$(openssl x509 -in "$cert_path/fullchain.pem" -text -noout | grep "Not After" | cut -d: -f2-)
    local domains=$(openssl x509 -in "$cert_path/fullchain.pem" -text -noout | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/DNS://g' | tr ',' '\n' | sort)
    
    info "Certificate expiry: $expiry"
    info "Certificate domains:"
    echo "$domains" | while read -r domain; do
        info "  - $domain"
    done
    
    # Test certificate chain
    if openssl verify -CAfile "$cert_path/chain.pem" "$cert_path/cert.pem" >/dev/null 2>&1; then
        log "✅ Certificate chain validation successful"
    else
        error "❌ Certificate chain validation failed"
        return 1
    fi
    
    log "✅ Certificate validation completed"
}

# Setup certificate renewal
setup_renewal() {
    local slug=$1
    
    log "Setting up certificate renewal for slug: $slug"
    
    # Create renewal configuration
    local renewal_config="$CERT_DIR/renewal/$slug-services.conf"
    
    if [ ! -f "$renewal_config" ]; then
        warn "Renewal configuration not found: $renewal_config"
        return 0
    fi
    
    # Test renewal
    if certbot renew --cert-name "$slug-services" --dry-run; then
        log "✅ Certificate renewal test successful"
    else
        warn "⚠️ Certificate renewal test failed"
    fi
    
    # Add to cron if not already present
    local cron_job="0 0,12 * * * /usr/bin/certbot renew --quiet --post-hook '/opt/rtpi-pen/setup/cert_manager.sh deploy $slug'"
    
    if ! crontab -l 2>/dev/null | grep -q "$slug-services"; then
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        log "Certificate renewal cron job added"
    fi
    
    log "✅ Certificate renewal setup completed"
}

# Main function
main() {
    local action=$1
    local slug=$2
    
    case "$action" in
        "install-deps")
            check_root
            install_dependencies
            ;;
        "generate")
            if [ -z "$slug" ]; then
                error "Usage: $0 generate <slug>"
                exit 1
            fi
            check_root
            create_dns_hooks
            generate_certificates "$slug"
            ;;
        "deploy")
            if [ -z "$slug" ]; then
                error "Usage: $0 deploy <slug>"
                exit 1
            fi
            check_root
            deploy_certificates "$slug"
            ;;
        "configure")
            if [ -z "$slug" ]; then
                error "Usage: $0 configure <slug>"
                exit 1
            fi
            update_service_configs "$slug"
            ;;
        "validate")
            if [ -z "$slug" ]; then
                error "Usage: $0 validate <slug>"
                exit 1
            fi
            validate_certificates "$slug"
            ;;
        "setup-renewal")
            if [ -z "$slug" ]; then
                error "Usage: $0 setup-renewal <slug>"
                exit 1
            fi
            check_root
            setup_renewal "$slug"
            ;;
        "full-setup")
            if [ -z "$slug" ]; then
                error "Usage: $0 full-setup <slug>"
                exit 1
            fi
            check_root
            install_dependencies
            create_dns_hooks
            generate_certificates "$slug"
            deploy_certificates "$slug"
            update_service_configs "$slug"
            validate_certificates "$slug"
            setup_renewal "$slug"
            ;;
        *)
            echo "Usage: $0 <install-deps|generate|deploy|configure|validate|setup-renewal|full-setup> [slug]"
            echo ""
            echo "Commands:"
            echo "  install-deps           - Install certificate management dependencies"
            echo "  generate <slug>        - Generate SSL certificates for slug"
            echo "  deploy <slug>          - Deploy certificates to services"
            echo "  configure <slug>       - Update service configurations"
            echo "  validate <slug>        - Validate certificates"
            echo "  setup-renewal <slug>   - Setup certificate renewal"
            echo "  full-setup <slug>      - Complete certificate setup process"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
