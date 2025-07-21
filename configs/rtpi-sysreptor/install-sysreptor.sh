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
log "SysReptor services will be started via docker-compose by the main build script"

# SysReptor User Account Setup
echo "============================================"
echo "🔐 SysReptor User Account Configuration"
echo "============================================"

# Get current system username
current_user=$(whoami)

# Check if running in automated mode (non-interactive)
if [ -t 0 ]; then
    # Interactive mode
    echo "Choose username option for SysReptor:"
    echo "1. Use current system username ($current_user)"
    echo "2. Create custom username"
    echo "3. Use default (rtpi-admin)"
    echo ""
    read -p "Enter your choice (1-3) [default: 1]: " choice
    
    case $choice in
        1|"")
            username="$current_user"
            echo "✓ Using current system username: $username"
            ;;
        2)
            while true; do
                read -p "Enter custom username: " custom_username
                # Validate username (alphanumeric, underscore, hyphen only)
                if [[ "$custom_username" =~ ^[a-zA-Z0-9_-]+$ ]] && [[ ${#custom_username} -ge 3 ]]; then
                    username="$custom_username"
                    echo "✓ Using custom username: $username"
                    break
                else
                    echo "❌ Username must be at least 3 characters and contain only letters, numbers, underscores, or hyphens"
                fi
            done
            ;;
        3)
            username="rtpi-admin"
            echo "✓ Using default username: $username"
            ;;
        *)
            echo "Invalid choice, using current system username: $current_user"
            username="$current_user"
            ;;
    esac
else
    # Non-interactive mode (automated installation)
    username="$current_user"
    echo "ℹ️  Running in automated mode - using current system username: $username"
fi

echo ""
echo "Creating SysReptor superuser account..."
echo "Username: $username"
echo "Note: You will be prompted to enter email and password"
echo ""

# Wait for services to be ready
echo "Waiting for SysReptor services to be ready..."
sleep 10

# Attempt to create superuser with error handling
max_attempts=3
attempt=1

while [ $attempt -le $max_attempts ]; do
    echo "Attempt $attempt of $max_attempts..."
    
    if docker compose exec app python3 manage.py createsuperuser --username "$username"; then
        echo "✅ SysReptor superuser '$username' created successfully!"
        echo ""
        echo "🌐 You can now access SysReptor at: http://localhost:7777"
        echo "🔑 Login with username: $username"
        break
    else
        echo "❌ Failed to create superuser (attempt $attempt/$max_attempts)"
        
        if [ $attempt -eq $max_attempts ]; then
            echo "❌ All attempts failed. You can create the superuser manually later:"
            echo "   docker compose exec app python3 manage.py createsuperuser --username $username"
            echo ""
        else
            echo "Retrying in 5 seconds..."
            sleep 5
        fi
        
        attempt=$((attempt + 1))
    fi
done
