#!/bin/bash

# RTPI-PEN Fresh Installation Script
# Sets up complete Red Team Penetration Testing Infrastructure
# Version: 1.17.0 (Native Kasm + Containerized Services)

set -e  # Exit on any error

echo "🚀 Starting RTPI-PEN Fresh Installation..."
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
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

# Basic system updates and essential packages
echo "📦 Installing system packages..."
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
        cleanup_broken_kasm
        log "🚀 Proceeding with fresh Kasm installation..."
        export SKIP_KASM_INSTALLATION=false
        ;;
    "ABSENT")
        log "📦 No Kasm installation detected, proceeding with installation..."
        export SKIP_KASM_INSTALLATION=false
        ;;
esac

# Only proceed with installation if not skipped
if [ "$SKIP_KASM_INSTALLATION" != "true" ]; then
    cd /opt

    # Download Kasm 1.17.0 release files
    echo "Downloading Kasm 1.17.0 release files..."
    curl -O https://kasm-static-content.s3.amazonaws.com/kasm_release_1.17.0.7f020d.tar.gz
    curl -O https://kasm-static-content.s3.amazonaws.com/kasm_release_service_images_amd64_1.17.0.7f020d.tar.gz
    curl -O https://kasm-static-content.s3.amazonaws.com/kasm_release_workspace_images_amd64_1.17.0.7f020d.tar.gz
    curl -O https://kasm-static-content.s3.amazonaws.com/kasm_release_plugin_images_amd64_1.17.0.7f020d.tar.gz

    # Extract and install Kasm
    echo "Installing Kasm Workspaces..."
    tar -xf kasm_release_1.17.0.7f020d.tar.gz
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

echo "🔧 Setting environment variables..."
echo "-------------------------------------"
# Set KASM_INSTALLED flag for healer service
export KASM_INSTALLED=true
echo "KASM_INSTALLED=true" >> /etc/environment

# Add current user to docker group
usermod -aG docker $USER || true

echo "📋 Installation Summary:"
echo "-------------------------------------"
echo "✅ System packages installed"
echo "✅ Docker Engine installed and configured"
echo "✅ Kasm Workspaces 1.17.0 installed natively"
echo "✅ Portainer installed"
echo "✅ SysReptor installation attempted"
echo "✅ Empire C2 installation attempted"
echo "✅ Environment variables configured"
echo ""
echo "🌐 Access Points:"
echo "• Kasm Workspaces: https://localhost:8443"
echo "• Portainer: https://localhost:9443"
echo "• SysReptor: http://localhost:7777"
echo "• Empire C2: http://localhost:1337"
echo ""
echo "📝 Next Steps:"
echo "1. Run 'docker-compose up -d' to start containerized services"
echo "2. Access services via the URLs above"
echo "3. Check logs with 'docker-compose logs' if issues occur"
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
