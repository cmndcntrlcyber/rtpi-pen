#!/bin/bash
# RTPI-PEN Sequential Startup Script
# Starts services in proper dependency order with health checks

set -e

echo "🚀 Starting Sequential Startup for RTPI-PEN..."

# Function to wait for container to be healthy
wait_for_container_health() {
    local container_name="$1"
    local max_wait="$2"
    local check_interval=5
    local elapsed=0
    
    echo "⏳ Waiting for $container_name to be healthy..."
    
    while [ $elapsed -lt $max_wait ]; do
        if sudo docker ps --filter "name=$container_name" --filter "status=running" --format "{{.Names}}" | grep -q "^${container_name}$"; then
            # Check if container has health check
            local health_status=$(sudo docker inspect "$container_name" --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
            
            if [ "$health_status" = "healthy" ]; then
                echo "✅ $container_name is healthy"
                return 0
            elif [ "$health_status" = "none" ]; then
                # No health check defined, check if container is running
                echo "✅ $container_name is running (no health check)"
                return 0
            elif [ "$health_status" = "unhealthy" ]; then
                echo "❌ $container_name is unhealthy"
                return 1
            else
                echo "⏳ $container_name health status: $health_status"
            fi
        else
            echo "⏳ $container_name is not running yet"
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    echo "❌ $container_name did not become healthy within ${max_wait}s"
    return 1
}

# Function to start a container and wait for it to be healthy
start_and_wait() {
    local container_name="$1"
    local max_wait="${2:-180}"
    
    echo "🔄 Starting $container_name..."
    
    # Start the container
    if sudo docker compose up -d "$container_name"; then
        echo "✅ $container_name started"
        
        # Wait for it to be healthy
        if wait_for_container_health "$container_name" "$max_wait"; then
            echo "✅ $container_name is ready"
            return 0
        else
            echo "❌ $container_name failed to become healthy"
            return 1
        fi
    else
        echo "❌ Failed to start $container_name"
        return 1
    fi
}

# Function to check if service is responding
check_service_endpoint() {
    local service_name="$1"
    local endpoint="$2"
    local max_attempts=10
    local attempt=1
    
    echo "🔍 Checking $service_name endpoint: $endpoint"
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "$endpoint" > /dev/null 2>&1; then
            echo "✅ $service_name endpoint is responding"
            return 0
        else
            echo "⏳ $service_name endpoint not ready (attempt $attempt/$max_attempts)"
            sleep 5
            ((attempt++))
        fi
    done
    
    echo "❌ $service_name endpoint did not respond after $max_attempts attempts"
    return 1
}

# Function to show container logs for debugging
show_container_logs() {
    local container_name="$1"
    local lines="${2:-20}"
    
    echo "📋 Last $lines lines of $container_name logs:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    sudo docker logs --tail="$lines" "$container_name" 2>&1 || echo "Could not get logs for $container_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to handle startup failures
handle_startup_failure() {
    local container_name="$1"
    local phase="$2"
    
    echo "❌ Startup failed for $container_name in phase: $phase"
    
    # Show container logs
    show_container_logs "$container_name" 50
    
    # Try to restart once
    echo "🔄 Attempting single restart of $container_name..."
    sudo docker restart "$container_name" || true
    
    # Wait a bit and check again
    sleep 10
    if wait_for_container_health "$container_name" 60; then
        echo "✅ $container_name recovered after restart"
        return 0
    else
        echo "❌ $container_name failed to recover"
        return 1
    fi
}

# Function to start phase 1 - Core Infrastructure
start_phase1_infrastructure() {
    echo "🏗️ Phase 1: Starting Core Infrastructure..."
    
    # Start shared database
    echo "📊 Starting shared database service..."
    
    if ! start_and_wait "rtpi-database" 120; then
        handle_startup_failure "rtpi-database" "Phase 1 - Shared Database"
    fi
    
    # Start cache services
    echo "🗄️ Starting cache services..."
    
    if ! start_and_wait "rtpi-cache" 60; then
        handle_startup_failure "rtpi-cache" "Phase 1 - Cache"
    fi
    
    if ! start_and_wait "sysreptor-redis" 60; then
        handle_startup_failure "sysreptor-redis" "Phase 1 - SysReptor Redis"
    fi
    
    if ! start_and_wait "kasm_redis" 60; then
        handle_startup_failure "kasm_redis" "Phase 1 - Kasm Redis"
    fi
    
    echo "✅ Phase 1 completed - Core Infrastructure ready"
}

# Function to start phase 2 - Self-Healing Service
start_phase2_healer() {
    echo "🏥 Phase 2: Starting Self-Healing Service..."
    
    # Start the healer service
    if ! start_and_wait "rtpi-healer" 180; then
        handle_startup_failure "rtpi-healer" "Phase 2 - Healer"
    fi
    
    # Check healer API endpoint
    if ! check_service_endpoint "RTPI Healer" "http://localhost:8888/health"; then
        echo "⚠️ Healer endpoint not responding, but continuing..."
    fi
    
    echo "✅ Phase 2 completed - Self-Healing Service ready"
}

# Function to start phase 3 - Application Services
start_phase3_applications() {
    echo "📱 Phase 3: Starting Application Services..."
    
    # Start SysReptor
    echo "📊 Starting SysReptor..."
    if ! start_and_wait "sysreptor-app" 180; then
        handle_startup_failure "sysreptor-app" "Phase 3 - SysReptor"
    fi
    
    if ! start_and_wait "sysreptor-caddy" 60; then
        handle_startup_failure "sysreptor-caddy" "Phase 3 - SysReptor Caddy"
    fi
    
    # Start Kasm services in correct order
    echo "🖥️ Starting Kasm services..."
    
    if ! start_and_wait "kasm_api" 120; then
        handle_startup_failure "kasm_api" "Phase 3 - Kasm API"
    fi
    
    if ! start_and_wait "kasm_manager" 120; then
        handle_startup_failure "kasm_manager" "Phase 3 - Kasm Manager"
    fi
    
    if ! start_and_wait "kasm_share" 120; then
        handle_startup_failure "kasm_share" "Phase 3 - Kasm Share"
    fi
    
    if ! start_and_wait "kasm_guac" 120; then
        handle_startup_failure "kasm_guac" "Phase 3 - Kasm Guacamole"
    fi
    
    if ! start_and_wait "kasm_agent" 120; then
        handle_startup_failure "kasm_agent" "Phase 3 - Kasm Agent"
    fi
    
    if ! start_and_wait "kasm_proxy" 120; then
        handle_startup_failure "kasm_proxy" "Phase 3 - Kasm Proxy"
    fi
    
    # Start Empire
    echo "👑 Starting Empire..."
    if ! start_and_wait "ps-empire" 120; then
        handle_startup_failure "ps-empire" "Phase 3 - Empire"
    fi
    
    # Start orchestrator
    echo "🎛️ Starting orchestrator..."
    if ! start_and_wait "rtpi-orchestrator" 120; then
        handle_startup_failure "rtpi-orchestrator" "Phase 3 - Orchestrator"
    fi
    
    echo "✅ Phase 3 completed - Application Services ready"
}

# Function to start phase 4 - Supporting Services
start_phase4_supporting() {
    echo "🔧 Phase 4: Starting Supporting Services..."
    
    # Start proxy services
    if ! start_and_wait "rtpi-proxy" 60; then
        handle_startup_failure "rtpi-proxy" "Phase 4 - Proxy"
    fi
    
    # Start tools
    if ! start_and_wait "rtpi-tools" 60; then
        handle_startup_failure "rtpi-tools" "Phase 4 - Tools"
    fi
    
    # Start utility services
    if ! start_and_wait "registry" 60; then
        handle_startup_failure "registry" "Phase 4 - Registry"
    fi
    
    if ! start_and_wait "node" 60; then
        handle_startup_failure "node" "Phase 4 - Node"
    fi
    
    echo "✅ Phase 4 completed - Supporting Services ready"
}

# Function to verify all services are running
verify_all_services() {
    echo "🔍 Verifying all services are running..."
    
    local failed_services=()
    
    # List of critical services to check
    local critical_services=(
        "rtpi-database"
        "rtpi-cache"
        "rtpi-healer"
        "kasm_redis"
        "kasm_api"
        "kasm_manager"
        "kasm_agent"
        "kasm_proxy"
        "sysreptor-app"
        "sysreptor-redis"
        "ps-empire"
        "rtpi-orchestrator"
    )
    
    echo "📋 Checking critical services..."
    for service in "${critical_services[@]}"; do
        if sudo docker ps --filter "name=$service" --filter "status=running" --format "{{.Names}}" | grep -q "^${service}$"; then
            echo "✅ $service is running"
        else
            echo "❌ $service is not running"
            failed_services+=("$service")
        fi
    done
    
    # Check service endpoints
    echo "🌐 Checking service endpoints..."
    
    # Check healer endpoint
    if check_service_endpoint "RTPI Healer" "http://localhost:8888/health"; then
        echo "✅ Healer API responding"
    else
        echo "⚠️ Healer API not responding"
    fi
    
    # Check Kasm proxy
    if check_service_endpoint "Kasm Proxy" "https://localhost:8443" --insecure; then
        echo "✅ Kasm Proxy responding"
    else
        echo "⚠️ Kasm Proxy not responding"
    fi
    
    # Check SysReptor
    if check_service_endpoint "SysReptor" "http://localhost:7777"; then
        echo "✅ SysReptor responding"
    else
        echo "⚠️ SysReptor not responding"
    fi
    
    # Check Empire
    if check_service_endpoint "Empire" "http://localhost:1337"; then
        echo "✅ Empire responding"
    else
        echo "⚠️ Empire not responding"
    fi
    
    # Check Orchestrator
    if check_service_endpoint "Orchestrator" "http://localhost:9444"; then
        echo "✅ Orchestrator responding"
    else
        echo "⚠️ Orchestrator not responding"
    fi
    
    if [ ${#failed_services[@]} -eq 0 ]; then
        echo "✅ All critical services are running"
        return 0
    else
        echo "❌ Failed services: ${failed_services[*]}"
        return 1
    fi
}

# Function to show final status
show_final_status() {
    echo "📊 Final System Status:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -20
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    echo "🌐 Service Access Points:"
    echo "• Kasm Workspaces: https://localhost:8443"
    echo "• SysReptor: http://localhost:7777"
    echo "• Empire C2: http://localhost:1337"
    echo "• Orchestrator: http://localhost:9444"
    echo "• Healer API: http://localhost:8888/health"
    echo "• Main Proxy: https://localhost:443"
    echo ""
    echo "🔍 Monitor logs with: sudo docker logs <container_name>"
    echo "📊 System health: sudo docker ps"
}

# Function to create startup recovery script
create_recovery_script() {
    echo "📝 Creating recovery script for future use..."
    
    cat > "repair-scripts/restart-failed-services.sh" << 'EOF'
#!/bin/bash
# Quick restart script for failed services
echo "🔄 Restarting failed services..."

# Get list of non-running services
failed_services=$(sudo docker ps -a --filter "status=exited" --format "{{.Names}}")

if [ -n "$failed_services" ]; then
    echo "Found failed services: $failed_services"
    for service in $failed_services; do
        echo "Restarting $service..."
        sudo docker restart "$service"
        sleep 5
    done
else
    echo "No failed services found"
fi

# Show current status
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
EOF
    
    chmod +x "repair-scripts/restart-failed-services.sh"
    echo "✅ Recovery script created at repair-scripts/restart-failed-services.sh"
}

# Main execution
main() {
    echo "Starting sequential startup at $(date)"
    
    # Check if running as root or with sudo access
    if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
        echo "❌ This script requires sudo privileges"
        exit 1
    fi
    
    # Check if docker compose is available
    if ! docker compose version &> /dev/null; then
        echo "❌ docker compose plugin is required but not available"
        exit 1
    fi
    
    # Check if we're in the right directory
    if [ ! -f "docker-compose.yml" ]; then
        echo "❌ docker-compose.yml not found. Are you in the right directory?"
        exit 1
    fi
    
    # Build images first if needed
    echo "🏗️ Building images..."
    sudo docker compose build --no-cache || echo "⚠️ Build failed, continuing with existing images"
    
    # Start services in phases
    start_phase1_infrastructure
    sleep 10
    
    start_phase2_healer
    sleep 10
    
    start_phase3_applications
    sleep 10
    
    start_phase4_supporting
    sleep 10
    
    # Verify all services
    if verify_all_services; then
        echo "✅ Sequential startup completed successfully!"
        show_final_status
        create_recovery_script
        echo "📝 Next step: Run health-validator.sh to perform comprehensive health checks"
    else
        echo "❌ Sequential startup completed with some failures"
        show_final_status
        echo "🔧 Check the failed services above and run repair-scripts/restart-failed-services.sh"
        exit 1
    fi
}

# Execute main function
main "$@"
