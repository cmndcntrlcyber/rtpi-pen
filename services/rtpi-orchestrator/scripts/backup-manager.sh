#!/bin/bash
set -e

# RTPI-PEN Backup Management System
# Automated backup and restore utilities for RTPI-PEN services

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/rtpi/backup-manager.log"
BACKUP_BASE_DIR="/data/backups"
RETENTION_DAYS=30
MAX_BACKUPS=50

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
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
        error_exit "Docker is not installed or not in PATH"
    fi
    
    if ! docker info &> /dev/null; then
        error_exit "Docker daemon is not running or not accessible"
    fi
}

# Create backup directory structure
create_backup_directory() {
    local backup_id="$1"
    local backup_dir="$BACKUP_BASE_DIR/$backup_id"
    
    mkdir -p "$backup_dir"/{containers,volumes,configs,databases,logs}
    
    echo "$backup_dir"
}

# Generate backup ID
generate_backup_id() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_type="${1:-full}"
    echo "rtpi-${backup_type}-${timestamp}"
}

# Create backup manifest
create_backup_manifest() {
    local backup_dir="$1"
    local backup_type="$2"
    local services="$3"
    
    cat > "$backup_dir/manifest.json" << EOF
{
  "backup_id": "$(basename "$backup_dir")",
  "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
  "backup_type": "$backup_type",
  "services": [$services],
  "created_by": "rtpi-backup-manager",
  "version": "1.0",
  "system": {
    "hostname": "$(hostname)",
    "os": "$(uname -s)",
    "arch": "$(uname -m)"
  }
}
EOF
}

# Backup container configurations
backup_container_configs() {
    local backup_dir="$1"
    local container_configs_dir="$backup_dir/containers"
    
    info "Backing up container configurations..."
    
    # Export container configurations
    for container in $(docker ps -a --format "{{.Names}}" | grep -E "(rtpi-|sysreptor-)"); do
        if docker inspect "$container" > "$container_configs_dir/${container}.json"; then
            success "Exported config for container: $container"
        else
            warning "Failed to export config for container: $container"
        fi
    done
    
    # Export docker-compose files
    if [[ -f "/opt/rtpi-pen/docker-compose.yml" ]]; then
        cp "/opt/rtpi-pen/docker-compose.yml" "$container_configs_dir/"
        success "Copied docker-compose.yml"
    fi
    
    # Export environment files
    if [[ -f "/opt/rtpi-pen/.env" ]]; then
        cp "/opt/rtpi-pen/.env" "$container_configs_dir/"
        success "Copied environment file"
    fi
}

# Backup Docker volumes
backup_volumes() {
    local backup_dir="$1"
    local volumes_dir="$backup_dir/volumes"
    
    info "Backing up Docker volumes..."
    
    # Get list of volumes used by RTPI-PEN containers
    local volumes
    volumes=$(docker volume ls --format "{{.Name}}" | grep -E "(rtpi|sysreptor)")
    
    if [[ -z "$volumes" ]]; then
        warning "No RTPI-PEN volumes found"
        return 0
    fi
    
    for volume in $volumes; do
        local volume_backup="$volumes_dir/${volume}.tar.gz"
        
        info "Backing up volume: $volume"
        
        if docker run --rm \
            -v "$volume:/backup-source:ro" \
            -v "$volumes_dir:/backup-dest" \
            alpine:latest \
            tar czf "/backup-dest/${volume}.tar.gz" -C /backup-source .; then
            success "Volume backup created: ${volume}.tar.gz"
        else
            warning "Failed to backup volume: $volume"
        fi
    done
}

# Backup databases
backup_databases() {
    local backup_dir="$1"
    local databases_dir="$backup_dir/databases"
    
    info "Backing up databases..."
    
    # Backup PostgreSQL databases
    backup_postgresql "$databases_dir"
    backup_sysreptor_db "$databases_dir"
}

