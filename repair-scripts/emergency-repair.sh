#!/bin/bash
# RTPI-PEN Emergency Repair Script
# Stops restart loops and cleans up environment

set -e

echo "🚨 Starting Emergency Repair for RTPI-PEN..."
echo "This will stop all containers and clean up the environment"

# Function to display status
show_status() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Current Container Status:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    sudo docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to stop containers gracefully
stop_containers() {
    echo "🛑 Stopping all containers..."
    
    # Get all running containers
    local containers=$(sudo docker ps -q)
    
    if [ -n "$containers" ]; then
        echo "Stopping containers gracefully..."
        sudo docker stop $containers || true
        
        # Wait a bit for graceful shutdown
        sleep 5
        
        # Force kill any remaining containers
        local remaining=$(sudo docker ps -q)
        if [ -n "$remaining" ]; then
            echo "Force killing remaining containers..."
            sudo docker kill $remaining || true
        fi
        
        echo "✅ All containers stopped"
    else
        echo "ℹ️ No running containers found"
    fi
}

# Function to remove failed containers
remove_failed_containers() {
    echo "🗑️ Removing failed containers..."
    
    # Remove exited containers
    local exited_containers=$(sudo docker ps -aq --filter "status=exited")
    if [ -n "$exited_containers" ]; then
        echo "Removing exited containers..."
        sudo docker rm $exited_containers || true
    fi
    
    # Remove containers with restart loops
    local problem_containers=(
        "kasm_agent"
        "rtpi-healer"
        "rtpi-orchestrator"
        "rtpi-init"
    )
    
    for container in "${problem_containers[@]}"; do
        if sudo docker ps -a --format "{{.Names}}" | grep -q "^${container}$"; then
            echo "Removing problematic container: $container"
            sudo docker rm -f "$container" || true
        fi
    done
    
    echo "✅ Failed containers removed"
}

# Function to clean up Docker resources
cleanup_docker_resources() {
    echo "🧹 Cleaning up Docker resources..."
    
    # Clean up unused images
    echo "Cleaning up unused images..."
    sudo docker image prune -f || true
    
    # Clean up unused volumes (be careful with this)
    echo "Cleaning up unused volumes..."
    sudo docker volume prune -f || true
    
    # Clean up unused networks
    echo "Cleaning up unused networks..."
    sudo docker network prune -f || true
    
    # Clean up build cache
    echo "Cleaning up build cache..."
    sudo docker builder prune -f || true
    
    echo "✅ Docker resources cleaned up"
}

# Function to fix Docker socket permissions
fix_docker_permissions() {
    echo "🔧 Fixing Docker socket permissions..."
    
    # Ensure Docker socket has correct permissions
    sudo chmod 666 /var/run/docker.sock || true
    
    # Add current user to docker group if not already there
    if ! groups $USER | grep -q docker; then
        sudo usermod -aG docker $USER
        echo "Added $USER to docker group (restart shell to take effect)"
    fi
    
    echo "✅ Docker permissions fixed"
}

# Function to create backup of current state
backup_current_state() {
    echo "💾 Creating backup of current state..."
    
    local backup_dir="/tmp/rtpi-pen-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup docker-compose.yml
    if [ -f "docker-compose.yml" ]; then
        cp docker-compose.yml "$backup_dir/"
    fi
    
    # Backup .env file
    if [ -f ".env" ]; then
        cp .env "$backup_dir/"
    fi
    
    # Backup configs directory
    if [ -d "configs" ]; then
        cp -r configs "$backup_dir/"
    fi
    
    # Save current container states
    sudo docker ps -a > "$backup_dir/container_states.txt"
    sudo docker images > "$backup_dir/image_list.txt"
    sudo docker volume ls > "$backup_dir/volume_list.txt"
    sudo docker network ls > "$backup_dir/network_list.txt"
    
    echo "✅ Backup created at: $backup_dir"
}

# Function to check system resources
check_system_resources() {
    echo "📊 Checking system resources..."
    
    # Check disk space
    echo "Disk Usage:"
    df -h / | head -2
    
    # Check memory
    echo "Memory Usage:"
    free -h
    
    # Check Docker daemon
    echo "Docker Daemon Status:"
    sudo systemctl is-active docker || echo "Docker daemon not running"
    
    # Check for any Docker issues
    echo "Docker System Info:"
    sudo docker system df || echo "Could not get Docker system info"
    
    echo "✅ System resources checked"
}

# Function to prepare for restart
prepare_for_restart() {
    echo "🔄 Preparing for clean restart..."
    
    # Ensure required directories exist
    local required_dirs=(
        "/opt/kasm/1.15.0"
        "/opt/rtpi-orchestrator/data"
        "/var/log/rtpi-healer"
        "/data/rtpi-healer"
        "/data/backups"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            echo "Creating directory: $dir"
            sudo mkdir -p "$dir"
            sudo chown -R 1000:1000 "$dir"
            sudo chmod -R 755 "$dir"
        fi
    done
    
    # Create logs directory for troubleshooting
    sudo mkdir -p /var/log/rtpi-pen-repair
    sudo chmod 755 /var/log/rtpi-pen-repair
    
    echo "✅ System prepared for restart"
}

# Main execution
main() {
    echo "Starting emergency repair at $(date)"
    
    # Check if running as root or with sudo access
    if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
        echo "❌ This script requires sudo privileges"
        exit 1
    fi
    
    # Show initial status
    show_status
    
    # Create backup before making changes
    backup_current_state
    
    # Fix Docker permissions first
    fix_docker_permissions
    
    # Check system resources
    check_system_resources
    
    # Stop all containers
    stop_containers
    
    # Remove failed containers
    remove_failed_containers
    
    # Clean up Docker resources
    cleanup_docker_resources
    
    # Prepare for restart
    prepare_for_restart
    
    # Final status check
    echo "🔍 Final status check..."
    show_status
    
    echo "✅ Emergency repair completed successfully!"
    echo "📝 Next steps:"
    echo "   1. Run manual-init.sh to initialize configurations"
    echo "   2. Run sequential-startup.sh to restart services"
    echo "   3. Run health-validator.sh to verify system health"
    echo ""
    echo "💡 If issues persist, check logs in /var/log/rtpi-pen-repair/"
}

# Execute main function
main "$@"
