#!/bin/bash
# RTPI-PEN Health Validation Script
# Comprehensive health checks for all services

set -e

echo "🔍 Starting Health Validation for RTPI-PEN..."

# Function to check container health
check_container_health() {
    local container_name="$1"
    local expected_status="running"
    
    echo "🔍 Checking $container_name..."
    
    # Check if container exists
    if ! sudo docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$"; then
        echo "❌ Container $container_name does not exist"
        return 1
    fi
    
    # Check container status
    local status=$(sudo docker ps -a --filter "name=$container_name" --format "{{.Status}}")
    local state=$(sudo docker ps -a --filter "name=$container_name" --format "{{.State}}")
    
    if [ "$state" != "running" ]; then
        echo "❌ $container_name is not running (Status: $status)"
        return 1
    fi
    
    # Check health status if available
    local health_status=$(sudo docker inspect "$container_name" --format='{{.State.Health.Status}}' 2>/dev/null || echo "none")
    
    if [ "$health_status" = "healthy" ]; then
        echo "✅ $container_name is running and healthy"
        return 0
    elif [ "$health_status" = "unhealthy" ]; then
        echo "❌ $container_name is running but unhealthy"
        return 1
    elif [ "$health_status" = "none" ]; then
        echo "✅ $container_name is running (no health check defined)"
        return 0
    else
        echo "⚠️ $container_name is running but health status is: $health_status"
        return 0
    fi
}

# Function to check service endpoint
check_endpoint() {
    local service_name="$1"
    local endpoint="$2"
    local expected_response="$3"
    local timeout="${4:-10}"
    
    echo "🌐 Checking $service_name endpoint: $endpoint"
    
    local response=$(curl -s -m "$timeout" "$endpoint" 2>/dev/null || echo "FAILED")
    
    if [ "$response" = "FAILED" ]; then
        echo "❌ $service_name endpoint not responding"
        return 1
    elif [ -n "$expected_response" ] && [[ "$response" != *"$expected_response"* ]]; then
        echo "❌ $service_name endpoint returned unexpected response"
        return 1
    else
        echo "✅ $service_name endpoint is responding"
        return 0
    fi
}

# Function to check database connectivity
check_database_connectivity() {
    local db_name="$1"
    local container_name="$2"
    local user="$3"
    local database="$4"
    
    echo "🗄️ Checking $db_name database connectivity..."
    
    if sudo docker exec "$container_name" pg_isready -U "$user" -d "$database" -h localhost >/dev/null 2>&1; then
        echo "✅ $db_name database is accessible"
        return 0
    else
        echo "❌ $db_name database is not accessible"
        return 1
    fi
}

# Function to check Redis connectivity
check_redis_connectivity() {
    local redis_name="$1"
    local container_name="$2"
    local password="$3"
    
    echo "🔄 Checking $redis_name Redis connectivity..."
    
    if [ -n "$password" ]; then
        if sudo docker exec "$container_name" redis-cli -a "$password" ping >/dev/null 2>&1; then
            echo "✅ $redis_name Redis is accessible"
            return 0
        else
            echo "❌ $redis_name Redis is not accessible"
            return 1
        fi
    else
        if sudo docker exec "$container_name" redis-cli ping >/dev/null 2>&1; then
            echo "✅ $redis_name Redis is accessible"
            return 0
        else
            echo "❌ $redis_name Redis is not accessible"
            return 1
        fi
    fi
}

# Function to check Docker network connectivity
check_network_connectivity() {
    echo "🌐 Checking Docker network connectivity..."
    
    local networks=(
        "rtpi_frontend"
        "rtpi_backend"
        "rtpi_database"
        "kasm_default_network"
        "sysreptor_default"
    )
    
    for network in "${networks[@]}"; do
        if sudo docker network ls --format "{{.Name}}" | grep -q "^${network}$"; then
            echo "✅ Network $network exists"
        else
            echo "❌ Network $network does not exist"
            return 1
        fi
    done
    
    return 0
}

# Function to check volume mounts
check_volume_mounts() {
    echo "💾 Checking volume mounts..."
    
    local critical_volumes=(
        "rtpi_database_data"
        "rtpi_cache_data"
        "kasm_db_1.15.0"
        "sysreptor-app-data"
        "sysreptor-db-data"
        "empire_data"
    )
    
    for volume in "${critical_volumes[@]}"; do
        if sudo docker volume ls --format "{{.Name}}" | grep -q "^${volume}$"; then
            echo "✅ Volume $volume exists"
        else
            echo "❌ Volume $volume does not exist"
            return 1
        fi
    done
    
    return 0
}

