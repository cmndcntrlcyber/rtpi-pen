#!/bin/bash
set -e

# RTPI-PEN Container Management Utilities
# Provides batch container operations and management functions

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/rtpi/container-manager.log"
COMPOSE_FILE="/opt/rtpi-pen/docker-compose.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message
success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
    log "SUCCESS: $1"
}

# Warning message
warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
    log "WARNING: $1"
}

# Info message
info() {
    echo -e "${BLUE}INFO: $1${NC}"
    log "INFO: $1"
}

# Check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        error_exit "Docker is not installed or not in PATH"
    fi
    
    if ! docker info &> /dev/null; then
        error_exit "Docker daemon is not running or not accessible"
    fi
}

# Get service startup order
get_startup_order() {
    echo "rtpi-database rtpi-cache sysreptor-db rtpi-healer rtpi-proxy rtpi-tools sysreptor-app"
}

# Get service shutdown order (reverse of startup)
get_shutdown_order() {
    echo "sysreptor-app rtpi-tools rtpi-proxy rtpi-healer sysreptor-db rtpi-cache rtpi-database"
}

# Check if container exists
container_exists() {
    local container_name="$1"
    docker ps -a --format "table {{.Names}}" | grep -q "^${container_name}$"
}

# Check if container is running
container_running() {
    local container_name="$1"
    docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"
}

# Get container status
get_container_status() {
    local container_name="$1"
    
    if ! container_exists "$container_name"; then
        echo "not_found"
        return
    fi
    
    docker inspect "$container_name" --format "{{.State.Status}}"
}

# Get container health status
get_container_health() {
    local container_name="$1"
    
    if ! container_exists "$container_name"; then
        echo "not_found"
        return
    fi
    
    local health_status
    health_status=$(docker inspect "$container_name" --format "{{.State.Health.Status}}" 2>/dev/null || echo "no_healthcheck")
    
    if [[ "$health_status" == "<no value>" ]]; then
        echo "no_healthcheck"
    else
        echo "$health_status"
    fi
}

# Wait for container to be ready
wait_for_container() {
    local container_name="$1"
    local max_wait="${2:-60}"
    local counter=0
    
    info "Waiting for container $container_name to be ready..."
    
    while [[ $counter -lt $max_wait ]]; do
        if container_running "$container_name"; then
            local health_status
            health_status=$(get_container_health "$container_name")
            
            if [[ "$health_status" == "healthy" ]] || [[ "$health_status" == "no_healthcheck" ]]; then
                success "Container $container_name is ready"
                return 0
            fi
        fi
        
        sleep 2
        counter=$((counter + 2))
    done
    
    warning "Container $container_name did not become ready within $max_wait seconds"
    return 1
}

# Start a single container
start_container() {
    local container_name="$1"
    local wait_ready="${2:-true}"
    
    if ! container_exists "$container_name"; then
        warning "Container $container_name does not exist"
        return 1
    fi
    
    if container_running "$container_name"; then
        info "Container $container_name is already running"
        return 0
    fi
    
    info "Starting container: $container_name"
    
    if docker start "$container_name"; then
        success "Started container: $container_name"
        
        if [[ "$wait_ready" == "true" ]]; then
            wait_for_container "$container_name"
        fi
        
        return 0
    else
        error_exit "Failed to start container: $container_name"
    fi
}

# Stop a single container
stop_container() {
    local container_name="$1"
    local timeout="${2:-30}"
    
    if ! container_exists "$container_name"; then
        warning "Container $container_name does not exist"
        return 1
    fi
    
    if ! container_running "$container_name"; then
        info "Container $container_name is already stopped"
        return 0
    fi
    
    info "Stopping container: $container_name"
    
    if docker stop --time="$timeout" "$container_name"; then
        success "Stopped container: $container_name"
        return 0
    else
        warning "Failed to stop container gracefully: $container_name"
        info "Force killing container: $container_name"
        docker kill "$container_name"
        return 1
    fi
}

# Restart a single container
restart_container() {
    local container_name="$1"
    local wait_ready="${2:-true}"
    
    info "Restarting container: $container_name"
    
    if container_running "$container_name"; then
        stop_container "$container_name"
    fi
    
    start_container "$container_name" "$wait_ready"
}

# Start all services in dependency order
start_all_services() {
    info "Starting all RTPI-PEN services..."
    
    for service in $(get_startup_order); do
        if container_exists "$service"; then
            start_container "$service" true
            sleep 5  # Brief pause between service starts
        else
            warning "Service $service does not exist, skipping"
        fi
    done
    
    success "All services started"
}

# Stop all services in reverse dependency order
stop_all_services() {
    info "Stopping all RTPI-PEN services..."
    
    for service in $(get_shutdown_order); do
        if container_exists "$service"; then
            stop_container "$service"
        else
            warning "Service $service does not exist, skipping"
        fi
    done
    
    success "All services stopped"
}

# Restart all services
restart_all_services() {
    info "Restarting all RTPI-PEN services..."
    stop_all_services
    sleep 10  # Allow time for cleanup
    start_all_services
}

# Show status of all containers
show_status() {
    info "RTPI-PEN Container Status:"
    echo
    printf "%-20s %-15s %-15s %-20s\n" "SERVICE" "STATUS" "HEALTH" "RESTART COUNT"
    echo "────────────────────────────────────────────────────────────────────"
    
    for service in $(get_startup_order); do
        if container_exists "$service"; then
            local status health restart_count
            status=$(get_container_status "$service")
            health=$(get_container_health "$service")
            restart_count=$(docker inspect "$service" --format "{{.RestartCount}}" 2>/dev/null || echo "0")
            
            printf "%-20s %-15s %-15s %-20s\n" "$service" "$status" "$health" "$restart_count"
        else
            printf "%-20s %-15s %-15s %-20s\n" "$service" "not_found" "not_found" "0"
        fi
    done
    echo
}

