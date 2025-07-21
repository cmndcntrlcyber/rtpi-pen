#!/bin/bash

# RTPI-PEN Cloudflare DNS Manager - Working Version
# Simplified DNS management for Let's Encrypt ACME challenges
# Version: 1.1.0

# Configuration
CLOUDFLARE_API_TOKEN=$CF_API_TOKEN
DOMAIN=$CF_DOMAIN
ZONE_ID=$CF_ZONE_ID
EMAIL=$CF_EMAIL

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] DNS: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] DNS WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] DNS ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] DNS INFO: $1${NC}"
}

# Create DNS TXT record for ACME challenge
create_acme_record() {
    local subdomain=$1
    local token=$2
    
    log "Creating ACME TXT record for $subdomain..."
    
    local record_name="_acme-challenge.$subdomain"
    local full_record_name="$record_name.$DOMAIN"
    
    info "Record name: $full_record_name"
    info "Token: $token"
    
    local response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\": \"TXT\", \"name\": \"$record_name\", \"content\": \"$token\", \"ttl\": 120, \"proxied\": false}")
    
    local record_id=$(echo "$response" | jq -r '.result.id // empty')
    local success=$(echo "$response" | jq -r '.success // false')
    
    if [ "$success" == "true" ] && [ -n "$record_id" ] && [ "$record_id" != "null" ]; then
        log "✅ ACME record created successfully: $record_id"
        echo "$record_id"
        return 0
    else
        error "❌ Failed to create ACME record for $subdomain"
        echo "$response" | jq -r '.errors[]?.message // "Unknown error"' >&2
        return 1
    fi
}

# Delete DNS record
delete_dns_record() {
    local record_id=$1
    local subdomain=$2
    
    log "Deleting ACME record for $subdomain..."
    
    local response=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")
    
    local success=$(echo "$response" | jq -r '.success // false')
    
    if [ "$success" == "true" ]; then
        log "✅ ACME record deleted successfully"
        return 0
    else
        warn "⚠️ Failed to delete ACME record for $subdomain"
        echo "$response" | jq -r '.errors[]?.message // "Unknown error"' >&2
        return 1
    fi
}

# Main DNS challenge handler
handle_dns_challenge() {
    local action=$1
    local subdomain=$2
    local token=$3
    
    if [ -z "$action" ] || [ -z "$subdomain" ]; then
        error "Usage: handle_dns_challenge <create|delete> <subdomain> [token]"
        return 1
    fi
    
    case "$action" in
        "create")
            if [ -z "$token" ]; then
                error "Token required for create action"
                return 1
            fi
            
            local record_id=$(create_acme_record "$subdomain" "$token")
            if [ $? -ne 0 ]; then
                return 1
            fi
            
            # Store record ID for cleanup
            echo "$record_id" > "/tmp/acme_record_${subdomain//[^a-zA-Z0-9]/_}.id"
            log "Record ID stored for cleanup: $record_id"
            
            # Wait briefly for propagation
            log "Waiting 30 seconds for DNS propagation..."
            sleep 30
            
            # Verify record exists
            local check_result=$(dig +short TXT "_acme-challenge.$subdomain.$DOMAIN" @1.1.1.1 2>/dev/null | tr -d '"' | head -1)
            if [ -n "$check_result" ]; then
                log "✅ DNS record verified: $check_result"
            else
                warn "⚠️ DNS record not yet visible, but continuing..."
            fi
            ;;
            
        "delete")
            local record_id_file="/tmp/acme_record_${subdomain//[^a-zA-Z0-9]/_}.id"
            if [ -f "$record_id_file" ]; then
                local record_id=$(cat "$record_id_file")
                delete_dns_record "$record_id" "$subdomain"
                rm -f "$record_id_file"
            else
                warn "No record ID found for $subdomain cleanup"
            fi
            ;;
            
        *)
            error "Invalid action: $action. Use create or delete"
            return 1
            ;;
    esac
}

# Create A records for services
create_service_records() {
    local slug=$1
    local server_ip=$2
    
    if [ -z "$slug" ] || [ -z "$server_ip" ]; then
        error "Usage: create_service_records <slug> <server_ip>"
        return 1
    fi
    
    # Service subdomains
    local services=("$slug" "$slug-reports" "$slug-empire" "$slug-mgmt" "$slug-kasm")
    
    for service in "${services[@]}"; do
        log "Creating A record for $service.$DOMAIN -> $server_ip"
        
        local response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"type\": \"A\", \"name\": \"$service\", \"content\": \"$server_ip\", \"ttl\": 300, \"proxied\": false}")
        
        local success=$(echo "$response" | jq -r '.success // false')
        
        if [ "$success" == "true" ]; then
            log "✅ A record created successfully for $service.$DOMAIN"
        else
            warn "⚠️ Failed to create A record for $service.$DOMAIN"
            echo "$response" | jq -r '.errors[]?.message // "Unknown error"' >&2
        fi
    done
}

# Main function
main() {
    local action=$1
    shift
    
    case "$action" in
        "challenge")
            handle_dns_challenge "$@"
            ;;
        "create-records")
            create_service_records "$@"
            ;;
        "validate")
            validate_config
            ;;
        "test")
            log "Testing DNS manager..."
            validate_config && create_acme_record "test" "test_token_123"
            ;;
        *)
            echo "Usage: $0 <challenge|create-records|validate|test> [options]"
            echo ""
            echo "Commands:"
            echo "  challenge create <subdomain> <token>  - Create ACME challenge record"
            echo "  challenge delete <subdomain>         - Delete ACME challenge record"
            echo "  create-records <slug> <server_ip>    - Create A records for services"
            echo "  validate                             - Validate Cloudflare configuration"
            echo "  test                                 - Test DNS manager functionality"
            exit 1
            ;;
    esac
}

# Validate configuration
validate_config() {
    log "Validating Cloudflare configuration..."
    
    if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
        error "CF_API_TOKEN not set"
        return 1
    fi
    
    if [ -z "$DOMAIN" ]; then
        error "CF_DOMAIN not set"
        return 1
    fi
    
    if [ -z "$ZONE_ID" ]; then
        error "CF_ZONE_ID not set"
        return 1
    fi
    
    if [ -z "$EMAIL" ]; then
        error "CF_EMAIL not set"
        return 1
    fi
    
    info "Configuration variables loaded:"
    info "  Domain: $DOMAIN"
    info "  Email: $EMAIL"
    info "  Zone ID: ${ZONE_ID:0:8}..."
    info "  API Token: ${CLOUDFLARE_API_TOKEN:0:8}..."
    
    # Test API connectivity
    log "Testing Cloudflare API connectivity..."
    local response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")
    
    local success=$(echo "$response" | jq -r '.success // false')
    
    if [ "$success" == "true" ]; then
        local zone_name=$(echo "$response" | jq -r '.result.name // "unknown"')
        log "✅ API connectivity successful - Zone: $zone_name"
        return 0
    else
        error "❌ API connectivity failed"
        echo "$response" | jq -r '.errors[]?.message // "Unknown error"' >&2
        return 1
    fi
}

# Check dependencies
check_dependencies() {
    local deps=("curl" "jq" "dig")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            error "Required dependency '$dep' not found"
            exit 1
        fi
    done
}

# Run dependency check
check_dependencies

# Execute main function
main "$@"
