#!/bin/bash

# RTPI-PEN Unified Build Script
# Complete system deployment with Native Kasm + Containerized Services + SSL Certificate Automation
# Version: 1.18.0

set -e  # Exit on any error

# Configuration
DOMAIN="attck-node.net"
CERT_MANAGER="./setup/cert_manager.sh"
DNS_MANAGER="./setup/cloudflare_dns_manager.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SLUG=""
ENABLE_SSL=false
SERVER_IP=""

# Kasm detection and cleanup functions
check_kasm_status() {
    log "Checking existing Kasm installation status..."
    
    # Check if native Kasm service exists and is active
    local native_active=false
    local native_runtime=0
    
    if systemctl is-active --quiet kasm 2>/dev/null; then
        native_active=true
        # Get service start time and calculate runtime
        local start_time=$(systemctl show kasm --property=ActiveEnterTimestamp --value)
        if [ -n "$start_time" ] && [ "$start_time" != "0" ]; then
            local start_epoch=$(date -d "$start_time" +%s 2>/dev/null)
            local current_epoch=$(date +%s)
            native_runtime=$((current_epoch - start_epoch))
        fi
    fi
    
    # Check for containerized Kasm workspaces
    local container_active=false
    local container_runtime=0
    
    local kasm_containers=$(docker ps --filter "name=kasm" --format "{{.Names}}" 2>/dev/null)
    if [ -n "$kasm_containers" ]; then
        container_active=true
        # Get oldest container start time
        local oldest_start=$(docker ps --filter "name=kasm" --format "{{.CreatedAt}}" | sort | head -1)
        if [ -n "$oldest_start" ]; then
            local start_epoch=$(date -d "$oldest_start" +%s 2>/dev/null)
            local current_epoch=$(date +%s)
            container_runtime=$((current_epoch - start_epoch))
        fi
    fi
    
    # Check API accessibility
    local api_accessible=false
    if curl -k -s --connect-timeout 5 https://localhost:8443/api/public/get_token | grep -q "token" 2>/dev/null; then
        api_accessible=true
    fi
    
    # Determine status
    local max_runtime=$((native_runtime > container_runtime ? native_runtime : container_runtime))
    local min_runtime_threshold=600  # 10 minutes in seconds
    
    if ($native_active || $container_active) && $api_accessible && [ $max_runtime -gt $min_runtime_threshold ]; then
        echo "WORKING"
    elif $native_active || $container_active || [ -d "/opt/kasm" ] || [ -n "$(docker images --filter 'reference=kasm*' -q 2>/dev/null)" ]; then
        echo "BROKEN"
    else
        echo "ABSENT"
    fi
}

cleanup_broken_kasm() {
    log "Cleaning up broken Kasm installation..."
    
    # Stop native Kasm service if running
    if systemctl is-active --quiet kasm 2>/dev/null; then
        log "Stopping native Kasm service..."
        systemctl stop kasm || true
        systemctl disable kasm || true
    fi
    
    # Remove Kasm containers
    log "Removing Kasm containers..."
    local kasm_containers=$(docker ps -aq --filter "name=kasm" 2>/dev/null)
    if [ -n "$kasm_containers" ]; then
        docker rm -f $kasm_containers || true
    fi
    
    # Remove Kasm images
    log "Removing Kasm images..."
    local kasm_images=$(docker images --filter "reference=kasm*" -q 2>/dev/null)
    if [ -n "$kasm_images" ]; then
        docker rmi -f $kasm_images || true
    fi
    
    # Remove Kasm networks
    log "Removing Kasm networks..."
    local kasm_networks=$(docker network ls --filter "name=kasm" -q 2>/dev/null)
    if [ -n "$kasm_networks" ]; then
        docker network rm $kasm_networks || true
    fi
    
    # Remove Kasm volumes
    log "Removing Kasm volumes..."
    local kasm_volumes=$(docker volume ls --filter "name=kasm" -q 2>/dev/null)
    if [ -n "$kasm_volumes" ]; then
        docker volume rm $kasm_volumes || true
    fi
    
    # Clean up Kasm directories
    log "Cleaning up Kasm directories..."
    if [ -d "/opt/kasm" ]; then
        rm -rf /opt/kasm || true
    fi
    
    # Remove any kasm-related systemd services
    if [ -f "/etc/systemd/system/kasm.service" ]; then
        rm -f /etc/systemd/system/kasm.service || true
    fi
    
    # Reload systemd
    systemctl daemon-reload || true
    
    log "Kasm cleanup completed"
}

# Port conflict detection and cleanup functions
check_port_8443_usage() {
    log "Checking port 8443 usage..."
    
    # Get processes using port 8443
    local port_users=$(lsof -Pi :8443 -sTCP:LISTEN 2>/dev/null || echo "")
    
    if [ -n "$port_users" ]; then
        log "Port 8443 is in use:"
        echo "$port_users"
        return 1
    else
        log "Port 8443 is available"
        return 0
    fi
}

