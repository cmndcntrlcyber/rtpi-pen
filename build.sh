#!/bin/bash

# RTPI-PEN Multi-Container Build Script
# This script builds and manages the decomposed microservices architecture

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.yml"
PROJECT_NAME="rtpi-pen"

echo -e "${BLUE}🔴 RTPI-PEN Multi-Container Platform${NC}"
echo -e "${BLUE}====================================${NC}"

# Function to print status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo -e "${PURPLE}[SECTION]${NC} $1"
}

# Check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    if ! docker compose version >/dev/null 2>&1; then
        print_error "Docker Compose (v2) is not available. Please install Docker with Compose v2."
        exit 1
    fi
    
    print_status "✅ Docker and Docker Compose are available"
}

# Check system requirements
check_requirements() {
    print_section "Checking system requirements..."
    
    # Check available memory
    if command -v free >/dev/null 2>&1; then
        AVAILABLE_MEM=$(free -g | awk '/^Mem:/{print $7}')
        if [ ${AVAILABLE_MEM} -lt 6 ]; then
            print_warning "Available memory (${AVAILABLE_MEM}GB) is less than recommended 6GB for multi-container setup"
        else
            print_status "✅ Memory: ${AVAILABLE_MEM}GB available"
        fi
    fi
    
    # Check available disk space
    AVAILABLE_DISK=$(df -BG . | awk 'NR==2{print $4}' | sed 's/G//')
    if [ ${AVAILABLE_DISK} -lt 15 ]; then
        print_warning "Available disk space (${AVAILABLE_DISK}GB) is less than recommended 15GB"
    else
        print_status "✅ Disk: ${AVAILABLE_DISK}GB available"
    fi
    
    # Check if critical ports are in use
    PORTS=(80 443 1337 5000 8443 9000 9444)
    for port in "${PORTS[@]}"; do
        if netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
            print_warning "Port ${port} is already in use"
        fi
    done
}

# Build all services
build_services() {
    print_section "Building RTPI-PEN microservices..."
    print_status "This may take 20-40 minutes depending on your system..."
    
    # Build core infrastructure services first
    print_status "🗄️ Building database service..."
    docker compose build rtpi-database
    
    print_status "⚡ Building cache service..."
    docker compose build rtpi-cache
    
    print_status "🔧 Building tools service..."
    docker compose build rtpi-tools
    
    print_status "🌐 Building proxy service..."
    docker compose build rtpi-proxy
    
    print_status "🐳 Building orchestrator service..."
    docker compose build rtpi-orchestrator
    
    # Build all remaining services
    print_status "📦 Building remaining services..."
    docker compose build
    
    print_status "✅ All services built successfully!"
    
    # Show image sizes
    echo ""
    print_section "Built Images:"
    docker images | grep -E "(rtpi-pen|REPOSITORY)" | head -10
}

# Start all services
start_services() {
    print_section "Starting RTPI-PEN platform..."
    
    # Create environment file if it doesn't exist
    if [ ! -f .env ]; then
        create_env_file
    fi
    
    # Start core services first
    print_status "🚀 Starting core infrastructure..."
    docker compose up -d rtpi-database rtpi-cache
    
    # Wait for database to be ready
    print_status "⏳ Waiting for database to be ready..."
    sleep 10
    
    # Start application services
    print_status "🚀 Starting application services..."
    docker compose up -d rtpi-orchestrator rtpi-proxy
    
    # Start remaining services
    print_status "🚀 Starting all remaining services..."
    docker compose up -d
    
    print_status "✅ All services started!"
    
    # Show service status
    show_status
    
    # Show access information
    show_access_info
}

# Create environment file
create_env_file() {
    print_status "Creating environment configuration..."
    cat > .env << 'EOF'
# RTPI-PEN Environment Configuration
COMPOSE_PROJECT_NAME=rtpi-pen

# Kasm Configuration
KASM_VERSION=1.15.0
KASM_UID=1000
KASM_GID=1000
POSTGRES_VERSION_KASM=12-alpine
POSTGRES_USER_KASM=kasmapp
POSTGRES_PASSWORD_KASM=SjenXuTppFFSWIIKjaAJ
POSTGRES_DB_KASM=kasm
REDIS_KASM_VERSION=5-alpine
NGINX_VERSION=1.25.3

# Database Configuration
POSTGRES_PASSWORD=rtpi_secure_password
REDIS_PASSWORD=rtpi_redis_password

# Network Configuration
RTPI_DOMAIN=localhost
EOF
    print_status "✅ Environment file created"
}

