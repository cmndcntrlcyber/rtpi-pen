#!/bin/bash

# RTPI-PEN All-in-One Container Build Script
# This script builds and optionally runs the consolidated single-image container

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="cmndcntrl/rtpi-pen:all-in-one"
CONTAINER_NAME="rtpi-pen-all-in-one"
COMPOSE_FILE="docker-compose-single.yml"

echo -e "${BLUE}🔴 RTPI-PEN All-in-One Container Builder${NC}"
echo -e "${BLUE}======================================${NC}"

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

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if docker compose is available
if ! docker compose version >/dev/null 2>&1; then
    print_error "Docker Compose (v2) is not available. Please install Docker with Compose v2 and try again."
    exit 1
fi

# Function to build the image
build_image() {
    print_status "Building RTPI-PEN all-in-one Docker image..."
    print_status "This may take 15-30 minutes depending on your internet connection..."
    
    if docker compose -f ${COMPOSE_FILE} build --no-cache; then
        print_status "✅ Build completed successfully!"
        
        # Show image size
        IMAGE_SIZE=$(docker images ${IMAGE_NAME} --format "{{.Size}}" | head -1)
        print_status "📦 Image size: ${IMAGE_SIZE}"
        
        return 0
    else
        print_error "❌ Build failed!"
        return 1
    fi
}

# Function to run the container
run_container() {
    print_status "Starting RTPI-PEN all-in-one container..."
    
    # Stop existing container if running
    if docker ps -q -f name=${CONTAINER_NAME} | grep -q .; then
        print_warning "Stopping existing container..."
        docker stop ${CONTAINER_NAME} >/dev/null 2>&1 || true
    fi
    
    # Remove existing container if exists
    if docker ps -aq -f name=${CONTAINER_NAME} | grep -q .; then
        print_warning "Removing existing container..."
        docker rm ${CONTAINER_NAME} >/dev/null 2>&1 || true
    fi
    
    # Start new container
    if docker compose -f ${COMPOSE_FILE} up -d; then
        print_status "✅ Container started successfully!"
        print_status "🌐 Main dashboard will be available at: https://localhost"
        print_status "⏳ Please wait 1-2 minutes for all services to start..."
        
        # Show access URLs
        echo ""
        echo -e "${BLUE}📡 Service Access URLs:${NC}"
        echo -e "  • Main Dashboard: ${GREEN}https://localhost${NC}"
        echo -e "  • Portainer:      ${GREEN}https://localhost/portainer/${NC} or ${GREEN}http://localhost:9000${NC}"
        echo -e "  • Empire C2:      ${GREEN}https://localhost/empire/${NC} or ${GREEN}http://localhost:1337${NC}"
        echo -e "  • SysReptor:      ${GREEN}https://localhost/sysreptor/${NC} or ${GREEN}http://localhost:8000${NC}"
        echo -e "  • Kasm:           ${GREEN}https://localhost/kasm/${NC} or ${GREEN}https://localhost:8443${NC}"
        
        return 0
    else
        print_error "❌ Failed to start container!"
        return 1
    fi
}

# Function to show logs
show_logs() {
    print_status "Showing container logs (Ctrl+C to exit)..."
    docker compose -f ${COMPOSE_FILE} logs -f
}

# Function to show status
show_status() {
    print_status "Container Status:"
    docker ps -f name=${CONTAINER_NAME} --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    print_status "Service Status:"
    if docker ps -q -f name=${CONTAINER_NAME} | grep -q .; then
        docker exec ${CONTAINER_NAME} supervisorctl status 2>/dev/null || print_warning "Container is starting, services not ready yet..."
    else
        print_warning "Container is not running"
    fi
}

# Function to enter container shell
enter_shell() {
    if docker ps -q -f name=${CONTAINER_NAME} | grep -q .; then
        print_status "Entering container shell..."
        docker exec -it ${CONTAINER_NAME} /bin/bash
    else
        print_error "Container is not running. Start it first with: $0 run"
    fi
}

# Function to stop container
stop_container() {
    print_status "Stopping RTPI-PEN container..."
    docker compose -f ${COMPOSE_FILE} down
    print_status "✅ Container stopped"
}

# Function to clean up
cleanup() {
    print_warning "This will remove the container and image. Data in volumes will be preserved."
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Cleaning up..."
        docker compose -f ${COMPOSE_FILE} down --rmi all
        print_status "✅ Cleanup completed"
    else
        print_status "Cleanup cancelled"
    fi
}

# Function to check requirements
check_requirements() {
    print_status "Checking system requirements..."
    
    # Check available memory
    AVAILABLE_MEM=$(free -g | awk '/^Mem:/{print $7}')
    if [ ${AVAILABLE_MEM} -lt 4 ]; then
        print_warning "Available memory (${AVAILABLE_MEM}GB) is less than recommended 4GB"
    else
        print_status "✅ Memory: ${AVAILABLE_MEM}GB available"
    fi
    
    # Check available disk space
    AVAILABLE_DISK=$(df -BG . | awk 'NR==2{print $4}' | sed 's/G//')
    if [ ${AVAILABLE_DISK} -lt 10 ]; then
        print_warning "Available disk space (${AVAILABLE_DISK}GB) is less than recommended 10GB"
    else
        print_status "✅ Disk: ${AVAILABLE_DISK}GB available"
    fi
    
    # Check if ports are in use
    PORTS=(80 443 1337 5000 8000 8443 9000)
    for port in "${PORTS[@]}"; do
        if netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
            print_warning "Port ${port} is already in use"
        fi
    done
}

# Main menu
show_menu() {
    echo ""
    echo -e "${BLUE}Available commands:${NC}"
    echo "  build    - Build the all-in-one Docker image"
    echo "  run      - Start the container"
    echo "  stop     - Stop the container"
    echo "  logs     - Show container logs"
    echo "  status   - Show container and service status"
    echo "  shell    - Enter container shell"
    echo "  check    - Check system requirements"
    echo "  cleanup  - Remove container and image"
    echo "  help     - Show this help menu"
}

# Parse command line arguments
case "${1:-help}" in
    build)
        check_requirements
        build_image
        ;;
    run)
        run_container
        ;;
    start)
        run_container
        ;;
    stop)
        stop_container
        ;;
    logs)
        show_logs
        ;;
    status)
        show_status
        ;;
    shell)
        enter_shell
        ;;
    check)
        check_requirements
        ;;
    cleanup)
        cleanup
        ;;
    help|*)
        show_menu
        echo ""
        echo -e "${YELLOW}Example usage:${NC}"
        echo "  $0 build    # Build the image"
        echo "  $0 run      # Start the container"
        echo "  $0 status   # Check status"
        ;;
esac