# Function to check system resources
check_system_resources() {
    echo "💻 Checking system resources..."
    
    # Check disk space
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        echo "❌ Disk usage is critical: ${disk_usage}%"
        return 1
    elif [ "$disk_usage" -gt 80 ]; then
        echo "⚠️ Disk usage is high: ${disk_usage}%"
    else
        echo "✅ Disk usage is normal: ${disk_usage}%"
    fi
    
    # Check memory usage
    local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [ "$mem_usage" -gt 90 ]; then
        echo "❌ Memory usage is critical: ${mem_usage}%"
        return 1
    elif [ "$mem_usage" -gt 80 ]; then
        echo "⚠️ Memory usage is high: ${mem_usage}%"
    else
        echo "✅ Memory usage is normal: ${mem_usage}%"
    fi
    
    # Check Docker daemon
    if sudo systemctl is-active --quiet docker; then
        echo "✅ Docker daemon is running"
    else
        echo "❌ Docker daemon is not running"
        return 1
    fi
    
    return 0
}

# Function to check log files
check_log_files() {
    echo "📋 Checking log files..."
    
    local log_dirs=(
        "/var/log/rtpi-healer"
        "/var/log/kasm"
        "/opt/kasm/1.15.0/log"
    )
    
    for log_dir in "${log_dirs[@]}"; do
        if [ -d "$log_dir" ]; then
            local log_count=$(find "$log_dir" -name "*.log" -type f 2>/dev/null | wc -l)
            if [ "$log_count" -gt 0 ]; then
                echo "✅ Log directory $log_dir has $log_count log files"
            else
                echo "⚠️ Log directory $log_dir has no log files"
            fi
        else
            echo "❌ Log directory $log_dir does not exist"
        fi
    done
    
    return 0
}

# Function to check file permissions
check_file_permissions() {
    echo "🔒 Checking file permissions..."
    
    local critical_paths=(
        "/opt/kasm/1.15.0"
        "/opt/empire/data"
        "/opt/rtpi-orchestrator/data"
        "/var/log/rtpi-healer"
        "/data/rtpi-healer"
    )
    
    for path in "${critical_paths[@]}"; do
        if [ -d "$path" ]; then
            local owner=$(stat -c "%U:%G" "$path" 2>/dev/null || echo "unknown")
            if [ "$owner" = "1000:1000" ] || [ "$owner" = "cmndcntrl:cmndcntrl" ]; then
                echo "✅ $path has correct ownership: $owner"
            else
                echo "❌ $path has incorrect ownership: $owner (expected 1000:1000)"
            fi
        else
            echo "❌ Critical path $path does not exist"
        fi
    done
    
    return 0
}

# Function to perform comprehensive health checks
perform_comprehensive_checks() {
    echo "🔍 Performing comprehensive health checks..."
    
    local failures=0
    
    # Phase 1: Container Health Checks
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Phase 1: Container Health Checks"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local containers=(
        "rtpi-database"
        "rtpi-cache"
        "rtpi-healer"
        "rtpi-orchestrator"
        "kasm_db"
        "kasm_redis"
        "kasm_api"
        "kasm_manager"
        "kasm_agent"
        "kasm_share"
        "kasm_guac"
        "kasm_proxy"
        "sysreptor-app"
        "sysreptor-db"
        "sysreptor-redis"
        "sysreptor-caddy"
        "ps-empire"
        "rtpi-proxy"
        "rtpi-tools"
        "registry"
        "node"
    )
    
    for container in "${containers[@]}"; do
        if ! check_container_health "$container"; then
            ((failures++))
        fi
    done
    
    # Phase 2: Database Connectivity
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Phase 2: Database Connectivity"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if ! check_database_connectivity "RTPI" "rtpi-database" "rtpi" "rtpi_main"; then
        ((failures++))
    fi
    
    if ! check_database_connectivity "Kasm" "kasm_db" "kasmapp" "kasm"; then
        ((failures++))
    fi
    
    if ! check_database_connectivity "SysReptor" "sysreptor-db" "sysreptor" "sysreptor"; then
        ((failures++))
    fi
    
    # Phase 3: Redis Connectivity
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Phase 3: Redis Connectivity"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if ! check_redis_connectivity "RTPI Cache" "rtpi-cache" ""; then
        ((failures++))
    fi
    
    if ! check_redis_connectivity "Kasm" "kasm_redis" "CwoZWGpBk5PZ3zD79fIK"; then
        ((failures++))
    fi
    
    if ! check_redis_connectivity "SysReptor" "sysreptor-redis" "sysreptorredispassword"; then
        ((failures++))
    fi
    
    # Phase 4: Service Endpoints
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Phase 4: Service Endpoints"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if ! check_endpoint "RTPI Healer" "http://localhost:8888/health" ""; then
        ((failures++))
    fi
    
    if ! check_endpoint "Kasm Proxy" "https://localhost:8443" "" 15; then
        ((failures++))
    fi
    
    if ! check_endpoint "SysReptor" "http://localhost:7777" "" 15; then
        ((failures++))
    fi
    
    if ! check_endpoint "Empire" "http://localhost:1337" "" 15; then
        ((failures++))
    fi
    
    if ! check_endpoint "Orchestrator" "http://localhost:9444" "" 15; then
        ((failures++))
    fi
    
    # Phase 5: Infrastructure Checks
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Phase 5: Infrastructure Checks"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if ! check_network_connectivity; then
        ((failures++))
    fi
    
    if ! check_volume_mounts; then
        ((failures++))
    fi
    
    if ! check_system_resources; then
        ((failures++))
    fi
    
    if ! check_log_files; then
        ((failures++))
    fi
    
    if ! check_file_permissions; then
        ((failures++))
    fi
    
    return $failures
}