# Backup PostgreSQL (rtpi-database)
backup_postgresql() {
    local databases_dir="$1"
    
    if ! docker ps --format "{{.Names}}" | grep -q "rtpi-database"; then
        warning "rtpi-database container not running, skipping PostgreSQL backup"
        return 0
    fi
    
    info "Backing up PostgreSQL databases..."
    
    # Backup all databases
    local pg_dump_file="$databases_dir/rtpi-postgresql.sql"
    
    if docker exec rtpi-database pg_dumpall -U postgres > "$pg_dump_file"; then
        success "PostgreSQL backup created: rtpi-postgresql.sql"
        
        # Compress the backup
        if gzip "$pg_dump_file"; then
            success "PostgreSQL backup compressed"
        fi
    else
        warning "Failed to backup PostgreSQL databases"
    fi
}

# Backup SysReptor database
backup_sysreptor_db() {
    local databases_dir="$1"
    
    if ! docker ps --format "{{.Names}}" | grep -q "sysreptor-db"; then
        warning "sysreptor-db container not running, skipping SysReptor backup"
        return 0
    fi
    
    info "Backing up SysReptor database..."
    
    local sysreptor_dump_file="$databases_dir/sysreptor-database.sql"
    
    if docker exec sysreptor-db pg_dump -U sysreptor -d sysreptor > "$sysreptor_dump_file"; then
        success "SysReptor database backup created: sysreptor-database.sql"
        
        # Compress the backup
        if gzip "$sysreptor_dump_file"; then
            success "SysReptor database backup compressed"
        fi
    else
        warning "Failed to backup SysReptor database"
    fi
}

# Backup configurations
backup_configs() {
    local backup_dir="$1"
    local configs_dir="$backup_dir/configs"
    
    info "Backing up configurations..."
    
    # Copy configuration directories
    local config_paths=(
        "/opt/rtpi-pen/configs"
        "/opt/rtpi-pen/services"
        "/opt/rtpi-pen/setup"
        "/etc/nginx/sites-available"
        "/etc/nginx/sites-enabled"
        "/etc/ssl/certs"
        "/etc/ssl/private"
    )
    
    for config_path in "${config_paths[@]}"; do
        if [[ -d "$config_path" ]]; then
            local dest_name=$(basename "$config_path")
            if cp -r "$config_path" "$configs_dir/$dest_name"; then
                success "Copied configuration: $config_path"
            else
                warning "Failed to copy configuration: $config_path"
            fi
        fi
    done
    
    # Copy important files
    local config_files=(
        "/opt/rtpi-pen/docker-compose.yml"
        "/opt/rtpi-pen/.env"
        "/opt/rtpi-pen/README.md"
        "/etc/hosts"
        "/etc/crontab"
    )
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            if cp "$config_file" "$configs_dir/"; then
                success "Copied file: $config_file"
            else
                warning "Failed to copy file: $config_file"
            fi
        fi
    done
}

# Backup logs
backup_logs() {
    local backup_dir="$1"
    local logs_dir="$backup_dir/logs"
    
    info "Backing up logs..."
    
    # Copy log directories
    local log_paths=(
        "/var/log/rtpi"
        "/var/log/nginx"
        "/var/log/docker"
    )
    
    for log_path in "${log_paths[@]}"; do
        if [[ -d "$log_path" ]]; then
            local dest_name=$(basename "$log_path")
            if cp -r "$log_path" "$logs_dir/$dest_name"; then
                success "Copied logs: $log_path"
            else
                warning "Failed to copy logs: $log_path"
            fi
        fi
    done
    
    # Export container logs
    for container in $(docker ps --format "{{.Names}}" | grep -E "(rtpi-|sysreptor-)"); do
        local log_file="$logs_dir/${container}.log"
        
        if docker logs "$container" > "$log_file" 2>&1; then
            success "Exported logs for container: $container"
        else
            warning "Failed to export logs for container: $container"
        fi
    done
}

