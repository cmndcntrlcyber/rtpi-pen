#!/bin/bash

# RTPI-PEN Certificate Renewal Script
# Automated SSL certificate renewal and deployment
# Version: 1.0.0

set -e

# Configuration
DOMAIN="attck-node.net"
CERT_DIR="/etc/letsencrypt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_MANAGER="$SCRIPT_DIR/cert_manager.sh"
RTPI_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] RENEWAL: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] RENEWAL WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] RENEWAL ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] RENEWAL INFO: $1${NC}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root"
        exit 1
    fi
}

# Get all certificate slugs
get_certificate_slugs() {
    local slugs=()
    
    if [ -d "$CERT_DIR/live" ]; then
        for cert_dir in "$CERT_DIR/live"/*-services; do
            if [ -d "$cert_dir" ]; then
                local slug=$(basename "$cert_dir" | sed 's/-services$//')
                slugs+=("$slug")
            fi
        done
    fi
    
    printf '%s\n' "${slugs[@]}"
}

# Check certificate expiry
check_certificate_expiry() {
    local slug=$1
    local cert_path="$CERT_DIR/live/$slug-services/fullchain.pem"
    
    if [ ! -f "$cert_path" ]; then
        error "Certificate not found: $cert_path"
        return 1
    fi
    
    local expiry_date=$(openssl x509 -in "$cert_path" -text -noout | grep "Not After" | cut -d: -f2- | xargs)
    local expiry_timestamp=$(date -d "$expiry_date" +%s)
    local current_timestamp=$(date +%s)
    local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
    
    info "Certificate for $slug expires in $days_until_expiry days ($expiry_date)"
    
    # Return 0 if renewal needed (less than 30 days), 1 if not
    if [ $days_until_expiry -lt 30 ]; then
        return 0
    else
        return 1
    fi
}

# Renew certificate for a specific slug
renew_certificate() {
    local slug=$1
    
    log "Renewing certificate for slug: $slug"
    
    # Use certbot to renew the certificate
    if certbot renew --cert-name "$slug-services" --quiet; then
        log "Certificate renewed successfully for $slug"
    else
        error "Failed to renew certificate for $slug"
        return 1
    fi
    
    # Deploy renewed certificate
    if "$CERT_MANAGER" deploy "$slug"; then
        log "Certificate deployed successfully for $slug"
    else
        error "Failed to deploy certificate for $slug"
        return 1
    fi
    
    # Restart services to pick up new certificates
    restart_services "$slug"
}

# Restart services after certificate renewal
restart_services() {
    local slug=$1
    
    log "Restarting services for certificate update: $slug"
    
    # Change to RTPI root directory
    cd "$RTPI_ROOT"
    
    # Restart proxy service to pick up new certificates
    if docker-compose restart rtpi-proxy; then
        log "Proxy service restarted successfully"
    else
        warn "Failed to restart proxy service"
    fi
    
    # Optional: Restart other services if needed
    # docker-compose restart sysreptor-caddy
    
    log "Service restart completed"
}

# Send notification about renewal
send_notification() {
    local slug=$1
    local status=$2
    local message=$3
    
    # Log the notification
    if [ "$status" = "success" ]; then
        log "NOTIFICATION: Certificate renewal successful for $slug"
    else
        error "NOTIFICATION: Certificate renewal failed for $slug - $message"
    fi
    
    # Optional: Add email/webhook notifications here
    # curl -X POST "https://hooks.slack.com/..." -d "{'text': '$message'}"
}

# Main renewal function
renew_certificates() {
    log "Starting certificate renewal process..."
    
    local slugs=($(get_certificate_slugs))
    
    if [ ${#slugs[@]} -eq 0 ]; then
        info "No certificates found for renewal"
        return 0
    fi
    
    local renewed_count=0
    local failed_count=0
    
    for slug in "${slugs[@]}"; do
        info "Checking certificate for slug: $slug"
        
        if check_certificate_expiry "$slug"; then
            log "Certificate for $slug needs renewal"
            
            if renew_certificate "$slug"; then
                ((renewed_count++))
                send_notification "$slug" "success" "Certificate renewed successfully"
            else
                ((failed_count++))
                send_notification "$slug" "failed" "Certificate renewal failed"
            fi
        else
            info "Certificate for $slug is still valid"
        fi
    done
    
    log "Renewal process completed"
    log "Certificates renewed: $renewed_count"
    log "Renewal failures: $failed_count"
    
    return $failed_count
}

# Force renewal of all certificates
force_renewal() {
    log "Forcing renewal of all certificates..."
    
    local slugs=($(get_certificate_slugs))
    
    if [ ${#slugs[@]} -eq 0 ]; then
        info "No certificates found for renewal"
        return 0
    fi
    
    for slug in "${slugs[@]}"; do
        log "Force renewing certificate for slug: $slug"
        renew_certificate "$slug"
    done
}

# Show certificate status
show_status() {
    log "Certificate Status Report"
    echo "========================"
    
    local slugs=($(get_certificate_slugs))
    
    if [ ${#slugs[@]} -eq 0 ]; then
        info "No certificates found"
        return 0
    fi
    
    for slug in "${slugs[@]}"; do
        local cert_path="$CERT_DIR/live/$slug-services/fullchain.pem"
        
        if [ -f "$cert_path" ]; then
            local expiry_date=$(openssl x509 -in "$cert_path" -text -noout | grep "Not After" | cut -d: -f2- | xargs)
            local expiry_timestamp=$(date -d "$expiry_date" +%s)
            local current_timestamp=$(date +%s)
            local days_until_expiry=$(( (expiry_timestamp - current_timestamp) / 86400 ))
            
            echo "Slug: $slug"
            echo "  Expiry: $expiry_date"
            echo "  Days until expiry: $days_until_expiry"
            
            if [ $days_until_expiry -lt 30 ]; then
                echo "  Status: ⚠️  RENEWAL NEEDED"
            elif [ $days_until_expiry -lt 7 ]; then
                echo "  Status: 🚨 URGENT RENEWAL NEEDED"
            else
                echo "  Status: ✅ Valid"
            fi
            echo ""
        fi
    done
}

# Setup cron job for automatic renewal
setup_cron() {
    log "Setting up automatic certificate renewal..."
    
    local cron_job="0 0,12 * * * /opt/rtpi-pen/setup/cert_renewal.sh renew >/var/log/cert-renewal.log 2>&1"
    
    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "cert_renewal.sh"; then
        log "Cron job already exists"
    else
        # Add cron job
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        log "Cron job added for automatic renewal (twice daily)"
    fi
}

# Main function
main() {
    local action=$1
    
    case "$action" in
        "renew")
            check_root
            renew_certificates
            ;;
        "force")
            check_root
            force_renewal
            ;;
        "status")
            show_status
            ;;
        "setup-cron")
            check_root
            setup_cron
            ;;
        *)
            echo "Usage: $0 <renew|force|status|setup-cron>"
            echo ""
            echo "Commands:"
            echo "  renew       - Renew certificates that are expiring soon"
            echo "  force       - Force renewal of all certificates"
            echo "  status      - Show certificate status"
            echo "  setup-cron  - Setup automatic renewal cron job"
            echo ""
            echo "Examples:"
            echo "  $0 renew       # Daily renewal check"
            echo "  $0 status      # Check certificate status"
            echo "  $0 setup-cron  # Setup automatic renewal"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