# Show service status
show_status() {
    echo ""
    print_section "Service Status:"
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    print_section "Resource Usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" | head -10
}

# Show access information
show_access_info() {
    echo ""
    print_section "🌐 Access Information:"
    echo -e "  ${GREEN}Main Dashboard:${NC}     https://localhost"
    echo -e "  ${GREEN}Portainer:${NC}          https://localhost/portainer/ or http://localhost:9444"
    echo -e "  ${GREEN}Kasm Workspaces:${NC}    https://localhost/kasm/ or https://localhost:8443"
    echo -e "  ${GREEN}SysReptor:${NC}          https://localhost/sysreptor/ or http://localhost:9000"
    echo -e "  ${GREEN}Empire C2:${NC}          https://localhost/empire/ or http://localhost:1337"
    echo -e "  ${GREEN}Docker Registry:${NC}    http://localhost:5001"
    
    echo ""
    print_section "🔧 Management Commands:"
    echo "  View logs:      docker compose logs -f [service]"
    echo "  Scale service:  docker compose up -d --scale [service]=N"
    echo "  Shell access:   docker compose exec [service] /bin/bash"
    echo "  Restart all:    docker compose restart"
    echo "  Stop all:       docker compose down"
    
    echo ""
    print_warning "⏳ Please wait 2-3 minutes for all services to fully initialize"
}

# Show logs for all or specific service
show_logs() {
    if [ -n "$2" ]; then
        print_status "Showing logs for $2..."
        docker compose logs -f "$2"
    else
        print_status "Showing logs for all services (Ctrl+C to exit)..."
        docker compose logs -f
    fi
}

# Stop all services
stop_services() {
    print_section "Stopping RTPI-PEN platform..."
    docker compose down
    print_status "✅ All services stopped"
}

# Restart all services
restart_services() {
    print_section "Restarting RTPI-PEN platform..."
    docker compose restart
    print_status "✅ All services restarted"
    show_status
}

# Clean up everything
cleanup() {
    print_warning "This will remove all containers, images, and volumes."
    print_warning "All data will be lost permanently!"
    read -p "Are you sure? (type 'YES' to confirm): " -r
    if [[ $REPLY == "YES" ]]; then
        print_section "Cleaning up RTPI-PEN platform..."
        docker compose down -v --rmi all --remove-orphans
        docker system prune -f
        print_status "✅ Cleanup completed"
    else
        print_status "Cleanup cancelled"
    fi
}

# Shell access to specific service
shell_access() {
    if [ -n "$2" ]; then
        SERVICE="$2"
    else
        echo "Available services:"
        docker compose ps --services
        read -p "Enter service name: " SERVICE
    fi
    
    print_status "Accessing shell for $SERVICE..."
    docker compose exec "$SERVICE" /bin/bash || docker compose exec "$SERVICE" /bin/sh
}

# Update services
update_services() {
    print_section "Updating RTPI-PEN services..."
    docker compose pull
    docker compose up -d --build
    print_status "✅ Services updated"
}

# Main menu
show_menu() {
    echo ""
    echo -e "${BLUE}Available commands:${NC}"
    echo "  build      - Build all microservices"
    echo "  start      - Start all services (docker compose up -d)"
    echo "  stop       - Stop all services"
    echo "  restart    - Restart all services"
    echo "  status     - Show service status and resource usage"
    echo "  logs       - Show logs (optionally specify service name)"
    echo "  shell      - Access shell of specific service"
    echo "  update     - Update and rebuild services"
    echo "  check      - Check system requirements"
    echo "  cleanup    - Remove everything (destructive)"
    echo "  help       - Show this help menu"
}

# Parse command line arguments
case "${1:-help}" in
    build)
        check_docker
        check_requirements
        build_services
        ;;
    start|up)
        check_docker
        start_services
        ;;
    stop|down)
        stop_services
        ;;
    restart)
        restart_services
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs "$@"
        ;;
    shell)
        shell_access "$@"
        ;;
    update)
        check_docker
        update_services
        ;;
    check)
        check_docker
        check_requirements
        ;;
    cleanup)
        cleanup
        ;;
    help|*)
        show_menu
        echo ""
        echo -e "${YELLOW}Primary Usage:${NC}"
        echo "  $0 build && $0 start    # First time setup"
        echo "  $0 start                # Regular startup"
        echo "  $0 status               # Check services"
        echo ""
        echo -e "${YELLOW}Quick Start:${NC}"
        echo "  git clone <repo> && cd rtpi-pen"
        echo "  chmod +x build.sh"
        echo "  ./build.sh build        # Build all services"
        echo "  ./build.sh start        # Start platform"
        ;;
esac
