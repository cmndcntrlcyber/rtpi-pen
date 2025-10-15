#!/bin/bash
# RTPI-PEN Image Availability Checker
# Pre-deployment verification of Docker images

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] IMAGE-CHECKER:${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] IMAGE-CHECKER: ✅${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] IMAGE-CHECKER: ⚠️${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] IMAGE-CHECKER: ❌${NC} $1"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESOLVED_TAGS_FILE="$PROJECT_ROOT/configs/resolved-image-tags.env"

# Function to check if Docker is available and running
check_docker() {
    log "Checking Docker availability..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        return 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running or not accessible"
        return 1
    fi
    
    log_success "Docker is available and running"
    return 0
}

# Function to pull an image with retry logic
pull_image_with_retry() {
    local image="$1"
    local max_attempts="${2:-3}"
    local delay="${3:-5}"
    
    log "Attempting to pull $image..."
    
    for attempt in $(seq 1 $max_attempts); do
        log "Pull attempt $attempt/$max_attempts for $image"
        
        if docker pull "$image" 2>/dev/null; then
            log_success "Successfully pulled $image"
            return 0
        else
            if [ $attempt -lt $max_attempts ]; then
                log_warning "Pull attempt $attempt failed, retrying in ${delay}s..."
                sleep $delay
                # Increase delay for next attempt
                delay=$((delay * 2))
            else
                log_error "Failed to pull $image after $max_attempts attempts"
                return 1
            fi
        fi
    done
}

# Function to check if image exists locally
check_local_image() {
    local image="$1"
    
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^$image$"; then
        log_success "Image $image is available locally"
        return 0
    else
        log "Image $image not found locally"
        return 1
    fi
}

# Function to check image manifest without pulling
check_image_manifest() {
    local image="$1"
    
    log "Checking manifest for $image..."
    
    if docker manifest inspect "$image" >/dev/null 2>&1; then
        log_success "Image $image manifest is accessible"
        return 0
    else
        log_error "Image $image manifest is not accessible"
        return 1
    fi
}

# Function to get image size information
get_image_info() {
    local image="$1"
    
    # Try to get image info from local Docker first
    local size=$(docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep "^$image" | awk '{print $2}' 2>/dev/null)
    
    if [ -n "$size" ]; then
        echo "Local size: $size"
        return 0
    fi
    
    # If not local, try to get info from manifest
    local manifest_info=$(docker manifest inspect "$image" 2>/dev/null)
    if [ -n "$manifest_info" ]; then
        local config_size=$(echo "$manifest_info" | grep -o '"size":[0-9]*' | head -1 | cut -d':' -f2)
        if [ -n "$config_size" ] && [ "$config_size" -gt 0 ]; then
            local size_mb=$((config_size / 1024 / 1024))
            echo "Manifest size: ${size_mb}MB"
            return 0
        fi
    fi
    
    echo "Size unknown"
    return 1
}

# Function to verify a single image
verify_single_image() {
    local image="$1"
    local pull_if_missing="${2:-false}"
    local critical="${3:-false}"
    
    log "Verifying image: $image"
    
    # Check if image exists locally
    if check_local_image "$image"; then
        local info=$(get_image_info "$image")
        log_success "✓ $image ($info)"
        return 0
    fi
    
    # Check if image manifest is accessible
    if check_image_manifest "$image"; then
        if [ "$pull_if_missing" = "true" ]; then
            if pull_image_with_retry "$image"; then
                local info=$(get_image_info "$image")
                log_success "✓ $image (pulled, $info)"
                return 0
            else
                if [ "$critical" = "true" ]; then
                    log_error "✗ $image (CRITICAL - pull failed)"
                    return 1
                else
                    log_warning "⚠ $image (pull failed, but not critical)"
                    return 0
                fi
            fi
        else
            log_success "✓ $image (manifest available, not pulled)"
            return 0
        fi
    else
        if [ "$critical" = "true" ]; then
            log_error "✗ $image (CRITICAL - not available)"
            return 1
        else
            log_warning "⚠ $image (not available, but not critical)"
            return 0
        fi
    fi
}