cleanup_port_8443_conflicts() {
    log "Cleaning up port 8443 conflicts..."
    
    # Stop any Docker containers using port 8443
    local containers_using_port=$(docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Ports}}" | grep ":8443" | awk '{print $1}' || echo "")
    
    if [ -n "$containers_using_port" ]; then
        log "Stopping containers using port 8443..."
        for container in $containers_using_port; do
            log "Stopping container: $container"
            docker stop "$container" || true
            docker rm -f "$container" || true
        done
    fi
    
    # Stop docker-compose services that might be using port 8443
    if [ -f "/opt/rtpi-pen/docker-compose.yml" ]; then
        log "Stopping docker-compose services..."
        cd /opt/rtpi-pen
        docker compose down || true
        cd - > /dev/null
    fi
    
    # Kill any remaining processes on port 8443
    local port_pids=$(lsof -t -i:8443 2>/dev/null || echo "")
    if [ -n "$port_pids" ]; then
        log "Killing remaining processes on port 8443..."
        for pid in $port_pids; do
            kill -9 "$pid" 2>/dev/null || true
        done
    fi
    
    # Wait a moment for processes to cleanup
    sleep 3
    
    # Verify port is now free
    if check_port_8443_usage; then
        log "Port 8443 successfully freed"
        return 0
    else
        error "Failed to free port 8443"
        return 1
    fi
}

# Enhanced Kasm cleanup with port conflict resolution
cleanup_broken_kasm_enhanced() {
    log "Enhanced Kasm cleanup with port conflict resolution..."
    
    # First, cleanup port conflicts
    cleanup_port_8443_conflicts
    
    # Then do the standard Kasm cleanup
    cleanup_broken_kasm
    
    log "Enhanced Kasm cleanup completed"
}

# Portainer detection and cleanup functions
check_portainer_status() {
    log "Checking existing Portainer installation status..."
    
    # Check for Portainer container
    local container_active=false
    local container_runtime=0
    
    if docker ps --filter "name=portainer" --format "{{.Names}}" | grep -q "portainer" 2>/dev/null; then
        container_active=true
        # Get container start time
        local start_time=$(docker inspect --format='{{.State.StartedAt}}' portainer 2>/dev/null)
        if [ -n "$start_time" ]; then
            local start_epoch=$(date -d "$start_time" +%s 2>/dev/null)
            local current_epoch=$(date +%s)
            container_runtime=$((current_epoch - start_epoch))
        fi
    fi
    
    # Check API accessibility
    local api_accessible=false
    if curl -s --connect-timeout 5 http://localhost:9443 | grep -q "Portainer" 2>/dev/null; then
        api_accessible=true
    fi
    
    # Determine status
    local min_runtime_threshold=600  # 10 minutes in seconds
    
    if $container_active && $api_accessible && [ $container_runtime -gt $min_runtime_threshold ]; then
        echo "WORKING"
    elif $container_active || docker ps -a --filter "name=portainer" --format "{{.Names}}" | grep -q "portainer" 2>/dev/null; then
        echo "BROKEN"
    else
        echo "ABSENT"
    fi
}

cleanup_broken_portainer() {
    log "Cleaning up broken Portainer installation..."
    
    # Remove Portainer container
    local portainer_container=$(docker ps -aq --filter "name=portainer" 2>/dev/null)
    if [ -n "$portainer_container" ]; then
        docker rm -f $portainer_container || true
        log "Removed Portainer container"
    fi
    
    # Remove Portainer volumes
    local portainer_volumes=$(docker volume ls --filter "name=portainer" -q 2>/dev/null)
    if [ -n "$portainer_volumes" ]; then
        docker volume rm $portainer_volumes || true
        log "Removed Portainer volumes"
    fi
    
    log "Portainer cleanup completed"
}

# Security services detection and cleanup functions
check_security_services_status() {
    log "Checking existing security services installation status..."
    
    # Check Vaultwarden
    local vaultwarden_active=false
    local vaultwarden_runtime=0
    
    if docker ps --filter "name=vaultwarden" --format "{{.Names}}" | grep -q "vaultwarden" 2>/dev/null; then
        vaultwarden_active=true
        local start_time=$(docker inspect --format='{{.State.StartedAt}}' vaultwarden 2>/dev/null)
        if [ -n "$start_time" ]; then
            local start_epoch=$(date -d "$start_time" +%s 2>/dev/null)
            local current_epoch=$(date +%s)
            vaultwarden_runtime=$((current_epoch - start_epoch))
        fi
    fi
    
    # Check Empire C2 (native service)
    local empire_active=false
    local empire_runtime=0
    
    if systemctl is-active --quiet empire 2>/dev/null; then
        empire_active=true
        local start_time=$(systemctl show empire --property=ActiveEnterTimestamp --value)
        if [ -n "$start_time" ] && [ "$start_time" != "0" ]; then
            local start_epoch=$(date -d "$start_time" +%s 2>/dev/null)
            local current_epoch=$(date +%s)
            empire_runtime=$((current_epoch - start_epoch))
        fi
    fi
    
    # Check API accessibility
    local vaultwarden_api_accessible=false
    local empire_api_accessible=false
    
    if curl -s --connect-timeout 5 http://localhost:8080/alive 2>/dev/null; then
        vaultwarden_api_accessible=true
    fi
    
    if curl -s --connect-timeout 5 http://localhost:1337 2>/dev/null; then
        empire_api_accessible=true
    fi
    
    # Determine status
    local min_runtime_threshold=600  # 10 minutes in seconds
    local max_runtime=$((vaultwarden_runtime > empire_runtime ? vaultwarden_runtime : empire_runtime))
    
    if ($vaultwarden_active || $empire_active) && ($vaultwarden_api_accessible || $empire_api_accessible) && [ $max_runtime -gt $min_runtime_threshold ]; then
        echo "WORKING"
    elif $vaultwarden_active || $empire_active || [ -d "/opt/Empire" ] || docker ps -a --filter "name=vaultwarden" --format "{{.Names}}" | grep -q "vaultwarden" 2>/dev/null; then
        echo "BROKEN"
    else
        echo "ABSENT"
    fi
}