# Create full backup
create_full_backup() {
    local backup_id=$(generate_backup_id "full")
    local backup_dir=$(create_backup_directory "$backup_id")
    
    info "Creating full backup: $backup_id"
    
    # Create backup manifest
    create_backup_manifest "$backup_dir" "full" '"rtpi-database", "rtpi-cache", "rtpi-proxy", "rtpi-healer", "rtpi-orchestrator", "rtpi-tools", "sysreptor-db", "sysreptor-app"'
    
    # Perform backup operations
    backup_container_configs "$backup_dir"
    backup_volumes "$backup_dir"
    backup_databases "$backup_dir"
    backup_configs "$backup_dir"
    backup_logs "$backup_dir"
    
    # Create archive
    local archive_file="$BACKUP_BASE_DIR/${backup_id}.tar.gz"
    
    if tar -czf "$archive_file" -C "$BACKUP_BASE_DIR" "$backup_id"; then
        success "Full backup archive created: ${backup_id}.tar.gz"
        
        # Remove uncompressed directory
        rm -rf "$backup_dir"
        success "Cleaned up temporary backup directory"
    else
        error_exit "Failed to create backup archive"
    fi
    
    success "Full backup completed: $backup_id"
    echo "$backup_id"
}

# Create incremental backup
create_incremental_backup() {
    local backup_id=$(generate_backup_id "incremental")
    local backup_dir=$(create_backup_directory "$backup_id")
    
    info "Creating incremental backup: $backup_id"
    
    # Create backup manifest
    create_backup_manifest "$backup_dir" "incremental" '"rtpi-database", "rtpi-cache", "rtpi-proxy", "rtpi-healer", "rtpi-orchestrator", "rtpi-tools", "sysreptor-db", "sysreptor-app"'
    
    # Perform incremental backup (configs and databases only)
    backup_container_configs "$backup_dir"
    backup_databases "$backup_dir"
    backup_configs "$backup_dir"
    
    # Create archive
    local archive_file="$BACKUP_BASE_DIR/${backup_id}.tar.gz"
    
    if tar -czf "$archive_file" -C "$BACKUP_BASE_DIR" "$backup_id"; then
        success "Incremental backup archive created: ${backup_id}.tar.gz"
        
        # Remove uncompressed directory
        rm -rf "$backup_dir"
        success "Cleaned up temporary backup directory"
    else
        error_exit "Failed to create incremental backup archive"
    fi
    
    success "Incremental backup completed: $backup_id"
    echo "$backup_id"
}