# Function to verify all resolved images
verify_all_images() {
    local pull_if_missing="${1:-false}"
    local fail_on_critical="${2:-true}"
    
    log "Starting image verification process..."
    
    if [ ! -f "$RESOLVED_TAGS_FILE" ]; then
        log_error "Resolved tags file not found: $RESOLVED_TAGS_FILE"
        log "Run './scripts/image-resolver.sh resolve' first"
        return 1
    fi
    
    local total_count=0
    local success_count=0
    local warning_count=0
    local error_count=0
    local critical_errors=0
    
    # Define critical images that must be available
    local critical_images=(
        "postgres"
        "redis"
        "nginx"
        "caddy"
    )
    
    echo ""
    log "Verification Results:"
    echo "======================================"
    
    # Read resolved tags and verify each one
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$(echo "$line" | xargs)" ]] && continue
        
        # Parse resolved tag line: VAR_NAME=image:tag
        if [[ "$line" =~ ^([^=]+)=(.+)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local full_image_name="${BASH_REMATCH[2]}"
            
            ((total_count++))
            
            # Check if this is a critical image
            local is_critical=false
            for critical_pattern in "${critical_images[@]}"; do
                if [[ "$full_image_name" == *"$critical_pattern"* ]]; then
                    is_critical=true
                    break
                fi
            done
            
            # Verify the image
            if verify_single_image "$full_image_name" "$pull_if_missing" "$is_critical"; then
                ((success_count++))
            else
                if [ "$is_critical" = "true" ]; then
                    ((critical_errors++))
                    ((error_count++))
                else
                    ((warning_count++))
                fi
            fi
        fi
    done < "$RESOLVED_TAGS_FILE"
    
    echo "======================================"
    echo ""
    
    # Summary
    log "Verification Summary:"
    echo "  Total images: $total_count"
    echo "  ✅ Success: $success_count"
    echo "  ⚠️  Warnings: $warning_count"
    echo "  ❌ Errors: $error_count"
    echo "  🔴 Critical errors: $critical_errors"
    
    # Determine exit status
    if [ $critical_errors -gt 0 ] && [ "$fail_on_critical" = "true" ]; then
        log_error "Critical image verification failed - deployment should not proceed"
        return 1
    elif [ $error_count -gt 0 ]; then
        log_warning "Some images failed verification but no critical errors"
        return 0
    else
        log_success "All image verification passed"
        return 0
    fi
}

# Function to pre-pull all critical images
preload_critical_images() {
    log "Pre-loading critical images..."
    
    if [ ! -f "$RESOLVED_TAGS_FILE" ]; then
        log_error "Resolved tags file not found: $RESOLVED_TAGS_FILE"
        return 1
    fi
    
    # Critical images that should be pre-pulled
    local critical_patterns=(
        "postgres"
        "redis"
        "nginx"
        "caddy"
        "rtpi-pen"
    )
    
    local preload_count=0
    local preload_success=0
    local preload_failed=0
    
    # Read resolved tags and preload critical ones
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$(echo "$line" | xargs)" ]] && continue
        
        # Parse resolved tag line: VAR_NAME=image:tag
        if [[ "$line" =~ ^([^=]+)=(.+)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local full_image_name="${BASH_REMATCH[2]}"
            
            # Check if this is a critical image
            local is_critical=false
            for critical_pattern in "${critical_patterns[@]}"; do
                if [[ "$full_image_name" == *"$critical_pattern"* ]]; then
                    is_critical=true
                    break
                fi
            done
            
            if [ "$is_critical" = "true" ]; then
                ((preload_count++))
                
                if ! check_local_image "$full_image_name"; then
                    if pull_image_with_retry "$full_image_name"; then
                        ((preload_success++))
                    else
                        ((preload_failed++))
                    fi
                else
                    log "Image $full_image_name already available locally"
                    ((preload_success++))
                fi
            fi
        fi
    done < "$RESOLVED_TAGS_FILE"
    
    log_success "Critical image preload completed: $preload_success/$preload_count successful"
    
    if [ $preload_failed -gt 0 ]; then
        log_warning "$preload_failed critical images failed to preload"
        return 1
    else
        return 0
    fi
}

# Function to clean up failed or outdated images
cleanup_images() {
    log "Cleaning up Docker images..."
    
    # Remove dangling images
    local dangling=$(docker images -f "dangling=true" -q)
    if [ -n "$dangling" ]; then
        log "Removing dangling images..."
        docker rmi $dangling || true
        log_success "Removed dangling images"
    else
        log "No dangling images to remove"
    fi
    
    # Remove unused images older than 7 days
    log "Removing unused images older than 7 days..."
    docker image prune -a -f --filter "until=168h" || true
    log_success "Image cleanup completed"
}

# Function to show help
show_help() {
    echo "RTPI-PEN Image Checker"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  verify          Verify all resolved images (default)"
    echo "  pull            Verify and pull missing images"
    echo "  preload         Pre-load critical images"
    echo "  cleanup         Clean up unused images"
    echo "  check IMAGE     Check a specific image"
    echo "  help            Show this help message"
    echo ""
    echo "Options:"
    echo "  --no-fail       Don't fail on critical image errors"
    echo "  --pull          Pull missing images during verification"
    echo ""
    echo "Examples:"
    echo "  $0 verify                     # Verify all images"
    echo "  $0 pull                       # Verify and pull missing"
    echo "  $0 preload                    # Pre-load critical images"
    echo "  $0 check nginx:latest         # Check specific image"
    echo "  $0 verify --no-fail           # Verify but don't fail"
}

# Main function
main() {
    local command="${1:-verify}"
    local pull_if_missing=false
    local fail_on_critical=true
    
    # Parse options
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --pull)
                pull_if_missing=true
                shift
                ;;
            --no-fail)
                fail_on_critical=false
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Check Docker availability first
    if ! check_docker; then
        exit 1
    fi
    
    case "$command" in
        verify)
            verify_all_images "$pull_if_missing" "$fail_on_critical"
            ;;
        pull)
            verify_all_images true "$fail_on_critical"
            ;;
        preload)
            preload_critical_images
            ;;
        cleanup)
            cleanup_images
            ;;
        check)
            if [ -z "$2" ]; then
                log_error "Image name required for check command"
                show_help
                exit 1
            fi
            verify_single_image "$2" false false
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
