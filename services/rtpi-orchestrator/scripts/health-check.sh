#!/bin/bash
set -e

# RTPI-PEN Service Health Monitoring
# Comprehensive health checks for all RTPI-PEN services

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/rtpi/health-check.log"
STATUS_FILE="/var/log/rtpi/health-status.json"
ALERT_THRESHOLD=3  # Number of consecutive failures before alert

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Health check results
declare -A health_results
declare -A failure_counts

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
}

# Success message
success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
    log "SUCCESS: $1"
}

# Warning message
warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
    log "WARNING: $1"
}

# Info message
info() {
    echo -e "${BLUE}INFO: $1${NC}"
    log "INFO: $1"
}

# Check if Docker is available
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed or not in PATH"
        return 1
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running or not accessible"
        return 1
    fi
    
    return 0
}

# Check if container exists and is running
check_container_basic() {
    local container_name="$1"
    
    if ! docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"; then
        return 1
    fi
    
    return 0
}

# Get container health status
get_container_health() {
    local container_name="$1"
    
    if ! docker ps -a --format "table {{.Names}}" | grep -q "^${container_name}$"; then
        echo "not_found"
        return
    fi
    
    local health_status
    health_status=$(docker inspect "$container_name" --format "{{.State.Health.Status}}" 2>/dev/null || echo "no_healthcheck")
    
    if [[ "$health_status" == "<no value>" ]]; then
        echo "no_healthcheck"
    else
        echo "$health_status"
    fi
}

# Test TCP connection
test_tcp_connection() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"
    
    if timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port"; then
        return 0
    else
        return 1
    fi
}

# Test HTTP endpoint
test_http_endpoint() {
    local url="$1"
    local expected_status="${2:-200}"
    local timeout="${3:-10}"
    
    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$timeout" "$url" 2>/dev/null || echo "000")
    
    if [[ "$response_code" == "$expected_status" ]]; then
        return 0
    else
        return 1
    fi
}

