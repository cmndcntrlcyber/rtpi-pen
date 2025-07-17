#!/usr/bin/env bash
# build-kasm-first.sh — Kasm-first deployment for RTPI-PEN
# Based on inspiration method: Install Kasm Workspaces first, then deploy rest via Docker Compose

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
KASM_VERSION="1.17.0.7f020d"
KASM_LISTEN_PORT="8443"
COMPOSE_FILE="docker-compose-kasm-first.yml"
PROJECT_NAME="rtpi-pen"

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

echo -e "${BLUE}🔴 RTPI-PEN Kasm-First Deployment${NC}"
echo -e "${BLUE}=================================${NC}"

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root for Kasm installation"
        print_status "Please run: sudo $0"
        exit 1
    fi
}

# Install Docker CE with Compose v2
install_docker() {
    print_section "Installing Docker CE with Compose v2..."
    
    # Check if running on Ubuntu
    if ! command -v lsb_release >/dev/null 2>&1; then
        print_error "This script is designed for Ubuntu. Please install Docker manually on other systems."
        exit 1
    fi
    
    local ubuntu_version=$(lsb_release -cs)
    print_status "Detected Ubuntu version: $ubuntu_version"
    
    # Remove old Docker if installed from Ubuntu repo
    print_status "🗑️ Removing old Docker packages..."
    apt remove -y docker docker-engine docker.io containerd runc || true
    
    # Install prerequisites
    print_status "📦 Installing prerequisites..."
    apt update
    apt install -y ca-certificates curl gnupg lsb-release
    
    # Add Docker's official GPG key and repo
    print_status "🔑 Adding Docker's official GPG key and repository..."
    mkdir -p /usr/share/keyrings
    
    # Download and add GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) \
        signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
        https://download.docker.com/linux/ubuntu \
        $ubuntu_version stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install latest Docker CE, CLI, containerd, and Compose plugin
    print_status "🐳 Installing Docker CE with Compose v2..."
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # Start and enable Docker service
    print_status "🚀 Starting Docker service..."
    systemctl start docker
    systemctl enable docker
    
    # Add current user to docker group (if not root)
    if [ "$SUDO_USER" != "" ]; then
        print_status "👥 Adding $SUDO_USER to docker group..."
        usermod -aG docker "$SUDO_USER"
        print_warning "Note: $SUDO_USER will need to log out and back in for docker group membership to take effect"
    fi
    
    # Verify installation
    print_status "✅ Verifying Docker installation..."
    if docker version >/dev/null 2>&1; then
        print_status "✅ Docker version: $(docker version --format '{{.Server.Version}}')"
    else
        print_error "Docker installation failed"
        exit 1
    fi
    
    if docker compose version >/dev/null 2>&1; then
        print_status "✅ Docker Compose version: $(docker compose version --short)"
    else
        print_error "Docker Compose installation failed"
        exit 1
    fi
    
    print_status "✅ Docker installation completed successfully!"
}

# Check if Docker is running, offer to install if missing
check_docker() {
    # Check if Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        print_warning "Docker is not installed on this system"
        echo ""
        echo "Would you like to install Docker CE with Compose v2 automatically?"
        echo "This will:"
        echo "  • Remove old Docker packages from Ubuntu repo"
        echo "  • Install latest Docker CE from official Docker repository"
        echo "  • Install Docker Compose v2 plugin"
        echo "  • Start and enable Docker service"
        echo ""
        read -p "Install Docker automatically? [Y/n]: " -r
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            print_error "Docker is required for this deployment. Please install Docker manually."
            exit 1
        else
            install_docker
        fi
    fi
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is installed but not running. Please start Docker and try again."
        print_status "Try: sudo systemctl start docker"
        exit 1
    fi
    
    # Check if Docker Compose v2 is available
    if ! docker compose version >/dev/null 2>&1; then
        print_error "Docker Compose (v2) is not available. Please install Docker with Compose v2."
        print_status "Current Docker version: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'unknown')"
        exit 1
    fi
    
    print_status "✅ Docker and Docker Compose are available"
    print_status "Docker version: $(docker version --format '{{.Server.Version}}')"
    print_status "Docker Compose version: $(docker compose version --short)"
}