cleanup_broken_security_services() {
    log "Cleaning up broken security services..."
    
    # Stop Empire service if running
    if systemctl is-active --quiet empire 2>/dev/null; then
        log "Stopping Empire service..."
        systemctl stop empire || true
        systemctl disable empire || true
    fi
    
    # Remove Vaultwarden container
    local vaultwarden_container=$(docker ps -aq --filter "name=vaultwarden" 2>/dev/null)
    if [ -n "$vaultwarden_container" ]; then
        docker rm -f $vaultwarden_container || true
        log "Removed Vaultwarden container"
    fi
    
    # Remove Vaultwarden volumes
    local vaultwarden_volumes=$(docker volume ls --filter "name=vaultwarden" -q 2>/dev/null)
    if [ -n "$vaultwarden_volumes" ]; then
        docker volume rm $vaultwarden_volumes || true
        log "Removed Vaultwarden volumes"
    fi
    
    # Clean up Empire directory
    if [ -d "/opt/Empire" ]; then
        rm -rf /opt/Empire || true
        log "Removed Empire directory"
    fi
    
    # Remove Empire systemd service
    if [ -f "/etc/systemd/system/empire.service" ]; then
        rm -f /etc/systemd/system/empire.service || true
        systemctl daemon-reload || true
        log "Removed Empire service"
    fi
    
    log "Security services cleanup completed"
}

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

RTPI-PEN Unified Build Script with SSL Certificate Automation

Options:
    --slug <slug>        Organizational slug for domain generation (required for SSL)
    --enable-ssl         Enable SSL certificate generation
    --server-ip <ip>     Server IP address for DNS records (auto-detected if not provided)
    --help               Show this help message

Examples:
    $0 --slug c3s --enable-ssl
    $0 --slug demo --enable-ssl --server-ip 192.168.1.100
    $0 (basic deployment without SSL)

Generated domains (with --slug c3s):
    • c3s.attck-node.net           (Main dashboard)
    • c3s-reports.attck-node.net   (SysReptor)
    • c3s-empire.attck-node.net    (Empire C2)
    • c3s-mgmt.attck-node.net      (Portainer)
    • c3s-kasm.attck-node.net      (Kasm Workspaces)

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --slug)
                SLUG="$2"
                shift 2
                ;;
            --enable-ssl)
                ENABLE_SSL=true
                shift
                ;;
            --server-ip)
                SERVER_IP="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate SSL requirements
    if [ "$ENABLE_SSL" = true ] && [ -z "$SLUG" ]; then
        error "SSL requires --slug parameter"
        usage
        exit 1
    fi
}

