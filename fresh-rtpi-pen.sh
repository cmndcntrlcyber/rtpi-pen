#!/bin/bash

# RTPI-PEN Fresh Installation Script - Enhanced with Resilience Framework
# Sets up complete Red Team Penetration Testing Infrastructure
# Version: 2.0.0 (Native Kasm + Containerized Services + Resilience Framework)

set -e  # Exit on any error

echo "🚀 Starting RTPI-PEN Fresh Installation with Resilience Framework..."
echo "=================================================================="

# Load Installation Resilience Framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/installation-resilience.sh" ]; then
    source "$SCRIPT_DIR/lib/installation-resilience.sh"
    log "✅ Resilience framework loaded"
else
    echo "⚠️  Warning: Resilience framework not found, using basic installation"
    # Fallback logging functions
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
    
    log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
    warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
    error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"; }
    info() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"; }
fi

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

# Port conflict detection and cleanup functions
check_port_8443_usage() {
    log "Checking port 8443 usage..."
    
    # Get processes using port 8443
    local port_users=$(lsof -Pi :8443 -sTCP:LISTEN 2>/dev/null || echo "")
    
    if [ -n "$port_users" ]; then
        log "Port 8443 is in use:"
        echo "$port_users"
        return 1
    else
        log "Port 8443 is available"
        return 0
    fi
}

cleanup_port_8443_conflicts() {
    log "Cleaning up port 8443 conflicts..."
    
    # Stop any Docker containers using port 8443
    local containers_using_port=$(docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Ports}}" | grep ":8443" | awk '{print $1}' || echo "")
    
    if [ -n "$containers_using_port" ]; then
        log "Stopping containers using port 8443..."
        for container in $containers_using_port; do
            log "Stopping container: $container"
            docker stop "$container" || true
            docker rm -f "$container" || true
        done
    fi
    
    # Stop docker-compose services that might be using port 8443
    if [ -f "/opt/rtpi-pen/docker-compose.yml" ]; then
        log "Stopping docker-compose services..."
        cd /opt/rtpi-pen
        docker compose down || true
        cd - > /dev/null
    fi
    
    # Kill any remaining processes on port 8443
    local port_pids=$(lsof -t -i:8443 2>/dev/null || echo "")
    if [ -n "$port_pids" ]; then
        log "Killing remaining processes on port 8443..."
        for pid in $port_pids; do
            kill -9 "$pid" 2>/dev/null || true
        done
    fi
    
    # Wait a moment for processes to cleanup
    sleep 3
    
    # Verify port is now free
    if check_port_8443_usage; then
        log "Port 8443 successfully freed"
        return 0
    else
        error "Failed to free port 8443"
        return 1
    fi
}