# Test database connection
test_database_connection() {
    local host="$1"
    local port="$2"
    local database="$3"
    local username="$4"
    local timeout="${5:-10}"
    
    if timeout "$timeout" docker exec rtpi-database pg_isready -h "$host" -p "$port" -U "$username" -d "$database" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Test Redis connection
test_redis_connection() {
    local host="$1"
    local port="$2"
    local timeout="${3:-10}"
    
    if timeout "$timeout" docker exec rtpi-cache redis-cli -h "$host" -p "$port" ping | grep -q "PONG"; then
        return 0
    else
        return 1
    fi
}

# Health check for rtpi-database
check_rtpi_database() {
    local service_name="rtpi-database"
    info "Checking $service_name..."
    
    # Check container is running
    if ! check_container_basic "$service_name"; then
        health_results["$service_name"]="CRITICAL: Container not running"
        return 1
    fi
    
    # Check PostgreSQL is ready
    if ! test_database_connection "localhost" "5432" "postgres" "postgres" 10; then
        health_results["$service_name"]="CRITICAL: PostgreSQL not responding"
        return 1
    fi
    
    # Check disk space
    local disk_usage
    disk_usage=$(docker exec "$service_name" df -h /var/lib/postgresql/data 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [[ "$disk_usage" -gt 90 ]]; then
        health_results["$service_name"]="WARNING: High disk usage (${disk_usage}%)"
        return 1
    fi
    
    # Check connection count
    local connection_count
    connection_count=$(docker exec "$service_name" psql -U postgres -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ')
    
    if [[ "$connection_count" -gt 80 ]]; then
        health_results["$service_name"]="WARNING: High connection count ($connection_count)"
        return 1
    fi
    
    health_results["$service_name"]="OK: All checks passed"
    return 0
}

# Health check for rtpi-cache
check_rtpi_cache() {
    local service_name="rtpi-cache"
    info "Checking $service_name..."
    
    # Check container is running
    if ! check_container_basic "$service_name"; then
        health_results["$service_name"]="CRITICAL: Container not running"
        return 1
    fi
    
    # Check Redis is responding
    if ! test_redis_connection "localhost" "6379" 10; then
        health_results["$service_name"]="CRITICAL: Redis not responding"
        return 1
    fi
    
    # Check Redis memory usage
    local memory_usage
    memory_usage=$(docker exec "$service_name" redis-cli info memory | grep used_memory_human | cut -d: -f2 | tr -d '\r')
    
    # Check Redis connected clients
    local connected_clients
    connected_clients=$(docker exec "$service_name" redis-cli info clients | grep connected_clients | cut -d: -f2 | tr -d '\r')
    
    if [[ "$connected_clients" -gt 100 ]]; then
        health_results["$service_name"]="WARNING: High client count ($connected_clients)"
        return 1
    fi
    
    health_results["$service_name"]="OK: All checks passed (Memory: $memory_usage, Clients: $connected_clients)"
    return 0
}

# Health check for rtpi-proxy
check_rtpi_proxy() {
    local service_name="rtpi-proxy"
    info "Checking $service_name..."
    
    # Check container is running
    if ! check_container_basic "$service_name"; then
        health_results["$service_name"]="CRITICAL: Container not running"
        return 1
    fi
    
    # Check nginx configuration
    if ! docker exec "$service_name" nginx -t &>/dev/null; then
        health_results["$service_name"]="CRITICAL: Nginx configuration invalid"
        return 1
    fi
    
    # Check HTTP endpoints
    if ! test_http_endpoint "http://localhost:80" "200" 10; then
        health_results["$service_name"]="CRITICAL: HTTP endpoint not responding"
        return 1
    fi
    
    # Check HTTPS endpoints
    if ! test_http_endpoint "https://localhost:443" "200" 10; then
        health_results["$service_name"]="WARNING: HTTPS endpoint not responding"
        # Don't return 1 here as HTTP might be sufficient
    fi
    
    health_results["$service_name"]="OK: All checks passed"
    return 0
}

# Health check for rtpi-healer
check_rtpi_healer() {
    local service_name="rtpi-healer"
    info "Checking $service_name..."
    
    # Check container is running
    if ! check_container_basic "$service_name"; then
        health_results["$service_name"]="CRITICAL: Container not running"
        return 1
    fi
    
    # Check healer API endpoint
    if ! test_http_endpoint "http://localhost:8888/health" "200" 10; then
        health_results["$service_name"]="CRITICAL: Healer API not responding"
        return 1
    fi
    
    # Check healer log for recent activity
    local last_activity
    last_activity=$(docker logs "$service_name" --since "5m" 2>/dev/null | wc -l)
    
    if [[ "$last_activity" -eq 0 ]]; then
        health_results["$service_name"]="WARNING: No recent activity in logs"
        return 1
    fi
    
    health_results["$service_name"]="OK: All checks passed"
    return 0
}

# Health check for rtpi-orchestrator
check_rtpi_orchestrator() {
    local service_name="rtpi-orchestrator"
    info "Checking $service_name..."
    
    # Check container is running
    if ! check_container_basic "$service_name"; then
        health_results["$service_name"]="CRITICAL: Container not running"
        return 1
    fi
    
    # Check Portainer is accessible
    if ! test_http_endpoint "http://localhost:9000" "200" 10; then
        health_results["$service_name"]="CRITICAL: Portainer not responding"
        return 1
    fi
    
    # Check orchestrator API
    if ! test_http_endpoint "http://localhost:8080/health" "200" 10; then
        health_results["$service_name"]="WARNING: Orchestrator API not responding"
        # Don't return 1 as Portainer might be sufficient
    fi
    
    health_results["$service_name"]="OK: All checks passed"
    return 0
}

# Health check for rtpi-tools
check_rtpi_tools() {
    local service_name="rtpi-tools"
    info "Checking $service_name..."
    
    # Check container is running
    if ! check_container_basic "$service_name"; then
        health_results["$service_name"]="CRITICAL: Container not running"
        return 1
    fi
    
    # Check if essential tools are available
    if ! docker exec "$service_name" which nmap &>/dev/null; then
        health_results["$service_name"]="WARNING: Essential tools missing"
        return 1
    fi
    
    health_results["$service_name"]="OK: All checks passed"
    return 0
}

# Health check for sysreptor-db
check_sysreptor_db() {
    local service_name="sysreptor-db"
    info "Checking $service_name..."
    
    # Check container is running
    if ! check_container_basic "$service_name"; then
        health_results["$service_name"]="CRITICAL: Container not running"
        return 1
    fi
    
    # Check PostgreSQL is ready
    if ! docker exec "$service_name" pg_isready -U sysreptor -d sysreptor &>/dev/null; then
        health_results["$service_name"]="CRITICAL: PostgreSQL not responding"
        return 1
    fi
    
    health_results["$service_name"]="OK: All checks passed"
    return 0
}

# Health check for sysreptor-app
check_sysreptor_app() {
    local service_name="sysreptor-app"
    info "Checking $service_name..."
    
    # Check container is running
    if ! check_container_basic "$service_name"; then
        health_results["$service_name"]="CRITICAL: Container not running"
        return 1
    fi
    
    # Check application endpoint
    if ! test_http_endpoint "http://localhost:8000" "200" 10; then
        health_results["$service_name"]="CRITICAL: SysReptor app not responding"
        return 1
    fi
    
    # Check database connectivity
    if ! test_tcp_connection "sysreptor-db" "5432" 5; then
        health_results["$service_name"]="CRITICAL: Cannot connect to database"
        return 1
    fi
    
    health_results["$service_name"]="OK: All checks passed"
    return 0
}

# System resource checks
check_system_resources() {
    info "Checking system resources..."
    
    # Check disk space
    local disk_usage
    disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [[ "$disk_usage" -gt 90 ]]; then
        health_results["system_disk"]="CRITICAL: High disk usage (${disk_usage}%)"
    elif [[ "$disk_usage" -gt 80 ]]; then
        health_results["system_disk"]="WARNING: High disk usage (${disk_usage}%)"
    else
        health_results["system_disk"]="OK: Disk usage normal (${disk_usage}%)"
    fi
    
    # Check memory usage
    local memory_usage
    memory_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    
    if [[ "$memory_usage" -gt 90 ]]; then
        health_results["system_memory"]="CRITICAL: High memory usage (${memory_usage}%)"
    elif [[ "$memory_usage" -gt 80 ]]; then
        health_results["system_memory"]="WARNING: High memory usage (${memory_usage}%)"
    else
        health_results["system_memory"]="OK: Memory usage normal (${memory_usage}%)"
    fi
    
    # Check CPU load
    local cpu_load
    cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    local cpu_cores
    cpu_cores=$(nproc)
    
    local cpu_usage
    cpu_usage=$(echo "scale=2; $cpu_load / $cpu_cores * 100" | bc)
    
    if (( $(echo "$cpu_usage > 90" | bc -l) )); then
        health_results["system_cpu"]="CRITICAL: High CPU load (${cpu_usage}%)"
    elif (( $(echo "$cpu_usage > 70" | bc -l) )); then
        health_results["system_cpu"]="WARNING: High CPU load (${cpu_usage}%)"
    else
        health_results["system_cpu"]="OK: CPU load normal (${cpu_usage}%)"
    fi
}

# Check Docker system
check_docker_system() {
    info "Checking Docker system..."
    
    # Check Docker daemon health
    if ! docker system info &>/dev/null; then
        health_results["docker_daemon"]="CRITICAL: Docker daemon not responding"
        return 1
    fi
    
    # Check Docker disk usage
    local docker_disk_usage
    docker_disk_usage=$(docker system df --format "table {{.Type}}\t{{.Size}}" | grep -v "TYPE" | awk '{sum += $2} END {print sum}')
    
    if [[ "$docker_disk_usage" -gt 50000000000 ]]; then  # 50GB
        health_results["docker_storage"]="WARNING: High Docker disk usage ($(numfmt --to=iec $docker_disk_usage))"
    else
        health_results["docker_storage"]="OK: Docker disk usage normal ($(numfmt --to=iec $docker_disk_usage))"
    fi
    
    # Check for unhealthy containers
    local unhealthy_containers
    unhealthy_containers=$(docker ps --filter "health=unhealthy" --format "{{.Names}}" | wc -l)
    
    if [[ "$unhealthy_containers" -gt 0 ]]; then
        health_results["docker_containers"]="WARNING: $unhealthy_containers unhealthy containers"
    else
        health_results["docker_containers"]="OK: All containers healthy"
    fi
}

# Update failure counts
update_failure_counts() {
    for service in "${!health_results[@]}"; do
        if [[ "${health_results[$service]}" =~ ^CRITICAL ]]; then
            failure_counts["$service"]=$((failure_counts["$service"] + 1))
        elif [[ "${health_results[$service]}" =~ ^WARNING ]]; then
            # Don't increment for warnings, but don't reset either
            continue
        else
            failure_counts["$service"]=0
        fi
    done
}

# Check if alerts should be sent
check_alerts() {
    for service in "${!failure_counts[@]}"; do
        if [[ "${failure_counts[$service]}" -ge "$ALERT_THRESHOLD" ]]; then
            send_alert "$service" "${health_results[$service]}"
            failure_counts["$service"]=0  # Reset after alert
        fi
    done
}

# Send alert (placeholder for actual alerting mechanism)
send_alert() {
    local service="$1"
    local message="$2"
    
    warning "ALERT: $service - $message"
    
    # Here you could integrate with actual alerting systems:
    # - Email notifications
    # - Slack webhooks
    # - PagerDuty
    # - SMS notifications
    # - etc.
    
    # Example webhook notification (uncomment and configure):
    # curl -X POST -H 'Content-type: application/json' \
    #     --data "{\"text\":\"RTPI-PEN Alert: $service - $message\"}" \
    #     "$SLACK_WEBHOOK_URL"
}

# Generate status report
generate_status_report() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local overall_status="OK"
    
    # Determine overall status
    for service in "${!health_results[@]}"; do
        if [[ "${health_results[$service]}" =~ ^CRITICAL ]]; then
            overall_status="CRITICAL"
            break
        elif [[ "${health_results[$service]}" =~ ^WARNING ]]; then
            overall_status="WARNING"
        fi
    done
    
    # Create JSON status report
    cat > "$STATUS_FILE" << EOF
{
  "timestamp": "$timestamp",
  "overall_status": "$overall_status",
  "services": {
$(for service in "${!health_results[@]}"; do
    echo "    \"$service\": \"${health_results[$service]}\","
done | sed '$ s/,$//')
  }
}
EOF
    
    # Display summary
    echo
    info "Health Check Summary - $timestamp"
    echo "═══════════════════════════════════════════════════════════"
    printf "%-25s %s\n" "Overall Status:" "$overall_status"
    echo "───────────────────────────────────────────────────────────"
    
    for service in "${!health_results[@]}"; do
        local status="${health_results[$service]}"
        local color=""
        
        if [[ "$status" =~ ^CRITICAL ]]; then
            color="$RED"
        elif [[ "$status" =~ ^WARNING ]]; then
            color="$YELLOW"
        else
            color="$GREEN"
        fi
        
        printf "${color}%-25s %s${NC}\n" "$service:" "$status"
    done
    
    echo "═══════════════════════════════════════════════════════════"
    echo
}

# Main health check function
run_health_checks() {
    info "Starting RTPI-PEN health checks..."
    
    # Initialize failure counts if not already set
    for service in rtpi-database rtpi-cache rtpi-proxy rtpi-healer rtpi-orchestrator rtpi-tools sysreptor-db sysreptor-app system_disk system_memory system_cpu docker_daemon docker_storage docker_containers; do
        failure_counts["$service"]=${failure_counts["$service"]:-0}
    done
    
    # Check Docker availability
    if ! check_docker; then
        health_results["docker_daemon"]="CRITICAL: Docker not available"
        generate_status_report
        return 1
    fi
    
    # Run service-specific health checks
    check_rtpi_database
    check_rtpi_cache
    check_rtpi_proxy
    check_rtpi_healer
    check_rtpi_orchestrator
    check_rtpi_tools
    check_sysreptor_db
    check_sysreptor_app
    
    # Run system checks
    check_system_resources
    check_docker_system
    
    # Update failure counts and check for alerts
    update_failure_counts
    check_alerts
    
    # Generate status report
    generate_status_report
    
    success "Health checks completed"
}

# Continuous monitoring mode
monitor_continuously() {
    local interval="${1:-300}"  # Default 5 minutes
    
    info "Starting continuous monitoring (interval: ${interval}s)"
    
    while true; do
        run_health_checks
        sleep "$interval"
    done
}

# Show help
show_help() {
    cat << EOF
RTPI-PEN Health Check Utilities

Usage: $0 <command> [options]

Commands:
    check               Run health checks once
    monitor [interval]  Run continuous monitoring (default: 300s)
    status             Show current status from last check
    reset              Reset failure counts
    help               Show this help message

Examples:
    $0 check                    # Run health checks once
    $0 monitor 60               # Monitor every 60 seconds
    $0 status                   # Show last status

Environment Variables:
    ALERT_THRESHOLD    Number of failures before alert (default: 3)
    SLACK_WEBHOOK_URL  Slack webhook for notifications

EOF
}

# Load failure counts from file
load_failure_counts() {
    local count_file="/var/log/rtpi/failure-counts.txt"
    if [[ -f "$count_file" ]]; then
        while IFS='=' read -r service count; do
            failure_counts["$service"]="$count"
        done < "$count_file"
    fi
}

# Save failure counts to file
save_failure_counts() {
    local count_file="/var/log/rtpi/failure-counts.txt"
    for service in "${!failure_counts[@]}"; do
        echo "$service=${failure_counts[$service]}"
    done > "$count_file"
}

# Main command handler
main() {
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Load existing failure counts
    load_failure_counts
    
    case "${1:-check}" in
        check)
            run_health_checks
            save_failure_counts
            ;;
        monitor)
            monitor_continuously "${2:-300}"
            ;;
        status)
            if [[ -f "$STATUS_FILE" ]]; then
                cat "$STATUS_FILE"
            else
                error "No status file found. Run 'check' first."
                exit 1
            fi
            ;;
        reset)
            info "Resetting failure counts..."
            for service in "${!failure_counts[@]}"; do
                failure_counts["$service"]=0
            done
            save_failure_counts
            success "Failure counts reset"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Unknown command: ${1:-}. Use 'help' for usage information."
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
