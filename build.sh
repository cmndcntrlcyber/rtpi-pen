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
    if docker-compose build --no-cache; then
        log "Docker images built successfully"
    else
        error "Failed to build Docker images"
        exit 1
    fi
    
    # Start services
    if docker-compose up -d; then
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
            if docker-compose ps "$service" | grep -q "Up"; then
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

# Update Docker Compose for SSL certificate mounting
update_docker_compose_ssl() {
    log "Updating Docker Compose for SSL certificate mounting..."
    
    # Create backup of original docker-compose.yml
    cp docker-compose.yml docker-compose.yml.backup
    
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
    local running_containers=$(docker-compose ps --services --filter "status=running" | wc -l)
    local total_containers=$(docker-compose ps --services | wc -l)
    
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
    echo "• View logs: docker-compose logs -f"
    echo "• Restart services: docker-compose restart"
    echo "• Stop services: docker-compose down"
    echo "• Service status: docker-compose ps"
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
        docker-compose down 2>/dev/null || true
        error "You may need to run 'docker-compose down' manually"
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
    run_fresh_setup
    wait_for_system
    
    # Phase 2: Containerized services
    log "Phase 2: Containerized Services"
    start_containerized_services
    wait_for_services
    
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
    echo "ℹ️  For troubleshooting, check logs with: docker-compose logs -f"
    
    if [ "$ENABLE_SSL" = true ]; then
        echo "ℹ️  SSL certificate management: $CERT_MANAGER"
        echo "ℹ️  DNS management: $DNS_MANAGER"
    fi
}

# Run main function
main "$@"