# Enhanced Kasm cleanup with port conflict resolution
cleanup_broken_kasm_enhanced() {
    log "Enhanced Kasm cleanup with port conflict resolution..."
    
    # First, cleanup port conflicts
    cleanup_port_8443_conflicts
    
    # Then do the standard Kasm cleanup
    cleanup_broken_kasm
    
    log "Enhanced Kasm cleanup completed"
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

# APT cache repair and validation functions
check_apt_health() {
    log "Checking APT package system health..."
    
    # Check disk space first
    local available_space=$(df /var/cache/apt/ | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 1048576 ]; then  # Less than 1GB
        warn "Low disk space in /var/cache/apt/: ${available_space}KB available"
    fi
    
    # Test if APT is working
    if ! apt-get check >/dev/null 2>&1; then
        return 1
    fi
    
    # Test if we can read package lists
    if ! apt-cache search test >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

repair_apt_cache() {
    log "Repairing APT package cache..."
    
    # Clean existing cache
    log "Cleaning APT cache..."
    apt-get clean || true
    apt-get autoclean || true
    
    # Remove corrupted cache files
    log "Removing corrupted cache files..."
    rm -rf /var/cache/apt/archives/partial/* || true
    rm -rf /var/cache/apt/srcpkgcache.bin* || true
    rm -rf /var/cache/apt/pkgcache.bin* || true
    
    # Fix permissions
    log "Fixing APT cache permissions..."
    chown -R root:root /var/cache/apt/ || true
    chmod -R 755 /var/cache/apt/ || true
    
    # Nuclear option if needed - remove all package lists
    if ! apt-get check >/dev/null 2>&1; then
        log "Performing complete APT reset..."
        rm -rf /var/lib/apt/lists/* || true
        mkdir -p /var/lib/apt/lists/partial
        chown -R root:root /var/lib/apt/lists/
        chmod -R 755 /var/lib/apt/lists/
    fi
    
    # Rebuild package cache
    log "Rebuilding package database..."
    apt-get update || {
        error "Failed to update package database after repair"
        return 1
    }
    
    # Final health check
    log "Verifying APT repair..."
    if apt-get check && apt-cache search test >/dev/null 2>&1; then
        log "✅ APT cache repair successful"
        return 0
    else
        error "❌ APT cache repair failed"
        return 1
    fi
}

# Pre-installation APT health check and repair
ensure_apt_health() {
    log "Ensuring APT package system is healthy..."
    
    if check_apt_health; then
        log "✅ APT system is healthy"
        return 0
    else
        warn "⚠️  APT system issues detected, attempting repair..."
        
        if repair_apt_cache; then
            log "✅ APT system repaired successfully"
            return 0
        else
            error "❌ Unable to repair APT system"
            error "Manual intervention may be required"
            exit 1
        fi
    fi
}

# 🛡️ RESILIENCE CHECK PHASE
echo "🛡️ Running Installation Resilience Check..."
echo "=============================================="

# Run comprehensive resilience check if framework is loaded
if command -v run_installation_resilience_check >/dev/null 2>&1; then
    if ! run_installation_resilience_check; then
        error "❌ Installation resilience check failed - aborting installation"
        error "Please address the issues above and try again"
        exit 1
    fi
    save_checkpoint "RESILIENCE_CHECK_PASSED"
else
    warn "⚠️  Resilience framework not available - using basic installation"
fi

# Basic system updates and essential packages
echo "📦 Installing system packages..."

# Ensure APT is healthy before proceeding
ensure_apt_health
save_checkpoint "APT_HEALTH_ENSURED"
apt-get update
apt upgrade -y
apt-get install -y jython
apt-get install -y python3-pip
apt-get install -y python-is-python3
apt-get install -y python3-virtualenv
apt-get install -y git
apt-get install -y containerd
apt-get install -y ca-certificates
apt-get install -y certbot
apt-get install -y curl
apt-get install -y gnupg
apt-get install -y lsb-release
apt-get install -y snapd
apt-get install -y npm
apt-get install -y default-jdk
apt-get install -y gccgo-go
apt-get install -y golang-go

# Red Team specific packages
echo "🔍 Installing Red Team tools..."
apt-get install -y nmap
apt-get install -y hashcat
apt-get install -y hydra
apt-get install -y proxychains4
apt-get install -y mingw-w64
apt-get install -y wine
apt-get install -y wireshark
apt-get install -y python3-impacket
apt-get install -y nbtscan
apt-get install -y smbclient
apt-get install -y net-tools
apt-get install -y build-essential
sudo snap install metasploit-framework


# For C2 development and operation
echo "🐍 Installing Python packages..."
pip install pwntools
pip install pycrypto
pip install cryptography
pip install requests
pip install pyOpenSSL

echo "🐳 Setting up Docker..."
echo "-------------------------------------"
# Remove conflicting packages
echo "Removing conflicting packages..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    sudo apt-get remove -y $pkg
done
sudo apt remove -y docker docker-ce docker.io containerd runc

# Add Docker's official GPG key
echo "Adding Docker's official GPG key..."
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources
echo "Adding Docker repository..."
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y

# Install Docker Engine
echo "Installing Docker Engine..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify Docker installation
#echo "Verifying Docker installation..."
#docker version
#docker info --format '{{.ContainerdVersion}}'

echo "🏗️ Setting up RTPI environment..."
echo "-------------------------------------"
# Create base directories
mkdir -p /opt/rtpi
cd /opt/rtpi

echo "🖥️ Setting up KASM Workspaces (Native)..."
echo "-------------------------------------"

# Check existing Kasm installation before proceeding
kasm_status=$(check_kasm_status)
case $kasm_status in
    "WORKING")
        log "✅ Kasm is already installed and working (>10 min), skipping Kasm installation"
        export SKIP_KASM_INSTALLATION=true
        ;;
    "BROKEN")
        log "🔧 Kasm detected but not working properly, cleaning up..."
        cleanup_broken_kasm_enhanced
        log "🚀 Proceeding with fresh Kasm installation..."
        export SKIP_KASM_INSTALLATION=false
        ;;
    "ABSENT")
        log "📦 No Kasm installation detected, proceeding with installation..."
        # Even for absent, check for port conflicts
        if ! check_port_8443_usage; then
            log "Port 8443 is in use, cleaning up conflicts..."
            cleanup_port_8443_conflicts
        fi
        export SKIP_KASM_INSTALLATION=false
        ;;
esac

# Only proceed with installation if not skipped
if [ "$SKIP_KASM_INSTALLATION" != "true" ]; then
    cd /opt

    # Download Kasm 1.17.0 release files with resilience
    echo "Downloading Kasm 1.17.0 release files with resilience..."
    
    kasm_files=(
        "https://kasm-static-content.s3.amazonaws.com/kasm_release_1.17.0.7f020d.tar.gz"
        "https://kasm-static-content.s3.amazonaws.com/kasm_release_service_images_amd64_1.17.0.7f020d.tar.gz"
        "https://kasm-static-content.s3.amazonaws.com/kasm_release_workspace_images_amd64_1.17.0.7f020d.tar.gz"
        "https://kasm-static-content.s3.amazonaws.com/kasm_release_plugin_images_amd64_1.17.0.7f020d.tar.gz"
    )
    
    # Use resilient download if available, otherwise fallback to curl
    download_failed=false
    for url in "${kasm_files[@]}"; do
        filename=$(basename "$url")
        if command -v download_with_resilience >/dev/null 2>&1; then
            if ! download_with_resilience "$url" "$filename"; then
                download_failed=true
                break
            fi
        else
            if ! curl -O "$url"; then
                download_failed=true
                break
            fi
        fi
    done
    
    if [ "$download_failed" = true ]; then
        error "❌ Failed to download Kasm installation files"
        exit 1
    fi
    
    save_checkpoint "KASM_FILES_DOWNLOADED"

    # Extract and install Kasm
    echo "Installing Kasm Workspaces..."
    tar -xf kasm_release_1.17.0.7f020d.tar.gz
    
    # Run the installation script with the necessary parameters
    sudo bash kasm_release/install.sh -L 8443 \
        --offline-workspaces /opt/kasm_release_workspace_images_amd64_1.17.0.7f020d.tar.gz \
        --offline-service /opt/kasm_release_service_images_amd64_1.17.0.7f020d.tar.gz \
        --offline-network-plugin /opt/kasm_release_plugin_images_amd64_1.17.0.7f020d.tar.gz

    # Install and enable Kasm network plugin
    echo "Setting up Kasm Network Plugin..."
    PLUGIN_NAME="kasmweb/kasm-network-plugin:amd64-1.2"

    # Check if plugin already exists
    if docker plugin ls | grep -q "$PLUGIN_NAME"; then
        echo "✓ Kasm network plugin already installed"
        # Check if plugin is enabled
        if docker plugin ls | grep "$PLUGIN_NAME" | grep -q "true"; then
            echo "✓ Kasm network plugin is already enabled"
        else
            echo "Enabling Kasm network plugin..."
            sudo docker plugin enable "$PLUGIN_NAME"
            echo "✓ Kasm network plugin enabled"
        fi
    else
        echo "Installing Kasm network plugin..."
        sudo docker plugin install "$PLUGIN_NAME" --grant-all-permissions
        echo "✓ Kasm network plugin installed"
        
        echo "Enabling Kasm network plugin..."
        sudo docker plugin enable "$PLUGIN_NAME"
        echo "✓ Kasm network plugin enabled"
    fi

    # Start Kasm proxy if needed
    echo "Starting Kasm proxy..."
    sudo docker start kasm_proxy || true
else
    log "Skipping Kasm installation - already working"
fi

echo "🐋 Installing Portainer..."
echo "-------------------------------------"

# Check existing Portainer installation before proceeding
portainer_status=$(check_portainer_status)
case $portainer_status in
    "WORKING")
        log "✅ Portainer is already installed and working (>10 min), skipping Portainer installation"
        export SKIP_PORTAINER_INSTALLATION=true
        ;;
    "BROKEN")
        log "🔧 Portainer detected but not working properly, cleaning up..."
        cleanup_broken_portainer
        log "🚀 Proceeding with fresh Portainer installation..."
        export SKIP_PORTAINER_INSTALLATION=false
        ;;
    "ABSENT")
        log "📦 No Portainer installation detected, proceeding with installation..."
        export SKIP_PORTAINER_INSTALLATION=false
        ;;
esac

# Only proceed with installation if not skipped
if [ "$SKIP_PORTAINER_INSTALLATION" != "true" ]; then
    # Create volume if it doesn't exist
    if ! docker volume ls | grep -q "portainer_data"; then
        docker volume create portainer_data
        echo "✓ Created Portainer data volume"
    else
        echo "✓ Portainer data volume already exists"
    fi

    # Check if Portainer container already exists
    if docker ps -a | grep -q "portainer"; then
        echo "✓ Portainer container already exists"
        # Check if it's running
        if docker ps | grep -q "portainer"; then
            echo "✓ Portainer is already running"
        else
            echo "Starting existing Portainer container..."
            docker start portainer
            echo "✓ Portainer started"
        fi
    else
        echo "Installing Portainer..."
        docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v portainer_data:/data \
            portainer/portainer-ce:lts
        echo "✓ Portainer installed and started"
    fi
else
    log "Skipping Portainer installation - already working"
fi

echo "📊 Installing SysReptor..."
echo "-------------------------------------"
cd /opt/rtpi-pen/configs/rtpi-sysreptor
if [ -f "install-sysreptor.sh" ]; then
    bash install-sysreptor.sh
else
    echo "⚠️  SysReptor installation script not found, skipping..."
fi

echo "👑 Installing Empire C2..."
echo "-------------------------------------"

# Check existing security services installation before proceeding
security_services_status=$(check_security_services_status)
case $security_services_status in
    "WORKING")
        log "✅ Security services are already installed and working (>10 min), skipping security services installation"
        export SKIP_SECURITY_SERVICES_INSTALLATION=true
        ;;
    "BROKEN")
        log "🔧 Security services detected but not working properly, cleaning up..."
        cleanup_broken_security_services
        log "🚀 Proceeding with fresh security services installation..."
        export SKIP_SECURITY_SERVICES_INSTALLATION=false
        ;;
    "ABSENT")
        log "📦 No security services installation detected, proceeding with installation..."
        export SKIP_SECURITY_SERVICES_INSTALLATION=false
        ;;
esac

# Only proceed with installation if not skipped
if [ "$SKIP_SECURITY_SERVICES_INSTALLATION" != "true" ]; then
    # Check if Empire directory exists
    if [ -d "/opt/Empire" ]; then
        echo "✓ Empire directory already exists at /opt/Empire"
        cd /opt/Empire
    else
        echo "Cloning Empire repository..."
        cd /opt/
        git clone --recursive https://github.com/BC-SECURITY/Empire.git
        cd Empire/
        echo "✓ Empire repository cloned successfully"
    fi

    # Ensure we're in the Empire directory
    cd /opt/Empire

    # Check if Empire is already installed
    if [ -f "ps-empire" ]; then
        echo "✓ Empire appears to be already installed"
        
        # Check if Empire is functional
        if ./ps-empire --help >/dev/null 2>&1; then
            echo "✓ Empire installation verified"
        else
            echo "⚠️  Empire installation may be incomplete, attempting reinstall..."
            ./setup/checkout-latest-tag.sh
            ./ps-empire install -f -y
            echo "✓ Empire installation completed"
        fi
    else
        echo "Installing Empire..."
        ./setup/checkout-latest-tag.sh
        ./ps-empire install -f -y
        echo "✓ Empire installation completed"
    fi

    # Create Empire service configuration
    echo "Configuring Empire service..."
    cat > /etc/systemd/system/empire.service << 'EOF'
[Unit]
Description=Empire C2 Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/Empire
ExecStart=/opt/Empire/ps-empire server -f
Restart=always
RestartSec=10
Environment=EMPIRE_HOME=/opt/Empire

[Install]
WantedBy=multi-user.target
EOF

    # Enable but don't start Empire service (will be managed by Docker Compose)
    systemctl daemon-reload
    systemctl enable empire.service

    echo "✓ Empire C2 installation and configuration completed"
    echo "  - Empire installed at: /opt/Empire"
    echo "  - Empire can be started with: systemctl start empire"
    echo "  - Empire will be accessible at: http://localhost:1337"
else
    log "Skipping security services installation - already working"
fi

# Generate SysReptor configuration - Enhanced for automation
generate_sysreptor_config() {
    log "Generating SysReptor configuration for automated build..."
    
    # Create the config directory if it doesn't exist
    local config_dir="configs/rtpi-sysreptor"
    mkdir -p "$config_dir"
    
    # Create app.env file path
    local app_env_file="$config_dir/app.env"
    
    # Pre-build cleanup - remove any existing template or problematic files
    log "Cleaning up any existing SysReptor configuration files..."
    if [ -f "$app_env_file" ]; then
        log "Removing existing app.env file for clean generation..."
        rm -f "$app_env_file"
    fi
    
    # Remove any backup or template files that might interfere
    rm -f "$config_dir/app.env.bak" "$config_dir/app.env.template" "$config_dir/app.env.example" 2>/dev/null || true
    
    # Generate cryptographically secure keys with proper base64 encoding
    log "Generating secure cryptographic keys..."
    local secret_key
    local key_id
    local enc_key
    
    # Generate SECRET_KEY with validation
    secret_key=$(openssl rand -base64 64 | tr -d '\n=' | head -c 64)
    if [ ${#secret_key} -lt 32 ]; then
        error "Failed to generate adequate SECRET_KEY"
        return 1
    fi
    
    # Generate ENCRYPTION_KEYS with validation - ensure proper base64 padding
    key_id=$(uuidgen)
    if [ -z "$key_id" ]; then
        error "Failed to generate UUID for encryption key"
        return 1
    fi
    
    # Generate properly padded base64 encryption key (32 bytes = 44 characters with padding)
    enc_key=$(python3 -c "import base64, secrets; print(base64.b64encode(secrets.token_bytes(32)).decode())")
    if [ -z "$enc_key" ] || [ ${#enc_key} -lt 32 ]; then
        error "Failed to generate adequate encryption key"
        return 1
    fi
    
    # Validate the generated key is proper base64
    if ! echo "$enc_key" | base64 -d > /dev/null 2>&1; then
        error "Generated encryption key has invalid base64 format"
        return 1
    fi
    
    log "Creating clean SysReptor app.env configuration..."
    
    # Create app.env with clean, validated configuration
    cat > "$app_env_file" << EOF
# SysReptor Configuration
# Generated automatically by RTPI-PEN build process
# Build Date: $(date)
# DO NOT EDIT MANUALLY - This file is auto-generated

# Security Keys
SECRET_KEY=$secret_key

# Database Configuration
DATABASE_HOST=rtpi-database
DATABASE_NAME=sysreptor
DATABASE_USER=sysreptor
DATABASE_PASSWORD=sysreptorpassword
DATABASE_PORT=5432

# Encryption Keys
ENCRYPTION_KEYS=[{"id":"$key_id","key":"$enc_key","cipher":"AES-GCM","revoked":false}]
DEFAULT_ENCRYPTION_KEY_ID=$key_id

# Security and Access
ALLOWED_HOSTS=sysreptor,0.0.0.0,127.0.0.1,rtpi-pen-dev,localhost,sysreptor.rtpi.local
SECURE_SSL_REDIRECT=off
USE_X_FORWARDED_HOST=on
DEBUG=off

# Redis Configuration
REDIS_HOST=sysreptor-redis
REDIS_PORT=6379
REDIS_INDEX=0
REDIS_PASSWORD=sysreptorredispassword

# Features and Plugins
ENABLE_PRIVATE_DESIGNS=true
DISABLE_WEBSOCKETS=true
ENABLED_PLUGINS=cyberchef,graphqlvoyager,checkthehash

# Performance and Scaling
CELERY_BROKER_URL=redis://:sysreptorredispassword@sysreptor-redis:6379/0
CELERY_RESULT_BACKEND=redis://:sysreptorredispassword@sysreptor-redis:6379/0
EOF
    
    # Set proper permissions
    chmod 644 "$app_env_file"
    
    # Validation checks
    log "Validating generated configuration..."
    
    if [ ! -f "$app_env_file" ]; then
        error "❌ Failed to create app.env file"
        return 1
    fi
    
    # Check file size (should be reasonable)
    local file_size=$(wc -c < "$app_env_file")
    if [ "$file_size" -lt 500 ]; then
        error "❌ Generated app.env file is too small ($file_size bytes)"
        return 1
    fi
    
    # Check for required keys
    local required_keys=("SECRET_KEY" "DATABASE_HOST" "ENCRYPTION_KEYS" "REDIS_HOST")
    for key in "${required_keys[@]}"; do
        if ! grep -q "^$key=" "$app_env_file"; then
            error "❌ Missing required key: $key"
            return 1
        fi
    done
    
    # Check for problematic content
    if grep -q "BIND_PORT" "$app_env_file"; then
        error "❌ Invalid BIND_PORT configuration detected"
        return 1
    fi
    
    # Test if Docker Compose can parse the file
    log "Testing Docker Compose compatibility..."
    if command -v docker >/dev/null 2>&1; then
        # Test the env file syntax
        if ! docker run --rm --env-file "$app_env_file" alpine:latest /bin/sh -c 'echo "Environment file syntax OK"' >/dev/null 2>&1; then
            error "❌ Docker Compose cannot parse the generated env file"
            return 1
        fi
    fi
    
    log "✅ SysReptor configuration generated and validated successfully"
    log "Configuration file: $app_env_file"
    log "File size: $file_size bytes"
    
    return 0
}

echo "🔧 Setting environment variables..."
echo "-------------------------------------"
# Set KASM_INSTALLED flag for healer service
export KASM_INSTALLED=true
echo "KASM_INSTALLED=true" >> /etc/environment

# Add current user to docker group
usermod -aG docker $USER || true

# Create SysReptor superuser after services are running
create_sysreptor_superuser() {
    log "Setting up SysReptor superuser account..."
    
    # Get current system username
    local current_user=$(whoami)
    local username
    
    # Check if running in automated mode (non-interactive terminal)
    if [ ! -t 0 ] || [ -n "$AUTOMATED_MODE" ]; then
        # Non-interactive/automated mode
        username="rtpi-admin"
        log "Running in automated mode - using default username: $username"
    else
        # Interactive mode
        echo ""
        echo "============================================"
        echo "🔐 SysReptor User Account Configuration"
        echo "============================================"
        echo "Choose username option for SysReptor:"
        echo "1. Use current system username ($current_user)"
        echo "2. Create custom username"
        echo "3. Use default (rtpi-admin)"
        echo ""
        read -p "Enter your choice (1-3) [default: 3]: " choice
        
        case $choice in
            1)
                username="$current_user"
                log "Using current system username: $username"
                ;;
            2)
                while true; do
                    read -p "Enter custom username: " custom_username
                    # Validate username (alphanumeric, underscore, hyphen only)
                    if [[ "$custom_username" =~ ^[a-zA-Z0-9_-]+$ ]] && [[ ${#custom_username} -ge 3 ]]; then
                        username="$custom_username"
                        log "Using custom username: $username"
                        break
                    else
                        error "Username must be at least 3 characters and contain only letters, numbers, underscores, or hyphens"
                    fi
                done
                ;;
            3|"")
                username="rtpi-admin"
                log "Using default username: $username"
                ;;
            *)
                warn "Invalid choice, using default username: rtpi-admin"
                username="rtpi-admin"
                ;;
        esac
    fi
    
    # Wait for SysReptor service to be ready
    log "Waiting for SysReptor service to be ready..."
    local max_wait=120  # 2 minutes
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if docker compose ps sysreptor-app | grep -q "Up"; then
            log "SysReptor service is running"
            break
        fi
        
        if [ $wait_time -eq 0 ]; then
            info "Waiting for sysreptor-app service to start..."
        fi
        
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    if [ $wait_time -ge $max_wait ]; then
        error "SysReptor service failed to start within timeout"
        return 1
    fi
    
    # Additional wait for service initialization
    log "Waiting for SysReptor to complete initialization..."
    sleep 15
    
    # Ensure clean database state to prevent encryption key conflicts
    log "Ensuring clean database state for SysReptor..."
    if docker compose exec -T sysreptor-app python3 manage.py shell << 'EOF'
from django.contrib.auth import get_user_model
from django.core.management import execute_from_command_line
import sys

# Check if there are any existing users that might cause encryption key conflicts
User = get_user_model()
try:
    user_count = User.objects.count()
    print(f"Found {user_count} existing users in database")
    if user_count > 0:
        print("Database contains existing data - this is a fresh install, flushing database...")
        # Flush the database to ensure clean state
        from django.core.management.commands.flush import Command as FlushCommand
        from django.core.management.base import CommandError
        try:
            from io import StringIO
            from django.core.management import call_command
            call_command('flush', '--noinput')
            print("✅ Database flushed successfully")
        except Exception as e:
            print(f"❌ Database flush failed: {e}")
            sys.exit(1)
    else:
        print("✅ Database is clean, proceeding...")
except Exception as e:
    print(f"⚠️ Database check failed, proceeding with caution: {e}")
EOF
    then
        log "✅ Database state validated successfully"
    else
        warn "⚠️ Database validation encountered issues, but continuing..."
    fi
    
    # Create superuser with automated credentials for non-interactive mode
    log "Creating SysReptor superuser account: $username"
    
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        info "Attempt $attempt of $max_attempts..."
        
        if [ ! -t 0 ] || [ -n "$AUTOMATED_MODE" ]; then
            # Automated mode - create user with default credentials
            if docker compose exec -T sysreptor-app python3 manage.py shell << EOF
import os
from django.contrib.auth import get_user_model
User = get_user_model()
if not User.objects.filter(username='$username').exists():
    user = User.objects.create_superuser('$username', 'admin@rtpi.local', 'rtpi-admin-password')
    print(f"Superuser '{username}' created successfully!")
else:
    print(f"Superuser '{username}' already exists")
EOF
            then
                log "✅ SysReptor superuser '$username' created successfully!"
                log "🌐 Access SysReptor at: http://localhost:7777"
                log "🔑 Username: $username"
                log "🔑 Password: rtpi-admin-password"
                return 0
            fi
        else
            # Interactive mode - prompt for credentials
            if docker compose exec sysreptor-app python3 manage.py createsuperuser --username "$username"; then
                log "✅ SysReptor superuser '$username' created successfully!"
                log "🌐 Access SysReptor at: http://localhost:7777"
                log "🔑 Username: $username"
                return 0
            fi
        fi
        
        warn "Failed to create superuser (attempt $attempt/$max_attempts)"
        
        if [ $attempt -eq $max_attempts ]; then
            error "All attempts failed. You can create the superuser manually later:"
            error "   docker compose exec sysreptor-app python3 manage.py createsuperuser --username $username"
            return 1
        else
            info "Retrying in 5 seconds..."
            sleep 5
        fi
        
        attempt=$((attempt + 1))
    done
    
    return 1
}

echo "🐳 Building and starting containerized services..."
echo "-------------------------------------"
cd /opt/rtpi-pen

# Generate SysReptor configuration before building containers
generate_sysreptor_config

# Run encryption key fix as an additional safety measure
log "Running SysReptor encryption key validation and fix..."
if [ -f "./repair-scripts/fix-sysreptor-encryption-keys.sh" ]; then
    if ./repair-scripts/fix-sysreptor-encryption-keys.sh; then
        log "✅ SysReptor encryption keys validated successfully"
    else
        warn "⚠️  Encryption key validation script encountered issues, but continuing..."
    fi
else
    warn "⚠️  Encryption key fix script not found, skipping validation..."
fi

log "Building Docker images..."
if docker compose build; then
    log "✅ Docker images built successfully"
else
    error "❌ Failed to build Docker images"
    exit 1
fi

log "Starting containerized services..."
if docker compose up -d; then
    log "✅ Containerized services started successfully"
else
    error "❌ Failed to start containerized services"
    exit 1
fi

log "Waiting for services to stabilize..."
sleep 30

# Create SysReptor superuser after services are ready
create_sysreptor_superuser

echo "📋 Installation Summary:"
echo "-------------------------------------"
echo "✅ System packages installed"
echo "✅ Docker Engine installed and configured"
echo "✅ Kasm Workspaces 1.17.0 installed natively"
echo "✅ Portainer installed"
echo "✅ SysReptor installation attempted"
echo "✅ Empire C2 installation attempted"
echo "✅ Environment variables configured"
echo "✅ Containerized services built and started"
echo ""
echo "🌐 Access Points:"
echo "• Kasm Workspaces: https://localhost:8443"
echo "• Portainer: https://localhost:9443"
echo "• SysReptor: http://localhost:7777"
echo "• Empire C2: http://localhost:1337"
echo ""
echo "📝 Management Commands:"
echo "• View logs: docker compose logs -f"
echo "• Restart services: docker compose restart"
echo "• Stop services: docker compose down"
echo "• Service status: docker compose ps"
echo ""
echo "🏥 Self-healing service will monitor and repair services automatically"
echo ""
echo "✅ RTPI-PEN Environment Setup Complete!"
echo ""
echo "🌐 Optional: Configure Custom Hostnames"
echo "-------------------------------------"
echo "Would you like to configure custom hostnames for easier access?"
echo "This will add entries like kasm.rtpi.local, empire.rtpi.local, etc. to /etc/hosts"
echo ""
read -p "Configure custom hostnames? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Configuring custom hostnames..."
    if [ -f "./setup/configure-hosts.sh" ]; then
        ./setup/configure-hosts.sh add --force
        echo ""
        echo "✅ Custom hostnames configured!"
        echo "You can now access services via:"
        echo "  • Kasm Workspaces: https://kasm.rtpi.local:8443"
        echo "  • Empire C2: http://empire.rtpi.local:1337"
        echo "  • Portainer: https://portainer.rtpi.local:9443"
        echo "  • SysReptor: http://sysreptor.rtpi.local:7777"
        echo ""
        echo "💡 Tip: Run './setup/configure-hosts.sh remove' to remove these entries later"
    else
        echo "⚠️  Hosts configuration script not found"
    fi
else
    echo "Skipping hostname configuration"
    echo "💡 Tip: Run './setup/configure-hosts.sh add' later to configure custom hostnames"
fi
