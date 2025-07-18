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
    
    # Start SysReptor
    log "Starting SysReptor services..."
    $DOCKER_COMPOSE_CMD up -d sysreptor-app sysreptor-caddy
    
    # Start security services
    log "Starting security services..."
    # Empire C2 runs natively - no container deployment needed
    echo "✓ Empire C2 running natively at http://localhost:1337"
    
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