# List available backups
list_backups() {
    info "Available backups:"
    echo
    printf "%-30s %-20s %-15s %s\n" "BACKUP ID" "TIMESTAMP" "TYPE" "SIZE"
    echo "────────────────────────────────────────────────────────────────────────────"
    
    for backup_file in "$BACKUP_BASE_DIR"/*.tar.gz; do
        if [[ -f "$backup_file" ]]; then
            local backup_name=$(basename "$backup_file" .tar.gz)
            local backup_size=$(ls -lh "$backup_file" | awk '{print $5}')
            local backup_date=$(stat -c %y "$backup_file" | cut -d' ' -f1,2 | cut -d'.' -f1)
            
            # Extract backup type from filename
            local backup_type="unknown"
            if [[ "$backup_name" == *"full"* ]]; then
                backup_type="full"
            elif [[ "$backup_name" == *"incremental"* ]]; then
                backup_type="incremental"
            fi
            
            printf "%-30s %-20s %-15s %s\n" "$backup_name" "$backup_date" "$backup_type" "$backup_size"
        fi
    done
    
    echo
}

# Restore from backup
restore_backup() {
    local backup_id="$1"
    local backup_file="$BACKUP_BASE_DIR/${backup_id}.tar.gz"
    
    if [[ ! -f "$backup_file" ]]; then
        error_exit "Backup file not found: $backup_file"
    fi
    
    info "Restoring from backup: $backup_id"
    
    # Extract backup
    local restore_dir="$BACKUP_BASE_DIR/restore_$$"
    mkdir -p "$restore_dir"
    
    if ! tar -xzf "$backup_file" -C "$restore_dir"; then
        error_exit "Failed to extract backup archive"
    fi
    
    local backup_dir="$restore_dir/$backup_id"
    
    # Validate backup
    if [[ ! -f "$backup_dir/manifest.json" ]]; then
        error_exit "Invalid backup: missing manifest.json"
    fi
    
    info "Backup validation passed"
    
    # Stop services
    info "Stopping RTPI-PEN services..."
    docker-compose -f /opt/rtpi-pen/docker-compose.yml down || warning "Failed to stop some services"
    
    # Restore configurations
    restore_configs "$backup_dir"
    
    # Restore databases
    restore_databases "$backup_dir"
    
    # Restore volumes (if full backup)
    if [[ -d "$backup_dir/volumes" ]]; then
        restore_volumes "$backup_dir"
    fi
    
    # Start services
    info "Starting RTPI-PEN services..."
    docker-compose -f /opt/rtpi-pen/docker-compose.yml up -d || warning "Failed to start some services"
    
    # Cleanup
    rm -rf "$restore_dir"
    
    success "Restore completed: $backup_id"
}

# Restore configurations
restore_configs() {
    local backup_dir="$1"
    local configs_dir="$backup_dir/configs"
    
    if [[ ! -d "$configs_dir" ]]; then
        warning "No configurations to restore"
        return 0
    fi
    
    info "Restoring configurations..."
    
    # Restore configuration directories
    local config_paths=(
        "configs:/opt/rtpi-pen/configs"
        "services:/opt/rtpi-pen/services"
        "setup:/opt/rtpi-pen/setup"
    )
    
    for config_mapping in "${config_paths[@]}"; do
        local src_name=$(echo "$config_mapping" | cut -d: -f1)
        local dest_path=$(echo "$config_mapping" | cut -d: -f2)
        
        if [[ -d "$configs_dir/$src_name" ]]; then
            if cp -r "$configs_dir/$src_name" "$dest_path"; then
                success "Restored configuration: $dest_path"
            else
                warning "Failed to restore configuration: $dest_path"
            fi
        fi
    done
    
    # Restore important files
    local config_files=(
        "docker-compose.yml:/opt/rtpi-pen/docker-compose.yml"
        ".env:/opt/rtpi-pen/.env"
        "README.md:/opt/rtpi-pen/README.md"
    )
    
    for config_mapping in "${config_files[@]}"; do
        local src_name=$(echo "$config_mapping" | cut -d: -f1)
        local dest_path=$(echo "$config_mapping" | cut -d: -f2)
        
        if [[ -f "$configs_dir/$src_name" ]]; then
            if cp "$configs_dir/$src_name" "$dest_path"; then
                success "Restored file: $dest_path"
            else
                warning "Failed to restore file: $dest_path"
            fi
        fi
    done
}

# Restore databases
restore_databases() {
    local backup_dir="$1"
    local databases_dir="$backup_dir/databases"
    
    if [[ ! -d "$databases_dir" ]]; then
        warning "No databases to restore"
        return 0
    fi
    
    info "Restoring databases..."
    
    # Restore PostgreSQL
    if [[ -f "$databases_dir/rtpi-postgresql.sql.gz" ]]; then
        info "Restoring PostgreSQL database..."
        
        if gunzip -c "$databases_dir/rtpi-postgresql.sql.gz" | docker exec -i rtpi-database psql -U postgres; then
            success "PostgreSQL database restored"
        else
            warning "Failed to restore PostgreSQL database"
        fi
    fi
    
    # Restore SysReptor database
    if [[ -f "$databases_dir/sysreptor-database.sql.gz" ]]; then
        info "Restoring SysReptor database..."
        
        if gunzip -c "$databases_dir/sysreptor-database.sql.gz" | docker exec -i sysreptor-db psql -U sysreptor -d sysreptor; then
            success "SysReptor database restored"
        else
            warning "Failed to restore SysReptor database"
        fi
    fi
}

# Restore volumes
restore_volumes() {
    local backup_dir="$1"
    local volumes_dir="$backup_dir/volumes"
    
    if [[ ! -d "$volumes_dir" ]]; then
        warning "No volumes to restore"
        return 0
    fi
    
    info "Restoring Docker volumes..."
    
    for volume_backup in "$volumes_dir"/*.tar.gz; do
        if [[ -f "$volume_backup" ]]; then
            local volume_name=$(basename "$volume_backup" .tar.gz)
            
            info "Restoring volume: $volume_name"
            
            # Create volume if it doesn't exist
            docker volume create "$volume_name" || true
            
            if docker run --rm \
                -v "$volume_name:/restore-dest" \
                -v "$volumes_dir:/backup-source" \
                alpine:latest \
                tar xzf "/backup-source/${volume_name}.tar.gz" -C /restore-dest; then
                success "Volume restored: $volume_name"
            else
                warning "Failed to restore volume: $volume_name"
            fi
        fi
    done
}

# Clean up old backups
cleanup_old_backups() {
    info "Cleaning up old backups..."
    
    # Remove backups older than retention period
    find "$BACKUP_BASE_DIR" -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
    
    # Remove excess backups if more than max allowed
    local backup_count=$(find "$BACKUP_BASE_DIR" -name "*.tar.gz" | wc -l)
    
    if [[ $backup_count -gt $MAX_BACKUPS ]]; then
        local excess_count=$((backup_count - MAX_BACKUPS))
        info "Removing $excess_count excess backups..."
        
        find "$BACKUP_BASE_DIR" -name "*.tar.gz" -printf '%T@ %p\n' | sort -n | head -n $excess_count | cut -d' ' -f2- | xargs rm -f
    fi
    
    success "Backup cleanup completed"
}

# Schedule automatic backups
schedule_backups() {
    local cron_file="/etc/cron.d/rtpi-backup"
    
    info "Setting up automatic backup schedule..."
    
    cat > "$cron_file" << 'EOF'
# RTPI-PEN Automatic Backup Schedule
# Full backup every Sunday at 2 AM
0 2 * * 0 root /opt/rtpi-orchestrator/scripts/backup-manager.sh full >/dev/null 2>&1

# Incremental backup every day at 2 AM (except Sunday)
0 2 * * 1-6 root /opt/rtpi-orchestrator/scripts/backup-manager.sh incremental >/dev/null 2>&1

# Cleanup old backups every Monday at 3 AM
0 3 * * 1 root /opt/rtpi-orchestrator/scripts/backup-manager.sh cleanup >/dev/null 2>&1
EOF
    
    chmod 644 "$cron_file"
    
    # Restart cron service
    systemctl restart cron || service cron restart || warning "Failed to restart cron service"
    
    success "Automatic backup schedule configured"
}

# Show help
show_help() {
    cat << EOF
RTPI-PEN Backup Management System

Usage: $0 <command> [options]

Commands:
    full                Create a full backup
    incremental        Create an incremental backup
    list               List available backups
    restore <backup_id> Restore from a backup
    cleanup            Clean up old backups
    schedule           Set up automatic backup schedule
    help               Show this help message

Examples:
    $0 full                        # Create full backup
    $0 incremental                 # Create incremental backup
    $0 list                        # List all backups
    $0 restore rtpi-full-20240101_120000  # Restore specific backup
    $0 cleanup                     # Clean up old backups

Configuration:
    BACKUP_BASE_DIR:   $BACKUP_BASE_DIR
    RETENTION_DAYS:    $RETENTION_DAYS
    MAX_BACKUPS:       $MAX_BACKUPS

EOF
}

# Main command handler
main() {
    # Create log and backup directories
    mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_BASE_DIR"
    
    # Check Docker availability
    check_docker
    
    case "${1:-}" in
        full)
            create_full_backup
            ;;
        incremental)
            create_incremental_backup
            ;;
        list)
            list_backups
            ;;
        restore)
            if [[ -z "${2:-}" ]]; then
                error_exit "Backup ID required for restore command"
            fi
            restore_backup "$2"
            ;;
        cleanup)
            cleanup_old_backups
            ;;
        schedule)
            schedule_backups
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error_exit "Unknown command: ${1:-}. Use 'help' for usage information."
            ;;
    esac
}

# Run main function with all arguments
main "$@"
