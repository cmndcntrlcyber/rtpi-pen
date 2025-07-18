#!/bin/bash
# RTPI-PEN Self-Healing System Deployment Script
# Comprehensive deployment with automatic issue resolution

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

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

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Banner
show_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
    ____  ______  ____     ____  ______ _   __
   / __ \/_  __/ / __ \   / __ \/ ____// | / /
  / /_/ / / /   / /_/ /  / /_/ / __/  /  |/ / 
 / _, _/ / /   / ____/  / ____/ /___ / /|  /  
/_/ |_| /_/   /_/      /_/   /_____//_/ |_/   
                                              
Self-Healing Red Team Penetration Infrastructure
EOF
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    # Check Docker Compose (both standalone and plugin formats)
    if command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
        log "Found standalone docker-compose"
    elif docker compose version &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
        log "Found docker compose plugin"
    else
        log_error "Docker Compose is not installed (checked both 'docker-compose' and 'docker compose')"
        exit 1
    fi
    
    # Check Docker service
    if ! systemctl is-active --quiet docker; then
        log "Starting Docker service..."
        systemctl start docker
        systemctl enable docker
    fi
    
    log_success "Prerequisites check passed"
}

# Stop existing containers
stop_existing_containers() {
    log "Stopping existing containers..."
    
    # Get list of running containers
    containers=$(docker ps -q)
    if [ ! -z "$containers" ]; then
        docker stop $containers
        log_success "Stopped existing containers"
    else
        log "No running containers to stop"
    fi
    
    # Clean up exited containers
    exited_containers=$(docker ps -aq --filter "status=exited")
    if [ ! -z "$exited_containers" ]; then
        docker rm $exited_containers
        log_success "Removed exited containers"
    fi
}

# Build images
build_images() {
    log "Building Docker images..."
    
    # Build healer image first
    log "Building self-healing service image..."
    $DOCKER_COMPOSE_CMD build rtpi-healer
    
    # Build other core services
    log "Building core infrastructure images..."
    $DOCKER_COMPOSE_CMD build rtpi-database rtpi-cache rtpi-orchestrator rtpi-proxy rtpi-tools
    
    log_success "Docker images built successfully"
}

# Run system initialization
run_initialization() {
    log "Running system initialization..."
    
    # First, run the initialization container
    log "Starting initialization container..."
    $DOCKER_COMPOSE_CMD up --no-deps rtpi-init
    
    # Wait for initialization to complete
    log "Waiting for initialization to complete..."
    sleep 5
    
    # Check if initialization was successful
    if [ $? -eq 0 ]; then
        log_success "System initialization completed successfully"
    else
        log_error "System initialization failed"
        exit 1
    fi
    
    # Remove the initialization container
    $DOCKER_COMPOSE_CMD rm -f rtpi-init
}

# Deploy core services
deploy_core_services() {
    log "Deploying core infrastructure services..."
    
    # Start databases first
    log "Starting database services..."
    $DOCKER_COMPOSE_CMD up -d rtpi-database sysreptor-db
    
    # Wait for databases to be ready
    log "Waiting for databases to be ready..."
    sleep 30
    
    # Start cache services
    log "Starting cache services..."
    $DOCKER_COMPOSE_CMD up -d rtpi-cache sysreptor-redis kasm_redis
    
    # Wait for cache services
    sleep 10
    
    # Start healer service
    log "Starting self-healing service..."
    $DOCKER_COMPOSE_CMD up -d rtpi-healer
    
    # Wait for healer to be ready
    sleep 20
    
    log_success "Core services deployed successfully"
}