# Get container logs
get_logs() {
    local container_name="$1"
    local lines="${2:-50}"
    local follow="${3:-false}"
    
    if ! container_exists "$container_name"; then
        error_exit "Container $container_name does not exist"
    fi
    
    info "Showing logs for container: $container_name"
    
    if [[ "$follow" == "true" ]]; then
        docker logs -f --tail="$lines" "$container_name"
    else
        docker logs --tail="$lines" "$container_name"
    fi
}

# Clean up stopped containers
cleanup_containers() {
    info "Cleaning up stopped containers..."
    
    local stopped_containers
    stopped_containers=$(docker ps -a --filter "status=exited" --format "{{.Names}}")
    
    if [[ -z "$stopped_containers" ]]; then
        info "No stopped containers to clean up"
        return 0
    fi
    
    for container in $stopped_containers; do
        # Only clean up RTPI-PEN containers
        if [[ "$container" == rtpi-* ]] || [[ "$container" == sysreptor-* ]]; then
            info "Removing stopped container: $container"
            docker rm "$container"
        fi
    done
    
    success "Container cleanup completed"
}

# Monitor container resources
monitor_resources() {
    local container_name="$1"
    local duration="${2:-60}"
    
    if ! container_exists "$container_name"; then
        error_exit "Container $container_name does not exist"
    fi
    
    if ! container_running "$container_name"; then
        error_exit "Container $container_name is not running"
    fi
    
    info "Monitoring resources for container: $container_name for $duration seconds"
    
    docker stats --no-stream "$container_name" &
    local stats_pid=$!
    
    sleep "$duration"
    
    kill $stats_pid 2>/dev/null || true
    
    success "Resource monitoring completed"
}

# Update container images
update_images() {
    info "Updating container images..."
    
    # Get list of images used by our containers
    local images
    images=$(docker ps -a --format "table {{.Image}}" | grep -v "IMAGE" | sort -u)
    
    for image in $images; do
        # Skip local images
        if [[ "$image" == *"rtpi-"* ]]; then
            continue
        fi
        
        info "Pulling updated image: $image"
        docker pull "$image" || warning "Failed to pull image: $image"
    done
    
    success "Image update completed"
}

# Backup container volumes
backup_volumes() {
    local backup_dir="/data/backups/volumes"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    mkdir -p "$backup_dir"
    
    info "Backing up container volumes..."
    
    # Get list of volumes used by our containers
    local volumes
    volumes=$(docker volume ls --format "{{.Name}}" | grep -E "(rtpi|sysreptor)")
    
    for volume in $volumes; do
        local backup_file="$backup_dir/${volume}_${timestamp}.tar.gz"
        
        info "Backing up volume: $volume"
        docker run --rm \
            -v "$volume:/backup-source:ro" \
            -v "$backup_dir:/backup-dest" \
            alpine:latest \
            tar czf "/backup-dest/${volume}_${timestamp}.tar.gz" -C /backup-source .
        
        if [[ -f "$backup_file" ]]; then
            success "Volume backup created: $backup_file"
        else
            warning "Failed to create volume backup: $volume"
        fi
    done
    
    success "Volume backup completed"
}

# Show help
show_help() {
    cat << EOF
RTPI-PEN Container Management Utilities

Usage: $0 <command> [options]

Commands:
    start <service>         Start a specific service
    stop <service>          Stop a specific service
    restart <service>       Restart a specific service
    start-all              Start all services in dependency order
    stop-all               Stop all services in reverse dependency order
    restart-all            Restart all services
    status                 Show status of all containers
    logs <service> [lines] Show logs for a service
    follow <service>       Follow logs for a service
    cleanup                Remove stopped containers
    monitor <service>      Monitor resource usage for a service
    update-images          Update container images
    backup-volumes         Backup container volumes
    help                   Show this help message

Examples:
    $0 start rtpi-database
    $0 logs rtpi-proxy 100
    $0 monitor rtpi-healer
    $0 restart-all

EOF
}

# Main command handler
main() {
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Check Docker availability
    check_docker
    
    case "${1:-}" in
        start)
            if [[ -z "${2:-}" ]]; then
                error_exit "Service name required for start command"
            fi
            start_container "$2"
            ;;
        stop)
            if [[ -z "${2:-}" ]]; then
                error_exit "Service name required for stop command"
            fi
            stop_container "$2"
            ;;
        restart)
            if [[ -z "${2:-}" ]]; then
                error_exit "Service name required for restart command"
            fi
            restart_container "$2"
            ;;
        start-all)
            start_all_services
            ;;
        stop-all)
            stop_all_services
            ;;
        restart-all)
            restart_all_services
            ;;
        status)
            show_status
            ;;
        logs)
            if [[ -z "${2:-}" ]]; then
                error_exit "Service name required for logs command"
            fi
            get_logs "$2" "${3:-50}"
            ;;
        follow)
            if [[ -z "${2:-}" ]]; then
                error_exit "Service name required for follow command"
            fi
            get_logs "$2" "50" "true"
            ;;
        cleanup)
            cleanup_containers
            ;;
        monitor)
            if [[ -z "${2:-}" ]]; then
                error_exit "Service name required for monitor command"
            fi
            monitor_resources "$2" "${3:-60}"
            ;;
        update-images)
            update_images
            ;;
        backup-volumes)
            backup_volumes
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error_exit "Unknown command: ${1:-}. Use 'help' for usage information."
            ;;
    esac
}

# Run main function with all arguments
main "$@"