# Validate IPv4 address format
is_valid_ipv4() {
    local ip=$1
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ $ip =~ $regex ]]; then
        # Check each octet is between 0-255
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if [[ $octet -lt 0 || $octet -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Auto-detect server IP (IPv4 only)
detect_server_ip() {
    if [ -z "$SERVER_IP" ]; then
        log "Auto-detecting server IP address..."
        
        # Try multiple methods to detect IPv4 address specifically
        local detected_ip=""
        
        # Method 1: Force IPv4 with curl -4 flag
        detected_ip=$(curl -4 -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "")
        if [ -n "$detected_ip" ] && is_valid_ipv4 "$detected_ip"; then
            SERVER_IP="$detected_ip"
        fi
        
        # Method 2: Try alternative IPv4 services
        if [ -z "$SERVER_IP" ]; then
            detected_ip=$(curl -4 -s --connect-timeout 5 ipinfo.io/ip 2>/dev/null || echo "")
            if [ -n "$detected_ip" ] && is_valid_ipv4 "$detected_ip"; then
                SERVER_IP="$detected_ip"
            fi
        fi
        
        # Method 3: Try ipecho.net with IPv4 filter
        if [ -z "$SERVER_IP" ]; then
            detected_ip=$(curl -4 -s --connect-timeout 5 ipecho.net/plain 2>/dev/null || echo "")
            if [ -n "$detected_ip" ] && is_valid_ipv4 "$detected_ip"; then
                SERVER_IP="$detected_ip"
            fi
        fi
        
        # Method 4: Try ip4.me service
        if [ -z "$SERVER_IP" ]; then
            detected_ip=$(curl -s --connect-timeout 5 ip4.me 2>/dev/null | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | head -1 || echo "")
            if [ -n "$detected_ip" ] && is_valid_ipv4 "$detected_ip"; then
                SERVER_IP="$detected_ip"
            fi
        fi
        
        # Method 5: Fallback to local IPv4 address
        if [ -z "$SERVER_IP" ]; then
            # Get all IPs and filter for IPv4
            local ips=$(hostname -I 2>/dev/null || echo "")
            for ip in $ips; do
                if is_valid_ipv4 "$ip" && [[ ! "$ip" =~ ^127\. ]] && [[ ! "$ip" =~ ^169\.254\. ]]; then
                    SERVER_IP="$ip"
                    break
                fi
            done
        fi
        
        # Method 6: Try ip route method
        if [ -z "$SERVER_IP" ]; then
            detected_ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' | head -1 || echo "")
            if [ -n "$detected_ip" ] && is_valid_ipv4 "$detected_ip"; then
                SERVER_IP="$detected_ip"
            fi
        fi
        
        if [ -z "$SERVER_IP" ]; then
            error "Unable to detect IPv4 address. Please provide --server-ip parameter"
            error "Note: DNS A records require IPv4 addresses, not IPv6"
            exit 1
        fi
        
        # Final validation
        if ! is_valid_ipv4 "$SERVER_IP"; then
            error "Detected IP address is not a valid IPv4 address: $SERVER_IP"
            error "Please provide a valid IPv4 address with --server-ip parameter"
            exit 1
        fi
        
        log "Detected server IP: $SERVER_IP"
    else
        log "Using provided server IP: $SERVER_IP"
        
        # Validate provided IP
        if ! is_valid_ipv4 "$SERVER_IP"; then
            error "Provided IP address is not a valid IPv4 address: $SERVER_IP"
            error "Please provide a valid IPv4 address"
            exit 1
        fi
    fi
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root"
        echo "Please run with: sudo ./build.sh"
        exit 1
    fi
}

# Validate environment
validate_environment() {
    log "Validating environment..."
    
    # Check if we're in the right directory
    if [ ! -f "fresh-rtpi-pen.sh" ] || [ ! -f "docker-compose.yml" ]; then
        error "Please run this script from the RTPI-PEN root directory"
        exit 1
    fi
    
    # Check available disk space (minimum 10GB)
    available_space=$(df . | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 10485760 ]; then  # 10GB in KB
        warn "Low disk space detected. Minimum 10GB recommended."
    fi
    
    # Check internet connectivity
    if ! ping -c 1 google.com &> /dev/null; then
        error "Internet connectivity required for installation"
        exit 1
    fi
    
    log "Environment validation completed"
}

# Run fresh system setup
run_fresh_setup() {
    log "Starting fresh system setup..."
    
    # Make script executable
    chmod +x fresh-rtpi-pen.sh
    
    # Run the fresh setup script
    if ./fresh-rtpi-pen.sh; then
        log "Fresh system setup completed successfully"
    else
        error "Fresh system setup failed"
        exit 1
    fi
}

# Wait for system to stabilize
wait_for_system() {
    log "Waiting for system to stabilize..."
    sleep 30
    
    # Check if Kasm is running
    if systemctl is-active --quiet kasm; then
        log "Kasm service is active"
    else
        warn "Kasm service is not yet active, waiting..."
        sleep 60
        if systemctl is-active --quiet kasm; then
            log "Kasm service is now active"
        else
            error "Kasm service failed to start"
            exit 1
        fi
    fi
}

# Build and start containerized services
start_containerized_services() {
    log "Building and starting containerized services..."
    
    # Build images
    if docker compose build; then
        log "Docker images built successfully"
    else
        error "Failed to build Docker images"
        exit 1
    fi
    
    # Start services
    if docker compose up -d; then
        log "Containerized services started successfully"
    else
        error "Failed to start containerized services"
        exit 1
    fi
}

# Wait for services to be ready
wait_for_services() {
    log "Waiting for services to be ready..."
    
    # Wait for database to be ready
    info "Waiting for database services..."
    sleep 30
    
    # Check critical services
    local services=("rtpi-database" "rtpi-cache" "rtpi-healer")
    for service in "${services[@]}"; do
        local retries=0
        while [ $retries -lt 30 ]; do
            if docker compose ps "$service" | grep -q "Up"; then
                log "$service is ready"
                break
            else
                info "Waiting for $service..."
                sleep 10
                ((retries++))
            fi
        done
        
        if [ $retries -eq 30 ]; then
            error "$service failed to start within timeout"
            exit 1
        fi
    done
}

# SSL Certificate Generation Phase
setup_ssl_certificates() {
    if [ "$ENABLE_SSL" != true ]; then
        log "SSL disabled, skipping certificate generation"
        return 0
    fi
    
    log "Phase 0.5: SSL Certificate Generation"
    
    # Detect server IP for DNS records
    detect_server_ip
    
    # Create DNS A records for services
    log "Creating DNS A records for $SLUG services..."
    if ! "$DNS_MANAGER" create-records "$SLUG" "$SERVER_IP"; then
        error "Failed to create DNS records"
        exit 1
    fi
    
    # Wait for DNS propagation
    log "Waiting for DNS propagation..."
    sleep 60
    
    # Generate SSL certificates
    log "Generating SSL certificates for $SLUG..."
    if ! "$CERT_MANAGER" full-setup "$SLUG"; then
        error "Failed to generate SSL certificates"
        exit 1
    fi
    
    # Update Docker Compose for SSL
    update_docker_compose_ssl
    
    log "✅ SSL certificates generated and configured"
}

# Force cleanup of SysReptor configuration files
force_cleanup_sysreptor_config() {
    local config_dir="configs/rtpi-sysreptor"
    local app_env_file="$config_dir/app.env"
    
    log "🔄 Force cleaning SysReptor configuration for fresh generation..."
    
    # Backup existing config if it exists
    if [ -f "$app_env_file" ]; then
        local backup_file="$config_dir/app.env.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$app_env_file" "$backup_file" 2>/dev/null || true
        log "Backed up existing config to: $backup_file"
        rm -f "$app_env_file"
    fi
    
    # Remove any template or temporary files
    rm -f "$config_dir/app.env.template" "$config_dir/app.env.example" "$config_dir/app.env.tmp" 2>/dev/null || true
    
    log "Configuration cleanup completed"
}

# Generate and validate cryptographic keys
generate_validated_keys() {
    log "🔐 Generating fresh cryptographic keys..."
    
    # Generate SECRET_KEY - Django compatible, no padding issues
    SECRET_KEY=$(openssl rand -hex 32)
    if [ ${#SECRET_KEY} -ne 64 ]; then
        error "Failed to generate valid SECRET_KEY (expected 64 chars, got ${#SECRET_KEY})"
        return 1
    fi
    
    # Generate UUID for encryption key
    KEY_ID=$(uuidgen)
    if [ -z "$KEY_ID" ]; then
        error "Failed to generate UUID for encryption key"
        return 1
    fi
    
    # Generate ENCRYPTION_KEY - FIXED: Keep base64 padding, remove only newlines
    local raw_key=$(openssl rand -base64 44 | tr -d '\n')
    ENCRYPTION_KEY="$raw_key"
    
    # Validate base64 encoding immediately
    if ! echo "$ENCRYPTION_KEY" | base64 -d >/dev/null 2>&1; then
        error "Generated encryption key failed base64 validation"
        return 1
    fi
    
    # Ensure key meets minimum length requirements
    local decoded_length=$(echo "$ENCRYPTION_KEY" | base64 -d | wc -c)
    if [ "$decoded_length" -lt 32 ]; then
        error "Encryption key too short after decoding ($decoded_length bytes, need ≥32)"
        return 1
    fi
    
    log "✅ Generated and validated cryptographic keys:"
    log "   SECRET_KEY: ${#SECRET_KEY} characters"
    log "   ENCRYPTION_KEY: ${#ENCRYPTION_KEY} characters (${decoded_length} bytes decoded)"
    log "   KEY_ID: $KEY_ID"
    
    return 0
}

# Create app.env file atomically
create_app_env_atomic() {
    local config_dir="configs/rtpi-sysreptor"
    local app_env_file="$config_dir/app.env"
    local temp_file="$config_dir/app.env.tmp"
    
    log "📝 Creating fresh SysReptor configuration file..."
    
    # Create temporary file first
    cat > "$temp_file" << EOF
# SysReptor Configuration
# Generated automatically by RTPI-PEN build process
# Build Date: $(date)
# Build ID: $(date +%Y%m%d-%H%M%S)
# DO NOT EDIT MANUALLY - This file is auto-generated on every build

# Security Keys
SECRET_KEY=$SECRET_KEY

# Database Configuration
DATABASE_HOST=rtpi-database
DATABASE_NAME=sysreptor
DATABASE_USER=sysreptor
DATABASE_PASSWORD=sysreptorpassword
DATABASE_PORT=5432

# Encryption Keys - Base64 encoded with proper padding
ENCRYPTION_KEYS=[{"id":"$KEY_ID","key":"$ENCRYPTION_KEY","cipher":"AES-GCM","revoked":false}]
DEFAULT_ENCRYPTION_KEY_ID=$KEY_ID

# Security and Access
ALLOWED_HOSTS=sysreptor,0.0.0.0,127.0.0.1,rtpi-pen-dev,localhost
SECURE_SSL_REDIRECT=off
USE_X_FORWARDED_HOST=on
DEBUG=off

# Redis Configuration
REDIS_HOST=sysreptor-redis
REDIS_PORT=6379
REDIS_INDEX=0
REDIS_PASSWORD=sysreptorredispassword

# Features and Plugins
ENABLE_PRIVATE_DESIGNS=true
DISABLE_WEBSOCKETS=true
ENABLED_PLUGINS=cyberchef,graphqlvoyager,checkthehash

# Performance and Scaling
CELERY_BROKER_URL=redis://:sysreptorredispassword@sysreptor-redis:6379/0
CELERY_RESULT_BACKEND=redis://:sysreptorredispassword@sysreptor-redis:6379/0
EOF
    
    # Move temp file to final location (atomic operation)
    if mv "$temp_file" "$app_env_file"; then
        chmod 644 "$app_env_file"
        log "✅ Configuration file created successfully"
        return 0
    else
        error "Failed to create configuration file"
        rm -f "$temp_file" 2>/dev/null || true
        return 1
    fi
}

# Comprehensive validation of app.env file
validate_app_env_file() {
    local config_dir="configs/rtpi-sysreptor"
    local app_env_file="$config_dir/app.env"
    
    log "🔍 Validating generated app.env file..."
    
    if [ ! -f "$app_env_file" ]; then
        error "❌ app.env file does not exist"
        return 1
    fi
    
    # Check file size
    local file_size=$(wc -c < "$app_env_file")
    if [ "$file_size" -lt 500 ]; then
        error "❌ app.env file too small ($file_size bytes)"
        return 1
    fi
    
    # Check for required keys
    local required_keys=("SECRET_KEY" "DATABASE_HOST" "ENCRYPTION_KEYS" "REDIS_HOST" "DEFAULT_ENCRYPTION_KEY_ID")
    for key in "${required_keys[@]}"; do
        if ! grep -q "^$key=" "$app_env_file"; then
            error "❌ Missing required key: $key"
            return 1
        fi
    done
    
    # Validate base64 encoding in ENCRYPTION_KEYS
    local enc_key_line=$(grep "^ENCRYPTION_KEYS=" "$app_env_file")
    local enc_key_value=$(echo "$enc_key_line" | sed -n 's/.*"key":"\([^"]*\)".*/\1/p')
    
    if [ -z "$enc_key_value" ]; then
        error "❌ Could not extract encryption key from ENCRYPTION_KEYS"
        return 1
    fi
    
    # Test base64 decoding
    if ! echo "$enc_key_value" | base64 -d >/dev/null 2>&1; then
        error "❌ Encryption key failed base64 validation: $enc_key_value"
        return 1
    fi
    
    # Test Docker environment file compatibility
    if command -v docker >/dev/null 2>&1; then
        if ! docker run --rm --env-file "$app_env_file" alpine:latest /bin/sh -c 'echo "Environment file syntax OK"' >/dev/null 2>&1; then
            error "❌ Docker cannot parse the env file"
            return 1
        fi
    fi
    
    log "✅ app.env file validation passed"
    log "   File size: $file_size bytes"
    log "   Encryption key: ${#enc_key_value} characters (base64 valid)"
    
    return 0
}

# Generate SysReptor configuration - Enhanced with automated fresh generation
generate_sysreptor_config() {
    log "🚀 Generating fresh SysReptor configuration (automated build)..."
    
    # Create config directory
    local config_dir="configs/rtpi-sysreptor"
    mkdir -p "$config_dir"
    
    # Step 1: Force cleanup of existing configs
    if ! force_cleanup_sysreptor_config; then
        error "Failed to cleanup existing configuration"
        return 1
    fi
    
    # Step 2: Generate and validate new keys
    if ! generate_validated_keys; then
        error "Failed to generate cryptographic keys"
        return 1
    fi
    
    # Step 3: Create new configuration file atomically
    if ! create_app_env_atomic; then
        error "Failed to create app.env file"
        return 1
    fi
    
    # Step 4: Comprehensive validation
    if ! validate_app_env_file; then
        error "Generated configuration failed validation"
        return 1
    fi
    
    log "✅ SysReptor configuration generated successfully"
    log "   Location: $config_dir/app.env"
    log "   Status: Fresh generation with validated keys"
    log "   Build: Automated and secure"
    
    return 0
}

# Create SysReptor superuser after services are running
create_sysreptor_superuser() {
    log "Setting up SysReptor superuser account..."
    
    # Get current system username
    local current_user=$(whoami)
    local username
    
    # Check if running in automated mode (non-interactive terminal)
    if [ ! -t 0 ] || [ -n "$AUTOMATED_MODE" ]; then
        # Non-interactive/automated mode
        username="rtpi-admin"
        log "Running in automated mode - using default username: $username"
    else
        # Interactive mode
        echo ""
        echo "============================================"
        echo "🔐 SysReptor User Account Configuration"
        echo "============================================"
        echo "Choose username option for SysReptor:"
        echo "1. Use current system username ($current_user)"
        echo "2. Create custom username"
        echo "3. Use default (rtpi-admin)"
        echo ""
        read -p "Enter your choice (1-3) [default: 3]: " choice
        
        case $choice in
            1)
                username="$current_user"
                log "Using current system username: $username"
                ;;
            2)
                while true; do
                    read -p "Enter custom username: " custom_username
                    # Validate username (alphanumeric, underscore, hyphen only)
                    if [[ "$custom_username" =~ ^[a-zA-Z0-9_-]+$ ]] && [[ ${#custom_username} -ge 3 ]]; then
                        username="$custom_username"
                        log "Using custom username: $username"
                        break
                    else
                        error "Username must be at least 3 characters and contain only letters, numbers, underscores, or hyphens"
                    fi
                done
                ;;
            3|"")
                username="rtpi-admin"
                log "Using default username: $username"
                ;;
            *)
                warn "Invalid choice, using default username: rtpi-admin"
                username="rtpi-admin"
                ;;
        esac
    fi
    
    # Wait for SysReptor service to be ready
    log "Waiting for SysReptor service to be ready..."
    local max_wait=120  # 2 minutes
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if docker compose ps sysreptor-app | grep -q "Up"; then
            log "SysReptor service is running"
            break
        fi
        
        if [ $wait_time -eq 0 ]; then
            info "Waiting for sysreptor-app service to start..."
        fi
        
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    if [ $wait_time -ge $max_wait ]; then
        error "SysReptor service failed to start within timeout"
        return 1
    fi
    
    # Additional wait for service initialization
    log "Waiting for SysReptor to complete initialization..."
    sleep 15
    
    # Create superuser with automated credentials for non-interactive mode
    log "Creating SysReptor superuser account: $username"
    
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        info "Attempt $attempt of $max_attempts..."
        
        if [ ! -t 0 ] || [ -n "$AUTOMATED_MODE" ]; then
            # Automated mode - create user with default credentials
            if docker compose exec -T sysreptor-app python3 manage.py shell << EOF
import os
from django.contrib.auth import get_user_model
User = get_user_model()
if not User.objects.filter(username='$username').exists():
    user = User.objects.create_superuser('$username', 'admin@rtpi.local', 'rtpi-admin-password')
    print(f"Superuser '{username}' created successfully!")
else:
    print(f"Superuser '{username}' already exists")
EOF
            then
                log "✅ SysReptor superuser '$username' created successfully!"
                log "🌐 Access SysReptor at: http://localhost:7777"
                log "🔑 Username: $username"
                log "🔑 Password: rtpi-admin-password"
                return 0
            fi
        else
            # Interactive mode - prompt for credentials
            if docker compose exec sysreptor-app python3 manage.py createsuperuser --username "$username"; then
                log "✅ SysReptor superuser '$username' created successfully!"
                log "🌐 Access SysReptor at: http://localhost:7777"
                log "🔑 Username: $username"
                return 0
            fi
        fi
        
        warn "Failed to create superuser (attempt $attempt/$max_attempts)"
        
        if [ $attempt -eq $max_attempts ]; then
            error "All attempts failed. You can create the superuser manually later:"
            error "   docker compose exec sysreptor-app python3 manage.py createsuperuser --username $username"
            return 1
        else
            info "Retrying in 5 seconds..."
            sleep 5
        fi
        
        attempt=$((attempt + 1))
    done
    
    return 1
}

# Update Docker Compose for SSL certificate mounting
update_docker_compose_ssl() {
    log "Updating Docker Compose for SSL certificate mounting..."
    
    # Add certificate volume mount to proxy service
    local cert_volume="      - /opt/rtpi-pen/certs/$SLUG:/opt/rtpi-pen/certs/$SLUG:ro"
    
    # Add the volume mount to rtpi-proxy service
    if ! grep -q "/opt/rtpi-pen/certs" docker-compose.yml; then
        # Find the volumes section of rtpi-proxy and add certificate mount
        sed -i '/rtpi-proxy:/,/^[[:space:]]*[^[:space:]]/ {
            /volumes:/a\
      - /opt/rtpi-pen/certs:/opt/rtpi-pen/certs:ro
        }' docker-compose.yml
    fi
    
    log "Docker Compose updated for SSL"
}

# Update final status display for SSL
show_ssl_final_status() {
    if [ "$ENABLE_SSL" = true ]; then
        echo ""
        echo "🔒 SSL-Enabled Access Points:"
        echo "• Main Dashboard: https://$SLUG.$DOMAIN"
        echo "• SysReptor: https://$SLUG-reports.$DOMAIN"
        echo "• Empire C2: https://$SLUG-empire.$DOMAIN"
        echo "• Portainer: https://$SLUG-mgmt.$DOMAIN"
        echo "• Kasm Workspaces: https://$SLUG-kasm.$DOMAIN"
        echo ""
        echo "🔐 Certificate Information:"
        echo "• Certificate Location: /opt/rtpi-pen/certs/$SLUG/"
        echo "• Auto-renewal: Enabled (twice daily)"
        echo "• Certificate Management: $CERT_MANAGER"
        echo "• DNS Management: $DNS_MANAGER"
        echo ""
        echo "🌐 DNS Records Created:"
        echo "• $SLUG.$DOMAIN -> $SERVER_IP"
        echo "• $SLUG-reports.$DOMAIN -> $SERVER_IP"
        echo "• $SLUG-empire.$DOMAIN -> $SERVER_IP"
        echo "• $SLUG-mgmt.$DOMAIN -> $SERVER_IP"
        echo "• $SLUG-kasm.$DOMAIN -> $SERVER_IP"
    fi
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check Kasm Workspaces
    if curl -k -s https://localhost:8443/api/public/get_token | grep -q "token"; then
        log "✅ Kasm Workspaces API is responding"
    else
        warn "⚠️  Kasm Workspaces API not yet ready"
    fi
    
    # Check Portainer
    if curl -s http://localhost:9443 | grep -q "Portainer"; then
        log "✅ Portainer is responding"
    else
        warn "⚠️  Portainer not yet ready"
    fi
    
    # Check healer service
    if curl -s http://localhost:8888/health | grep -q "status"; then
        log "✅ Self-healing service is responding"
    else
        warn "⚠️  Self-healing service not yet ready"
    fi
    
    # Check Docker services
    local running_containers=$(docker compose ps --services --filter "status=running" | wc -l)
    local total_containers=$(docker compose ps --services | wc -l)
    
    if [ "$running_containers" -eq "$total_containers" ]; then
        log "✅ All containerized services are running ($running_containers/$total_containers)"
    else
        warn "⚠️  Some services may still be starting ($running_containers/$total_containers)"
    fi
}

# Show final status
show_final_status() {
    echo ""
    echo "=============================================="
    echo "🎉 RTPI-PEN DEPLOYMENT COMPLETED"
    echo "=============================================="
    echo ""
    echo "🌐 Access Points:"
    echo "• Kasm Workspaces: https://localhost:8443"
    echo "• Portainer: https://localhost:9443"
    echo "• SysReptor: http://localhost:7777"
    echo "• Empire C2: http://localhost:1337"
    echo "• Healer API: http://localhost:8888/health"
    echo ""
    echo "🔧 Management Commands:"
    echo "• View logs: docker compose logs -f"
    echo "• Restart services: docker compose restart"
    echo "• Stop services: docker compose down"
    echo "• Service status: docker compose ps"
    echo ""
    echo "🏥 Self-Healing Features:"
    echo "• Automatic container restart on failure"
    echo "• Native Kasm service monitoring"
    echo "• Health checks every 30 seconds"
    echo "• Configuration backup every 6 hours"
    echo ""
    echo "📋 Default Credentials:"
    echo "• Kasm: admin@kasm.local / password"
    echo "• Portainer: admin / admin (set on first login)"
    echo ""
    echo "🚀 System is ready for Red Team operations!"
    echo "=============================================="
}

# Cleanup function
cleanup() {
    if [ $? -ne 0 ]; then
        error "Build failed. Cleaning up..."
        docker compose down 2>/dev/null || true
        error "You may need to run 'docker compose down' manually"
    fi
}

# Main execution
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    echo "🚀 Starting RTPI-PEN Build Process..."
    echo "======================================"
    
    if [ "$ENABLE_SSL" = true ]; then
        log "SSL Mode: ENABLED for slug: $SLUG"
        log "Domain: $DOMAIN"
    else
        log "SSL Mode: DISABLED"
    fi
    
    # Pre-flight checks
    check_root
    validate_environment
    
    # Phase 0.5: SSL Certificate Generation (if enabled)
    if [ "$ENABLE_SSL" = true ]; then
        setup_ssl_certificates
    fi
    
    # Phase 1: Fresh system setup (native Kasm + system tools)
    log "Phase 1: Fresh System Setup"
    
    # Check existing Kasm installation before proceeding
    kasm_status=$(check_kasm_status)
    case $kasm_status in
        "WORKING")
            log "✅ Kasm is already installed and working (>10 min), skipping Kasm installation"
            export SKIP_KASM_INSTALLATION=true
            ;;
        "BROKEN")
            log "🔧 Kasm detected but not working properly, cleaning up..."
            cleanup_broken_kasm_enhanced
            log "🚀 Proceeding with fresh Kasm installation..."
            export SKIP_KASM_INSTALLATION=false
            ;;
        "ABSENT")
            log "📦 No Kasm installation detected, proceeding with installation..."
            # Even for absent, check for port conflicts
            if ! check_port_8443_usage; then
                log "Port 8443 is in use, cleaning up conflicts..."
                cleanup_port_8443_conflicts
            fi
            export SKIP_KASM_INSTALLATION=false
            ;;
    esac
    
    run_fresh_setup
    
    # Only wait for system if we didn't skip Kasm installation
    if [ "$SKIP_KASM_INSTALLATION" != "true" ]; then
        wait_for_system
    else
        log "Skipping system wait since Kasm was already running"
    fi
    
    # Phase 2: Containerized services
    log "Phase 2: Containerized Services"
    
    # Generate SysReptor configuration before building containers
    generate_sysreptor_config
    
    start_containerized_services
    wait_for_services
    
    # Create SysReptor superuser after services are ready
    create_sysreptor_superuser
    
    # Phase 3: Validation and status
    log "Phase 3: Validation"
    validate_deployment
    show_final_status
    show_ssl_final_status
    
    # Remove cleanup trap since we succeeded
    trap - EXIT
    
    log "Build completed successfully!"
    
    # Save build information
    cat > /opt/rtpi-pen-build.info << EOF
RTPI-PEN Build Information
Build Date: $(date)
Build Script: build.sh v1.18.0
Kasm Version: 1.17.0
Architecture: Native Kasm + Containerized Services
SSL Enabled: $ENABLE_SSL
Slug: $SLUG
Domain: $DOMAIN
Server IP: $SERVER_IP
Build Status: SUCCESS
EOF
    
    echo ""
    echo "ℹ️  Build information saved to /opt/rtpi-pen-build.info"
    echo "ℹ️  For troubleshooting, check logs with: docker compose logs -f"
    
    if [ "$ENABLE_SSL" = true ]; then
        echo "ℹ️  SSL certificate management: $CERT_MANAGER"
        echo "ℹ️  DNS management: $DNS_MANAGER"
    fi
}

# Run main function
main "$@"
