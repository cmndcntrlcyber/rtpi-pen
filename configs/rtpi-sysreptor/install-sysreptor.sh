# SysReptor installation script
# Note: app.env configuration is now generated automatically by build scripts

log() {
    echo -e "\033[0;32m[$(date +'%Y-%m-%d %H:%M:%S')] SYSREPTOR: $1\033[0m"
}

log "Setting up SysReptor..."

# Download SysReptor setup files (for reference, though we use containerized version)
log "Downloading SysReptor setup files..."
curl -s -L --output sysreptor.tar.gz https://github.com/syslifters/sysreptor/releases/latest/download/setup.tar.gz
tar xzf sysreptor.tar.gz

log "Creating SysReptor volumes..."
# Create volumes for SysReptor data
docker volume create sysreptor-db-data
docker volume create sysreptor-app-data

log "✅ SysReptor setup completed"
log "Note: SysReptor configuration (app.env) is generated automatically during build process"
log "Note: SysReptor superuser will be created automatically after services are running"