# Function to generate health report
generate_health_report() {
    local failures="$1"
    local report_file="/tmp/rtpi-pen-health-report-$(date +%Y%m%d_%H%M%S).txt"
    
    echo "📊 Generating health report..."
    
    cat > "$report_file" << EOF
# RTPI-PEN Health Report
Generated: $(date)

## System Status
- Total Failures: $failures
- Overall Health: $([ $failures -eq 0 ] && echo "HEALTHY" || echo "UNHEALTHY")

## Container Status
EOF
    
    sudo docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" >> "$report_file"
    
    cat >> "$report_file" << EOF

## System Resources
$(free -h)

## Disk Usage
$(df -h)

## Network Information
$(sudo docker network ls)

## Volume Information
$(sudo docker volume ls)

## Docker System Information
$(sudo docker system df)
EOF
    
    echo "📄 Health report saved to: $report_file"
    
    # Show summary
    echo "📋 Health Check Summary:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ $failures -eq 0 ]; then
        echo "✅ All health checks passed - System is HEALTHY"
    else
        echo "❌ $failures health checks failed - System is UNHEALTHY"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    return $failures
}

# Function to suggest fixes for common issues
suggest_fixes() {
    echo "🔧 Suggested fixes for common issues:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "• Container not running: sudo docker restart <container_name>"
    echo "• Database connectivity: Check if database container is running and accessible"
    echo "• Redis connectivity: Verify Redis password and container status"
    echo "• Endpoint not responding: Check if service is running and port is accessible"
    echo "• Permission issues: Run repair-scripts/manual-init.sh to fix permissions"
    echo "• Network issues: Restart Docker daemon or recreate networks"
    echo "• Volume issues: Check if volumes exist and are properly mounted"
    echo "• High resource usage: Consider scaling down services or increasing resources"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "💡 To restart failed services: ./repair-scripts/restart-failed-services.sh"
    echo "🔄 To perform emergency repair: ./repair-scripts/emergency-repair.sh"
    echo "🔧 To reinitialize system: ./repair-scripts/manual-init.sh"
}

# Main execution
main() {
    echo "Starting health validation at $(date)"
    
    # Check if running as root or with sudo access
    if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
        echo "❌ This script requires sudo privileges"
        exit 1
    fi
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        echo "❌ Docker is required but not installed"
        exit 1
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        echo "❌ curl is required but not installed"
        exit 1
    fi
    
    # Perform comprehensive health checks
    if perform_comprehensive_checks; then
        failures=$?
    else
        failures=$?
    fi
    
    # Generate health report
    generate_health_report $failures
    
    # Suggest fixes if there are failures
    if [ $failures -gt 0 ]; then
        suggest_fixes
    fi
    
    echo "✅ Health validation completed at $(date)"
    echo "📊 Total failures: $failures"
    
    # Exit with appropriate code
    exit $failures
}

# Execute main function
main "$@"
