#!/bin/bash
# RTPI-PEN Docker Compose Generator
# Generates docker-compose.yml from template with resolved image tags

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] COMPOSE-GENERATOR:${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] COMPOSE-GENERATOR: ✅${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] COMPOSE-GENERATOR: ⚠️${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] COMPOSE-GENERATOR: ❌${NC} $1"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname $(dirname "$SCRIPT_DIR"))"
TEMPLATE_FILE="$SCRIPT_DIR/templates/docker-compose.template.yml"
OUTPUT_FILE="$PROJECT_ROOT/docker-compose.yml"
RESOLVED_TAGS_FILE="$PROJECT_ROOT/configs/resolved-image-tags.env"
BACKUP_DIR="$SCRIPT_DIR/backups"

# Function to create backup of existing docker-compose.yml
backup_existing_compose() {
    if [ -f "$OUTPUT_FILE" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="$BACKUP_DIR/docker-compose.yml.backup.$timestamp"
        
        mkdir -p "$BACKUP_DIR"
        cp "$OUTPUT_FILE" "$backup_file"
        log_success "Backed up existing docker-compose.yml to $backup_file"
        return 0
    else
        log "No existing docker-compose.yml to backup"
        return 0
    fi
}

# Function to load resolved image tags as environment variables
load_resolved_tags() {
    log "Loading resolved image tags..."
    
    if [ ! -f "$RESOLVED_TAGS_FILE" ]; then
        log_error "Resolved tags file not found: $RESOLVED_TAGS_FILE"
        log "Run './scripts/image-resolver.sh resolve' first"
        return 1
    fi
    
    local loaded_count=0
    local failed_count=0
    
    # Read resolved tags and export as environment variables
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$(echo "$line" | xargs)" ]] && continue
        
        # Parse resolved tag line: VAR_NAME=image:tag
        if [[ "$line" =~ ^([^=]+)=(.+)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local full_image_name="${BASH_REMATCH[2]}"
            
            # Export as environment variable
            export "$var_name=$full_image_name"
            log "Loaded $var_name=$full_image_name"
            ((loaded_count++))
        else
            log_warning "Skipping invalid line: $line"
            ((failed_count++))
        fi
    done < "$RESOLVED_TAGS_FILE"
    
    log_success "Loaded $loaded_count image tags as environment variables"
    
    if [ $failed_count -gt 0 ]; then
        log_warning "$failed_count lines were skipped due to invalid format"
    fi
    
    return 0
}

# Function to set default fallback values for missing variables
set_fallback_defaults() {
    log "Setting fallback defaults for missing variables..."
    
    # Core infrastructure defaults (should always be available)
    export POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:15}"
    export REDIS_IMAGE="${REDIS_IMAGE:-redis:7.2}"
    export CADDY_IMAGE="${CADDY_IMAGE:-caddy:latest}"
    export NGINX_IMAGE="${NGINX_IMAGE:-nginx:alpine}"
    export REGISTRY_IMAGE="${REGISTRY_IMAGE:-registry:latest}"
    export NODE_IMAGE="${NODE_IMAGE:-node:lts}"
    
    # Kasm images with safer defaults
    export KASM_VSCODE_IMAGE="${KASM_VSCODE_IMAGE:-linuxserver/code-server:latest}"
    export KASM_KALI_IMAGE="${KASM_KALI_IMAGE:-kalilinux/kali-rolling:latest}"
    
    # SysReptor defaults
    export SYSREPTOR_APP_IMAGE="${SYSREPTOR_APP_IMAGE:-syslifters/sysreptor:latest}"
    export SYSREPTOR_REDIS_IMAGE="${SYSREPTOR_REDIS_IMAGE:-bitnami/redis:latest}"
    
    # Security services defaults
    export VAULTWARDEN_IMAGE="${VAULTWARDEN_IMAGE:-vaultwarden/server:latest}"
    
    log_success "Fallback defaults configured"
}

# Function to validate template file
validate_template() {
    log "Validating template file..."
    
    if [ ! -f "$TEMPLATE_FILE" ]; then
        log_error "Template file not found: $TEMPLATE_FILE"
        return 1
    fi
    
    # Basic YAML syntax check (if yamllint is available)
    if command -v yamllint &> /dev/null; then
        if yamllint "$TEMPLATE_FILE" 2>/dev/null; then
            log_success "Template file passed YAML validation"
        else
            log_warning "Template file has YAML syntax warnings (proceeding anyway)"
        fi
    else
        log "yamllint not available, skipping YAML validation"
    fi
    
    # Check for required sections
    local required_sections=("services" "networks" "volumes")
    for section in "${required_sections[@]}"; do
        if grep -q "^$section:" "$TEMPLATE_FILE"; then
            log "✓ Found required section: $section"
        else
            log_error "Missing required section: $section"
            return 1
        fi
    done
    
    log_success "Template file validation passed"
    return 0
}

# Function to generate docker-compose.yml from template
generate_compose_file() {
    log "Generating docker-compose.yml from template..."
    
    # Use envsubst to substitute environment variables in template
    if command -v envsubst &> /dev/null; then
        if envsubst < "$TEMPLATE_FILE" > "$OUTPUT_FILE"; then
            log_success "Generated docker-compose.yml using envsubst"
        else
            log_error "Failed to generate docker-compose.yml with envsubst"
            return 1
        fi
    else
        log_warning "envsubst not available, using manual substitution"
        
        # Manual substitution using sed (less reliable but works)
        cp "$TEMPLATE_FILE" "$OUTPUT_FILE"
        
        # Replace environment variables manually
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$(echo "$line" | xargs)" ]] && continue
            
            if [[ "$line" =~ ^([^=]+)=(.+)$ ]]; then
                local var_name="${BASH_REMATCH[1]}"
                local var_value="${BASH_REMATCH[2]}"
                
                # Escape special characters for sed
                local escaped_value=$(echo "$var_value" | sed 's/[[\.*^$()+?{|]/\\&/g')
                
                # Replace in output file
                sed -i "s/\${$var_name:-[^}]*}/$escaped_value/g" "$OUTPUT_FILE"
                sed -i "s/\${$var_name}/$escaped_value/g" "$OUTPUT_FILE"
            fi
        done < "$RESOLVED_TAGS_FILE"
        
        log_success "Generated docker-compose.yml using manual substitution"
    fi
    
    return 0
}

# Function to validate generated compose file
validate_generated_compose() {
    log "Validating generated docker-compose.yml..."
    
    if [ ! -f "$OUTPUT_FILE" ]; then
        log_error "Generated compose file not found: $OUTPUT_FILE"
        return 1
    fi
    
    # Check Docker Compose syntax
    local compose_cmd=""
    if command -v docker-compose &> /dev/null; then
        compose_cmd="docker-compose"
    elif docker compose version &> /dev/null; then
        compose_cmd="docker compose"
    else
        log_error "Docker Compose not found"
        return 1
    fi
    
    # Validate compose file syntax
    if $compose_cmd -f "$OUTPUT_FILE" config >/dev/null 2>&1; then
        log_success "Generated compose file passed validation"
    else
        log_error "Generated compose file failed validation"
        log "Running validation with output:"
        $compose_cmd -f "$OUTPUT_FILE" config
        return 1
    fi
    
    # Check for any remaining unresolved variables
    local unresolved=$(grep -o '\${[^}]*}' "$OUTPUT_FILE" 2>/dev/null || true)
    if [ -n "$unresolved" ]; then
        log_warning "Found unresolved variables in generated file:"
        echo "$unresolved" | sort | uniq
        log "These will use their default values or may cause errors"
    else
        log_success "All variables resolved successfully"
    fi
    
    return 0
}

# Function to generate service-specific compose files
generate_profile_compose_files() {
    log "Generating profile-specific compose files..."
    
    local profiles=("core" "kasm" "security" "optional")
    
    for profile in "${profiles[@]}"; do
        local profile_file="$PROJECT_ROOT/docker-compose.$profile.yml"
        
        # Generate compose file for specific profile
        if command -v docker-compose &> /dev/null; then
            docker-compose -f "$OUTPUT_FILE" --profile "$profile" config > "$profile_file" 2>/dev/null || true
        elif docker compose version &> /dev/null; then
            docker compose -f "$OUTPUT_FILE" --profile "$profile" config > "$profile_file" 2>/dev/null || true
        fi
        
        if [ -f "$profile_file" ] && [ -s "$profile_file" ]; then
            log_success "Generated docker-compose.$profile.yml"
        else
            log_warning "Failed to generate docker-compose.$profile.yml"
            rm -f "$profile_file"
        fi
    done
}

# Function to show generation summary
show_generation_summary() {
    log "Generation Summary:"
    echo ""
    echo -e "${GREEN}📄 Docker Compose Generation Completed!${NC}"
    echo ""
    echo -e "${BLUE}Generated Files:${NC}"
    
    if [ -f "$OUTPUT_FILE" ]; then
        local file_size=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "unknown")
        echo -e "  ✅ docker-compose.yml (${file_size} bytes)"
    else
        echo -e "  ❌ docker-compose.yml (not generated)"
    fi
    
    # Check for profile files
    for profile in core kasm security optional; do
        local profile_file="$PROJECT_ROOT/docker-compose.$profile.yml"
        if [ -f "$profile_file" ]; then
            local file_size=$(stat -f%z "$profile_file" 2>/dev/null || stat -c%s "$profile_file" 2>/dev/null || echo "unknown")
            echo -e "  ✅ docker-compose.$profile.yml (${file_size} bytes)"
        fi
    done
    
    echo ""
    echo -e "${BLUE}Image Information:${NC}"
    
    # Show resolved images
    if [ -f "$RESOLVED_TAGS_FILE" ]; then
        local total_images=$(grep -c "^[^#].*=" "$RESOLVED_TAGS_FILE" 2>/dev/null || echo "0")
        echo -e "  📦 Total resolved images: $total_images"
        
        # Show some key images
        echo -e "  🔧 Key images:"
        for key_var in KASM_VSCODE_IMAGE KASM_KALI_IMAGE SYSREPTOR_APP_IMAGE VAULTWARDEN_IMAGE; do
            local image_value=$(grep "^$key_var=" "$RESOLVED_TAGS_FILE" 2>/dev/null | cut -d'=' -f2)
            if [ -n "$image_value" ]; then
                echo -e "    • $key_var: $image_value"
            fi
        done
    fi
    
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo -e "  1. Review generated docker-compose.yml"
    echo -e "  2. Run image verification: ./scripts/image-checker.sh verify"
    echo -e "  3. Deploy services: ./deploy-self-healing.sh"
    echo ""
    echo -e "${YELLOW}Note: Use specific profiles for targeted deployments:${NC}"
    echo -e "  docker-compose --profile core up -d     # Core services only"
    echo -e "  docker-compose --profile kasm up -d     # Include Kasm services"
    echo -e "  docker-compose --profile security up -d # Include security services"
}

# Function to show help
show_help() {
    echo "RTPI-PEN Docker Compose Generator"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  generate      Generate docker-compose.yml from template (default)"
    echo "  validate      Validate template and generated files"
    echo "  profiles      Generate profile-specific compose files"
    echo "  backup        Backup existing docker-compose.yml"
    echo "  help          Show this help message"
    echo ""
    echo "Options:"
    echo "  --template FILE   Use custom template file"
    echo "  --output FILE     Use custom output file"
    echo "  --no-backup       Skip backup of existing compose file"
    echo ""
    echo "Examples:"
    echo "  $0 generate                   # Generate docker-compose.yml"
    echo "  $0 validate                   # Validate files"
    echo "  $0 profiles                   # Generate profile files"
    echo "  $0 --no-backup generate       # Generate without backup"
}

# Main function
main() {
    local command="${1:-generate}"
    local no_backup=false
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --template)
                TEMPLATE_FILE="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --no-backup)
                no_backup=true
                shift
                ;;
            generate|validate|profiles|backup|help)
                command="$1"
                shift
                ;;
            *)
                if [[ "$1" != "$command" ]]; then
                    log_error "Unknown option: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    case "$command" in
        generate)
            if [ "$no_backup" = "false" ]; then
                backup_existing_compose
            fi
            
            validate_template || exit 1
            load_resolved_tags || exit 1
            set_fallback_defaults
            generate_compose_file || exit 1
            validate_generated_compose || exit 1
            show_generation_summary
            ;;
        validate)
            validate_template || exit 1
            if [ -f "$OUTPUT_FILE" ]; then
                validate_generated_compose || exit 1
            else
                log_warning "No generated compose file to validate"
            fi
            ;;
        profiles)
            if [ ! -f "$OUTPUT_FILE" ]; then
                log_error "docker-compose.yml not found. Run 'generate' first."
                exit 1
            fi
            generate_profile_compose_files
            ;;
        backup)
            backup_existing_compose
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