# Check system requirements
check_requirements() {
    print_section "Checking system requirements..."
    
    # Check available memory
    if command -v free >/dev/null 2>&1; then
        AVAILABLE_MEM=$(free -g | awk '/^Mem:/{print $7}')
        if [ ${AVAILABLE_MEM} -lt 8 ]; then
            print_warning "Available memory (${AVAILABLE_MEM}GB) is less than recommended 8GB for Kasm + containers"
        else
            print_status "✅ Memory: ${AVAILABLE_MEM}GB available"
        fi
    fi
    
    # Check available disk space
    AVAILABLE_DISK=$(df -BG . | awk 'NR==2{print $4}' | sed 's/G//')
    if [ ${AVAILABLE_DISK} -lt 20 ]; then
        print_warning "Available disk space (${AVAILABLE_DISK}GB) is less than recommended 20GB"
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

# Download and install Kasm Workspaces offline
install_kasm_workspaces() {
    print_section "Installing Kasm Workspaces offline..."
    
    # Create temporary directory
    local temp_dir="/tmp/kasm-installation"
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # Define Kasm release files
    local kasm_files=(
        "kasm_release_${KASM_VERSION}.tar.gz"
        "kasm_release_workspace_images_amd64_${KASM_VERSION}.tar.gz"
        "kasm_release_service_images_amd64_${KASM_VERSION}.tar.gz"
        "kasm_release_plugin_images_amd64_${KASM_VERSION}.tar.gz"
    )
    
    # Download Kasm release files
    print_status "📥 Downloading Kasm Workspaces ${KASM_VERSION}..."
    for file in "${kasm_files[@]}"; do
        if [ ! -f "$file" ]; then
            print_status "Downloading $file..."
            curl -L -o "$file" "https://kasm-static-content.s3.amazonaws.com/$file"
        else
            print_status "✅ $file already exists"
        fi
    done
    
    # Extract main release
    print_status "📦 Extracting Kasm release..."
    tar -xf "kasm_release_${KASM_VERSION}.tar.gz"
    
    # Run Kasm installation
    print_status "🚀 Installing Kasm Workspaces..."
    print_status "This may take 10-15 minutes..."
    
    # Make install script executable
    chmod +x kasm_release/install.sh
    
    # Install Kasm with offline images
    sudo bash kasm_release/install.sh \
        -L "$KASM_LISTEN_PORT" \
        --offline-workspaces "/tmp/kasm-installation/kasm_release_workspace_images_amd64_${KASM_VERSION}.tar.gz" \
        --offline-service "/tmp/kasm-installation/kasm_release_service_images_amd64_${KASM_VERSION}.tar.gz" \
        --offline-network-plugin "/tmp/kasm-installation/kasm_release_plugin_images_amd64_${KASM_VERSION}.tar.gz"
    
    print_status "✅ Kasm Workspaces installed successfully!"
    
    # Clean up temporary files
    cd /
    rm -rf "$temp_dir"
    
    # Show Kasm access information
    print_section "📊 Kasm Workspaces Access Information:"
    echo -e "  ${GREEN}Kasm URL:${NC}           https://$(hostname -I | awk '{print $1}'):${KASM_LISTEN_PORT}"
    echo -e "  ${GREEN}Default Username:${NC}   admin@kasm.local"
    echo -e "  ${GREEN}Default Password:${NC}   Check installation logs or /opt/kasm/current/conf/app/api.app.config.yaml"
    echo -e "  ${GREEN}Installation Path:${NC}  /opt/kasm/current"
    echo -e "  ${GREEN}Service Status:${NC}     sudo systemctl status kasm"
}

# Start Kasm services
start_kasm_services() {
    print_section "Starting Kasm services..."
    
    # Start Kasm services
    if systemctl is-active --quiet kasm; then
        print_status "✅ Kasm is already running"
    else
        print_status "🚀 Starting Kasm services..."
        systemctl start kasm
        sleep 10
        
        if systemctl is-active --quiet kasm; then
            print_status "✅ Kasm services started successfully"
        else
            print_error "❌ Failed to start Kasm services"
            print_status "Check logs: sudo journalctl -u kasm -f"
            exit 1
        fi
    fi
    
    # Wait for Kasm to be ready
    print_status "⏳ Waiting for Kasm to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -k -s "https://localhost:${KASM_LISTEN_PORT}/api/public/get_token" > /dev/null 2>&1; then
            print_status "✅ Kasm is ready and responding"
            break
        fi
        
        print_status "Attempt $attempt/$max_attempts - Waiting for Kasm..."
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        print_warning "Kasm may not be fully ready yet, but continuing with container deployment"
    fi
}

# Create Docker Compose file for remaining services
create_docker_compose() {
    print_section "Creating Docker Compose configuration for remaining services..."
    
    cat > "$COMPOSE_FILE" << 'EOF'
# RTPI-PEN: Kasm-First Deployment
# Remaining services after native Kasm installation

version: '3.8'

networks:
  rtpi_frontend:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16
  rtpi_backend:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 172.29.0.0/16
  rtpi_database:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 172.30.0.0/16
  sysreptor_default:
    driver: bridge

volumes:
  # Core Infrastructure Volumes
  rtpi_database_data:
    driver: local
  rtpi_cache_data:
    driver: local
  rtpi_orchestrator_data:
    driver: local
  rtpi_tools_data:
    driver: local
  rtpi_healer_data:
    driver: local
  
  # Application Service Volumes
  sysreptor-app-data:
    driver: local
  sysreptor-caddy-data:
    driver: local
  empire_data:
    driver: local
  registry_data:
    driver: local

services:
  # =============================================================================
  # SELF-HEALING INFRASTRUCTURE
  # =============================================================================

  rtpi-healer:
    build:
      context: ./services/rtpi-healer
      dockerfile: Dockerfile
    image: rtpi-pen/healer:latest
    container_name: rtpi-healer
    restart: unless-stopped
    user: root
    privileged: true
    networks:
      - rtpi_frontend
      - rtpi_backend
      - rtpi_database
    ports:
      - "8888:8888"
    volumes:
      - rtpi_healer_data:/data
      - /var/run/docker.sock:/var/run/docker.sock:rw
      - /opt:/opt:ro
      - ./:/home/cmndcntrl/rtpi-pen:ro
    environment:
      - PYTHONUNBUFFERED=1
      - DOCKER_HOST=unix:///var/run/docker.sock
      - KASM_INSTALLED=true
      - KASM_URL=https://localhost:8443
    depends_on:
      - rtpi-database
      - rtpi-cache
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8888/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # =============================================================================
  # CORE INFRASTRUCTURE SERVICES
  # =============================================================================

  rtpi-database:
    build:
      context: ./services/rtpi-database
      dockerfile: Dockerfile
    image: rtpi-pen/database:latest
    container_name: rtpi-database
    restart: unless-stopped
    networks:
      - rtpi_database
      - rtpi_backend
    ports:
      - "5432:5432"  # Exposed for external access if needed
    volumes:
      - rtpi_database_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=rtpi_main
      - POSTGRES_USER=rtpi
      - POSTGRES_PASSWORD=rtpi_secure_password
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "rtpi", "-d", "rtpi_main"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  rtpi-cache:
    build:
      context: ./services/rtpi-cache
      dockerfile: Dockerfile
    image: rtpi-pen/cache:latest
    container_name: rtpi-cache
    restart: unless-stopped
    networks:
      - rtpi_backend
    ports:
      - "6379:6379"  # Exposed for external access if needed
    volumes:
      - rtpi_cache_data:/var/lib/redis
    healthcheck:
      test: ["CMD", "redis-cli", "-p", "6379", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  rtpi-orchestrator:
    build:
      context: ./services/rtpi-orchestrator
      dockerfile: Dockerfile
    image: rtpi-pen/orchestrator:latest
    container_name: rtpi-orchestrator
    restart: unless-stopped
    networks:
      - rtpi_frontend
      - rtpi_backend
    ports:
      - "9444:9000"  # Portainer UI
    volumes:
      - rtpi_orchestrator_data:/data
      - /var/run/docker.sock:/var/run/docker.sock:ro
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  rtpi-tools:
    build:
      context: ./services/rtpi-tools
      dockerfile: Dockerfile
    image: rtpi-pen/tools:latest
    container_name: rtpi-tools
    restart: unless-stopped
    networks:
      - rtpi_backend
    volumes:
      - rtpi_tools_data:/home/rtpi-tools
      - ./configs:/opt/configs:ro
      - /opt/kasm:/opt/kasm:ro  # Access to Kasm installation
    environment:
      - TERM=xterm-256color
      - KASM_INSTALLED=true
    stdin_open: true
    tty: true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  rtpi-proxy:
    build:
      context: ./services/rtpi-proxy
      dockerfile: Dockerfile
    image: rtpi-pen/proxy:latest
    container_name: rtpi-proxy
    restart: unless-stopped
    networks:
      - rtpi_frontend
      - rtpi_backend
    ports:
      - "80:80"   # HTTP (redirects to HTTPS)
      - "443:443" # HTTPS (main interface)
    depends_on:
      - rtpi-orchestrator
    volumes:
      - /opt/kasm:/opt/kasm:ro  # Access to Kasm installation
    environment:
      - KASM_INSTALLED=true
      - KASM_URL=https://localhost:8443
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # =============================================================================
  # SYSREPTOR STACK
  # =============================================================================

  sysreptor-app:
    image: syslifters/sysreptor:2025.37
    container_name: sysreptor-app
    restart: unless-stopped
    networks:
      - sysreptor_default
      - rtpi_backend
      - rtpi_database
    ports:
      - "9000:8000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    volumes:
      - sysreptor-app-data:/app/data
    depends_on:
      - rtpi-database
      - sysreptor-redis
    command: /bin/bash /app/api/start.sh
    env_file:
      - ./configs/rtpi-sysreptor/app.env
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  sysreptor-caddy:
    image: caddy:latest
    container_name: sysreptor-caddy
    restart: unless-stopped
    networks:
      - sysreptor_default
      - rtpi_frontend
    ports:
      - "7777:7777"
    volumes:
      - sysreptor-caddy-data:/data
      - ./configs/rtpi-sysreptor/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
    command: caddy reverse-proxy --from :7777 --to sysreptor-app:8000
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  sysreptor-redis:
    image: bitnami/redis:7.2
    container_name: sysreptor-redis
    restart: unless-stopped
    networks:
      - sysreptor_default
      - rtpi_backend
    environment:
      - REDIS_PASSWORD=sysreptorredispassword
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # =============================================================================
  # SECURITY SERVICES
  # =============================================================================

  ps-empire:
    image: bcsecurity/empire:latest
    container_name: ps-empire
    restart: unless-stopped
    networks:
      - rtpi_backend
      - rtpi_frontend
    ports:
      - "1337:1337"
      - "5000:5000"
    volumes:
      - empire_data:/empire
    command: ./ps-empire server
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # =============================================================================
  # UTILITY SERVICES
  # =============================================================================

  registry:
    image: registry:latest
    container_name: local-registry
    restart: unless-stopped
    networks:
      - rtpi_backend
    ports:
      - "5001:5000"
    volumes:
      - registry_data:/var/lib/registry
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  node:
    image: node:latest
    container_name: node-service
    restart: unless-stopped
    networks:
      - rtpi_backend
    ports:
      - "3500:3500"
    command: ["node", "-e", "require('http').createServer((req,res)=>{res.end('Node.js service running')}).listen(3500)"]
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF

    print_status "✅ Docker Compose configuration created: $COMPOSE_FILE"
}

# Build and start remaining services
start_remaining_services() {
    print_section "Building and starting remaining services..."
    
    # Create environment file if it doesn't exist
    if [ ! -f .env ]; then
        create_env_file
    fi
    
    # Build services
    print_status "🏗️ Building Docker services..."
    docker compose -f "$COMPOSE_FILE" build
    
    # Start core services first
    print_status "🚀 Starting core infrastructure..."
    docker compose -f "$COMPOSE_FILE" up -d rtpi-database rtpi-cache
    
    # Wait for database to be ready
    print_status "⏳ Waiting for database to be ready..."
    sleep 15
    
    # Start application services
    print_status "🚀 Starting application services..."
    docker compose -f "$COMPOSE_FILE" up -d rtpi-orchestrator rtpi-proxy rtpi-healer
    
    # Start remaining services
    print_status "🚀 Starting remaining services..."
    docker compose -f "$COMPOSE_FILE" up -d
    
    print_status "✅ All services started!"
}

# Create environment file
create_env_file() {
    print_status "Creating environment configuration..."
    cat > .env << 'EOF'
# RTPI-PEN Kasm-First Environment Configuration
COMPOSE_PROJECT_NAME=rtpi-pen

# Database Configuration
POSTGRES_PASSWORD=rtpi_secure_password
REDIS_PASSWORD=rtpi_redis_password

# Network Configuration
RTPI_DOMAIN=localhost

# Kasm Integration
KASM_INSTALLED=true
KASM_VERSION=1.17.0
KASM_URL=https://localhost:8443
EOF
    print_status "✅ Environment file created"
}

# Show final status and access information
show_final_status() {
    echo ""
    print_section "🎉 RTPI-PEN Kasm-First Deployment Complete!"
    
    echo ""
    print_section "📊 Service Status:"
    echo "Kasm Workspaces (Native):"
    systemctl status kasm --no-pager -l || echo "  Status check failed"
    
    echo ""
    echo "Docker Services:"
    docker compose -f "$COMPOSE_FILE" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    print_section "🌐 Access Information:"
    echo -e "  ${GREEN}Kasm Workspaces:${NC}    https://localhost:8443"
    echo -e "  ${GREEN}Main Dashboard:${NC}     https://localhost"
    echo -e "  ${GREEN}Portainer:${NC}          http://localhost:9444"
    echo -e "  ${GREEN}SysReptor:${NC}          http://localhost:9000"
    echo -e "  ${GREEN}Empire C2:${NC}          http://localhost:1337"
    echo -e "  ${GREEN}Docker Registry:${NC}    http://localhost:5001"
    
    echo ""
    print_section "🔧 Management Commands:"
    echo "  Kasm status:     sudo systemctl status kasm"
    echo "  Kasm logs:       sudo journalctl -u kasm -f"
    echo "  Kasm restart:    sudo systemctl restart kasm"
    echo "  Container logs:  docker compose -f $COMPOSE_FILE logs -f [service]"
    echo "  Stop containers: docker compose -f $COMPOSE_FILE down"
    echo "  Container shell: docker compose -f $COMPOSE_FILE exec [service] /bin/bash"
    
    echo ""
    print_warning "⏳ Please wait 2-3 minutes for all services to fully initialize"
    print_status "🎯 Kasm is installed natively and should be the fastest to respond"
}

# Main execution
main() {
    case "${1:-install}" in
        install|full)
            check_root
            check_docker
            check_requirements
            install_kasm_workspaces
            start_kasm_services
            create_docker_compose
            start_remaining_services
            show_final_status
            ;;
        kasm-only)
            check_root
            check_docker
            check_requirements
            install_kasm_workspaces
            start_kasm_services
            echo ""
            print_status "✅ Kasm-only installation complete!"
            print_status "Run '$0 containers' to deploy the remaining services"
            ;;
        containers)
            check_docker
            create_docker_compose
            start_remaining_services
            show_final_status
            ;;
        docker-install)
            check_root
            install_docker
            print_status "✅ Docker installation complete!"
            print_status "You can now run '$0 install' to deploy RTPI-PEN"
            ;;
        status)
            echo "Kasm Status:"
            systemctl status kasm --no-pager -l || echo "Kasm not running"
            echo ""
            echo "Container Status:"
            if [ -f "$COMPOSE_FILE" ]; then
                docker compose -f "$COMPOSE_FILE" ps
            else
                echo "Docker compose file not found. Run '$0 install' first."
            fi
            ;;
        stop)
            print_status "Stopping all services..."
            systemctl stop kasm || echo "Kasm not running"
            if [ -f "$COMPOSE_FILE" ]; then
                docker compose -f "$COMPOSE_FILE" down
            fi
            print_status "✅ All services stopped"
            ;;
        restart)
            print_status "Restarting all services..."
            systemctl restart kasm || echo "Kasm not running"
            if [ -f "$COMPOSE_FILE" ]; then
                docker compose -f "$COMPOSE_FILE" restart
            fi
            print_status "✅ All services restarted"
            ;;
        help|*)
            echo -e "${BLUE}RTPI-PEN Kasm-First Deployment${NC}"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  install        - Full installation (Kasm + containers) [default]"
            echo "  kasm-only      - Install only Kasm Workspaces natively"
            echo "  containers     - Deploy only the containerized services"
            echo "  docker-install - Install Docker CE with Compose v2 only"
            echo "  status         - Show status of all services"
            echo "  stop           - Stop all services"
            echo "  restart        - Restart all services"
            echo "  help           - Show this help"
            echo ""
            echo "Docker Installation Features:"
            echo "  • Automatic Docker detection and installation"
            echo "  • Removes old Ubuntu repository Docker packages"
            echo "  • Installs latest Docker CE from official repository"
            echo "  • Includes Docker Compose v2 plugin"
            echo "  • Configures Docker service and user permissions"
            echo ""
            echo "Example usage:"
            echo "  sudo $0 install        # Full deployment (auto-installs Docker if needed)"
            echo "  sudo $0 docker-install # Install Docker only"
            echo "  sudo $0 kasm-only      # Install Kasm first"
            echo "  $0 containers          # Then deploy containers"
            echo "  $0 status              # Check status"
            ;;
    esac
}

# Run the main function
main "$@"