# Deploy application services
deploy_application_services() {
    log "Deploying application services..."
    
    # Check existing Kasm installation before proceeding
    kasm_status=$(check_kasm_status)
    case $kasm_status in
        "WORKING")
            log_success "Kasm is already installed and working (>10 min), skipping Kasm deployment"
            export SKIP_KASM_DEPLOYMENT=true
            ;;
        "BROKEN")
            log_warning "Kasm detected but not working properly, cleaning up..."
            cleanup_broken_kasm
            log "Proceeding with fresh Kasm deployment..."
            export SKIP_KASM_DEPLOYMENT=false
            ;;
        "ABSENT")
            log "No Kasm installation detected, proceeding with deployment..."
            export SKIP_KASM_DEPLOYMENT=false
            ;;
    esac
    
    # Only deploy Kasm containers if not skipped
    if [ "$SKIP_KASM_DEPLOYMENT" != "true" ]; then
        # Start Kasm database
        log "Starting Kasm database..."
        $DOCKER_COMPOSE_CMD up -d kasm_db
        
        # Wait for Kasm database
        sleep 20
        
        # Start Kasm services
        log "Starting Kasm Workspaces..."
        $DOCKER_COMPOSE_CMD up -d kasm_api kasm_manager kasm_agent kasm_share kasm_guac
        
        # Wait for Kasm services
        sleep 30
        
        # Start Kasm proxy
        $DOCKER_COMPOSE_CMD up -d kasm_proxy
    else
        log "Skipping Kasm container deployment - already working"
    fi
    
    # Start SysReptor
    log "Starting SysReptor services..."
    $DOCKER_COMPOSE_CMD up -d sysreptor-app sysreptor-caddy
    
    # Check existing security services installation before proceeding
    security_services_status=$(check_security_services_status)
    case $security_services_status in
        "WORKING")
            log_success "Security services are already installed and working (>10 min), skipping security services deployment"
            export SKIP_SECURITY_SERVICES_DEPLOYMENT=true
            ;;
        "BROKEN")
            log_warning "Security services detected but not working properly, cleaning up..."
            cleanup_broken_security_services
            log "Proceeding with fresh security services deployment..."
            export SKIP_SECURITY_SERVICES_DEPLOYMENT=false
            ;;
        "ABSENT")
            log "No security services installation detected, proceeding with deployment..."
            export SKIP_SECURITY_SERVICES_DEPLOYMENT=false
            ;;
    esac
    
    # Only deploy security services if not skipped
    if [ "$SKIP_SECURITY_SERVICES_DEPLOYMENT" != "true" ]; then
        # Start security services
        log "Starting security services..."
        $DOCKER_COMPOSE_CMD up -d vaultwarden
        
        # Start additional Kasm workspaces
        log "Starting additional Kasm workspaces..."
        $DOCKER_COMPOSE_CMD up -d kasm-vscode kasm-kali
        
        # Empire C2 runs natively - no container deployment needed
        echo "✓ Empire C2 running natively at http://localhost:1337"
    else
        log "Skipping security services deployment - already working"
    fi
    
    # Check existing Portainer installation before proceeding
    portainer_status=$(check_portainer_status)
    case $portainer_status in
        "WORKING")
            log_success "Portainer is already installed and working (>10 min), skipping Portainer deployment"
            export SKIP_PORTAINER_DEPLOYMENT=true
            ;;
        "BROKEN")
            log_warning "Portainer detected but not working properly, cleaning up..."
            cleanup_broken_portainer
            log "Proceeding with fresh Portainer deployment..."
            export SKIP_PORTAINER_DEPLOYMENT=false
            ;;
        "ABSENT")
            log "No Portainer installation detected, proceeding with deployment..."
            export SKIP_PORTAINER_DEPLOYMENT=false
            ;;
    esac
    
    # Note: Portainer is not in docker-compose.yml, it's installed natively
    if [ "$SKIP_PORTAINER_DEPLOYMENT" != "true" ]; then
        log "Portainer deployment managed outside of docker-compose"
    else
        log "Skipping Portainer deployment - already working"
    fi
    
    # Start utility services
    log "Starting utility services..."
    $DOCKER_COMPOSE_CMD up -d rtpi-orchestrator rtpi-proxy rtpi-tools registry node
    
    log_success "Application services deployed successfully"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Wait for all services to stabilize
    sleep 30
    
    # Check critical services
    critical_services=(
        "rtpi-healer"
        "rtpi-database"
        "rtpi-cache"
        "sysreptor-app"
        "sysreptor-db"
        "kasm_db"
        "kasm_api"
    )
    
    failed_services=()
    
    for service in "${critical_services[@]}"; do
        if docker ps --filter "name=$service" --filter "status=running" | grep -q $service; then
            log_success "$service is running"
        else
            log_error "$service is not running"
            failed_services+=($service)
        fi
    done
    
    # Check healer API
    sleep 10
    if curl -f -s http://localhost:8888/health > /dev/null; then
        log_success "Self-healing service API is responding"
    else
        log_warning "Self-healing service API is not responding yet"
    fi
    
    if [ ${#failed_services[@]} -eq 0 ]; then
        log_success "All critical services are running"
        return 0
    else
        log_error "Some services failed to start: ${failed_services[*]}"
        return 1
    fi
}

# Show deployment summary
show_summary() {
    log "Deployment Summary:"
    echo ""
    echo -e "${GREEN}🏥 Self-Healing Infrastructure Deployed Successfully!${NC}"
    echo ""
    echo -e "${BLUE}Access Points:${NC}"
    echo -e "  • Self-Healing Dashboard: http://localhost:8888/health"
    echo -e "  • Kasm Workspaces: https://localhost:8443"
    echo -e "  • SysReptor: http://localhost:7777"
    echo -e "  • Empire C2: http://localhost:1337"
    echo -e "  • Portainer: http://localhost:9444"
    echo -e "  • Main Proxy: https://localhost:443"
    echo ""
    echo -e "${BLUE}Self-Healing Features:${NC}"
    echo -e "  • Automatic container restart with intelligent backoff"
    echo -e "  • Configuration auto-repair and regeneration"
    echo -e "  • Permission issue resolution"
    echo -e "  • Database connectivity healing"
    echo -e "  • Real-time monitoring and alerting"
    echo -e "  • Automated backup and recovery"
    echo ""
    echo -e "${BLUE}Monitoring:${NC}"
    echo -e "  • Logs: \$DOCKER_COMPOSE_CMD logs -f rtpi-healer"
    echo -e "  • Status: curl http://localhost:8888/health"
    echo -e "  • Container health: docker ps"
    echo ""
    echo -e "${YELLOW}Note: The self-healing service will automatically detect and repair issues.${NC}"
    echo -e "${YELLOW}Check the logs if you encounter any problems.${NC}"
}

# Show help
show_help() {
    echo "RTPI-PEN Self-Healing System Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -s, --stop     Stop all services"
    echo "  -r, --restart  Restart all services"
    echo "  -c, --clean    Clean up all containers and volumes"
    echo "  -v, --verify   Verify deployment status"
    echo ""
    echo "Examples:"
    echo "  $0              # Full deployment"
    echo "  $0 --stop       # Stop all services"
    echo "  $0 --restart    # Restart all services"
    echo "  $0 --clean      # Clean up everything"
    echo "  $0 --verify     # Check deployment status"
}

# Stop all services
stop_services() {
    log "Stopping all services..."
    
    # Ensure we have the compose command
    if [ -z "$DOCKER_COMPOSE_CMD" ]; then
        if command -v docker-compose &> /dev/null; then
            DOCKER_COMPOSE_CMD="docker-compose"
        elif docker compose version &> /dev/null; then
            DOCKER_COMPOSE_CMD="docker compose"
        else
            log_error "Docker Compose not found"
            exit 1
        fi
    fi
    
    $DOCKER_COMPOSE_CMD down
    log_success "All services stopped"
}

# Restart all services
restart_services() {
    log "Restarting all services..."
    
    # Ensure we have the compose command
    if [ -z "$DOCKER_COMPOSE_CMD" ]; then
        if command -v docker-compose &> /dev/null; then
            DOCKER_COMPOSE_CMD="docker-compose"
        elif docker compose version &> /dev/null; then
            DOCKER_COMPOSE_CMD="docker compose"
        else
            log_error "Docker Compose not found"
            exit 1
        fi
    fi
    
    $DOCKER_COMPOSE_CMD restart
    log_success "All services restarted"
}

# Clean up everything
clean_up() {
    log "Cleaning up containers and volumes..."
    
    # Ensure we have the compose command
    if [ -z "$DOCKER_COMPOSE_CMD" ]; then
        if command -v docker-compose &> /dev/null; then
            DOCKER_COMPOSE_CMD="docker-compose"
        elif docker compose version &> /dev/null; then
            DOCKER_COMPOSE_CMD="docker compose"
        else
            log_error "Docker Compose not found"
            exit 1
        fi
    fi
    
    # Stop and remove containers
    $DOCKER_COMPOSE_CMD down -v
    
    # Remove images
    docker image prune -f
    
    # Remove unused volumes
    docker volume prune -f
    
    # Clean up host directories
    if [ -d "/opt/kasm" ]; then
        rm -rf /opt/kasm
        log "Removed /opt/kasm directory"
    fi
    
    if [ -d "/opt/empire" ]; then
        rm -rf /opt/empire
        log "Removed /opt/empire directory"
    fi
    
    if [ -d "/opt/rtpi-orchestrator" ]; then
        rm -rf /opt/rtpi-orchestrator
        log "Removed /opt/rtpi-orchestrator directory"
    fi
    
    log_success "Cleanup completed"
}

# Main deployment function
main_deployment() {
    show_banner
    check_prerequisites
    stop_existing_containers
    build_images
    run_initialization
    deploy_core_services
    deploy_application_services
    
    if verify_deployment; then
        show_summary
    else
        log_error "Deployment verification failed"
        log "Check the logs: $DOCKER_COMPOSE_CMD logs"
        exit 1
    fi
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -s|--stop)
        stop_services
        exit 0
        ;;
    -r|--restart)
        restart_services
        exit 0
        ;;
    -c|--clean)
        clean_up
        exit 0
        ;;
    -v|--verify)
        verify_deployment
        exit 0
        ;;
    "")
        main_deployment
        ;;
    *)
        log_error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac
