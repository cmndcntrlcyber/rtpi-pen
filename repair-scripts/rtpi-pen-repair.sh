#!/bin/bash
# RTPI-PEN Main Repair Orchestrator
# Comprehensive repair solution for Docker container restart loops

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️ $1${NC}"
}

print_step() {
    echo -e "${PURPLE}🔄 $1${NC}"
}

# Function to show banner
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
    ____  ________  ____      ____  ___________   __
   / __ \/_  __/ / / __ \    / __ \/ ____/ __ \ / /
  / /_/ / / / / / / /_/ /   / /_/ / __/ / / / / /  
 / _, _/ / / / / / ____/   / _, _/ /___/ /_/ / /___
/_/ |_| /_/ /_/_/_/       /_/ |_/_____/\____/_____/
                                                   
    Red Team Penetration Infrastructure - Self-Healing Repair Tool
    Created by: RTPI-PEN Development Team
    Version: 1.0.0
EOF
    echo -e "${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check for required tools
    local required_tools=(
        "docker"
        "curl"
        "openssl"
        "sudo"
    )
    
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            print_success "$tool is installed"
        else
            print_error "$tool is not installed"
            missing_tools+=("$tool")
        fi
    done
    
    # Check for Docker Compose plugin
    if docker compose version &> /dev/null; then
        print_success "docker compose plugin is available"
    else
        print_error "docker compose plugin is not available"
        missing_tools+=("docker compose")
    fi
    
    # Check sudo access
    if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges"
        echo "Please run with sudo or ensure your user has sudo access"
        exit 1
    fi
    
    # Check Docker daemon
    if sudo systemctl is-active --quiet docker; then
        print_success "Docker daemon is running"
    else
        print_error "Docker daemon is not running"
        echo "Starting Docker daemon..."
        sudo systemctl start docker
        sleep 5
        if sudo systemctl is-active --quiet docker; then
            print_success "Docker daemon started"
        else
            print_error "Failed to start Docker daemon"
            exit 1
        fi
    fi
    
    # Check if we're in the right directory
    if [ ! -f "docker-compose.yml" ]; then
        print_error "docker-compose.yml not found"
        echo "Please run this script from the RTPI-PEN root directory"
        exit 1
    fi
    
    # Exit if missing tools
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools and try again"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Function to assess current situation
assess_situation() {
    print_header "Assessing Current Situation"
    
    # Check for restart loops
    local restarting_containers=$(sudo docker ps -a | grep -c "Restarting" || echo "0")
    local exited_containers=$(sudo docker ps -a | grep -c "Exited" || echo "0")
    local total_containers=$(sudo docker ps -a | wc -l)
    
    print_info "Container Status Assessment:"
    echo "  • Total containers: $total_containers"
    echo "  • Restarting containers: $restarting_containers"
    echo "  • Exited containers: $exited_containers"
    
    if [ "$restarting_containers" -gt 0 ]; then
        print_warning "Detected $restarting_containers containers in restart loops"
        echo "These containers are likely failing to start properly"
    fi
    
    if [ "$exited_containers" -gt 0 ]; then
        print_warning "Detected $exited_containers exited containers"
        echo "These containers have stopped running"
    fi
    
    # Show current problematic containers
    print_info "Current container status:"
    sudo docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -15
    
    # Check system resources
    print_info "System Resources:"
    local disk_usage=$(df / | awk 'NR==2 {print $5}')
    local mem_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
    echo "  • Disk usage: $disk_usage"
    echo "  • Memory usage: ${mem_usage}%"
    
    # Check Docker system info
    print_info "Docker System:"
    sudo docker system df
}

# Function to run repair phase
run_repair_phase() {
    local phase_name="$1"
    local script_name="$2"
    local description="$3"
    
    print_header "Phase: $phase_name"
    print_info "$description"
    
    if [ ! -f "$script_name" ]; then
        print_error "Script not found: $script_name"
        return 1
    fi
    
    # Make script executable
    chmod +x "$script_name"
    
    # Run the script
    print_step "Executing $script_name..."
    
    if bash "$script_name"; then
        print_success "$phase_name completed successfully"
        return 0
    else
        print_error "$phase_name failed"
        return 1
    fi
}

# Function to show repair menu
show_repair_menu() {
    print_header "Repair Options"
    
    echo "Select a repair option:"
    echo "1. Full Repair (Recommended) - Complete repair process"
    echo "2. Emergency Repair Only - Stop containers and cleanup"
    echo "3. Manual Initialization Only - Initialize configurations"
    echo "4. Sequential Startup Only - Start services in order"
    echo "5. Health Validation Only - Check system health"
    echo "6. Custom Repair - Choose specific phases"
    echo "7. Exit"
    echo ""
    read -p "Enter your choice (1-7): " choice
    
    case $choice in
        1) run_full_repair ;;
        2) run_emergency_repair ;;
        3) run_manual_init ;;
        4) run_sequential_startup ;;
        5) run_health_validation ;;
        6) run_custom_repair ;;
        7) print_info "Exiting..."; exit 0 ;;
        *) print_error "Invalid choice. Please try again."; show_repair_menu ;;
    esac
}

# Function to run full repair
run_full_repair() {
    print_header "Starting Full Repair Process"
    
    local failed_phases=()
    
    # Phase 1: Emergency Repair
    if ! run_repair_phase "Emergency Repair" "repair-scripts/emergency-repair.sh" "Stop restart loops and cleanup environment"; then
        failed_phases+=("Emergency Repair")
    fi
    
    # Wait between phases
    sleep 5
    
    # Phase 2: Manual Initialization
    if ! run_repair_phase "Manual Initialization" "repair-scripts/manual-init.sh" "Initialize configurations and dependencies"; then
        failed_phases+=("Manual Initialization")
    fi
    
    # Wait between phases
    sleep 5
    
    # Phase 3: Sequential Startup
    if ! run_repair_phase "Sequential Startup" "repair-scripts/sequential-startup.sh" "Start services in proper dependency order"; then
        failed_phases+=("Sequential Startup")
    fi
    
    # Wait between phases
    sleep 5
    
    # Phase 4: Health Validation
    if ! run_repair_phase "Health Validation" "repair-scripts/health-validator.sh" "Validate system health and generate report"; then
        failed_phases+=("Health Validation")
    fi
    
    # Show final results
    print_header "Full Repair Results"
    
    if [ ${#failed_phases[@]} -eq 0 ]; then
        print_success "All repair phases completed successfully!"
        show_success_summary
    else
        print_error "Some repair phases failed: ${failed_phases[*]}"
        show_failure_summary
    fi
}

# Function to run emergency repair only
run_emergency_repair() {
    run_repair_phase "Emergency Repair" "repair-scripts/emergency-repair.sh" "Stop restart loops and cleanup environment"
}

# Function to run manual initialization only
run_manual_init() {
    run_repair_phase "Manual Initialization" "repair-scripts/manual-init.sh" "Initialize configurations and dependencies"
}

# Function to run sequential startup only
run_sequential_startup() {
    run_repair_phase "Sequential Startup" "repair-scripts/sequential-startup.sh" "Start services in proper dependency order"
}

# Function to run health validation only
run_health_validation() {
    run_repair_phase "Health Validation" "repair-scripts/health-validator.sh" "Validate system health and generate report"
}

# Function to run custom repair
run_custom_repair() {
    print_header "Custom Repair Options"
    
    echo "Select phases to run (multiple selections allowed):"
    echo "1. Emergency Repair"
    echo "2. Manual Initialization"
    echo "3. Sequential Startup"
    echo "4. Health Validation"
    echo ""
    read -p "Enter phase numbers separated by spaces (e.g., 1 3 4): " -a phases
    
    local failed_phases=()
    
    for phase in "${phases[@]}"; do
        case $phase in
            1) 
                if ! run_repair_phase "Emergency Repair" "repair-scripts/emergency-repair.sh" "Stop restart loops and cleanup environment"; then
                    failed_phases+=("Emergency Repair")
                fi
                ;;
            2) 
                if ! run_repair_phase "Manual Initialization" "repair-scripts/manual-init.sh" "Initialize configurations and dependencies"; then
                    failed_phases+=("Manual Initialization")
                fi
                ;;
            3) 
                if ! run_repair_phase "Sequential Startup" "repair-scripts/sequential-startup.sh" "Start services in proper dependency order"; then
                    failed_phases+=("Sequential Startup")
                fi
                ;;
            4) 
                if ! run_repair_phase "Health Validation" "repair-scripts/health-validator.sh" "Validate system health and generate report"; then
                    failed_phases+=("Health Validation")
                fi
                ;;
            *) 
                print_error "Invalid phase number: $phase"
                ;;
        esac
        
        # Wait between phases
        sleep 2
    done
    
    # Show results
    if [ ${#failed_phases[@]} -eq 0 ]; then
        print_success "All selected phases completed successfully!"
    else
        print_error "Some phases failed: ${failed_phases[*]}"
    fi
}

# Function to show success summary
show_success_summary() {
    print_header "🎉 Repair Completed Successfully!"
    
    echo "Your RTPI-PEN system has been repaired and is now running."
    echo ""
    echo "🌐 Service Access Points:"
    echo "  • Kasm Workspaces: https://localhost:8443"
    echo "  • SysReptor: http://localhost:7777"
    echo "  • Empire C2: http://localhost:1337"
    echo "  • Orchestrator: http://localhost:9444"
    echo "  • Healer API: http://localhost:8888/health"
    echo "  • Main Proxy: https://localhost:443"
    echo ""
    echo "📊 System Status:"
    sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -10
    echo ""
    echo "🔍 Next Steps:"
    echo "  1. Test service endpoints above"
    echo "  2. Monitor container logs: sudo docker logs <container_name>"
    echo "  3. Run periodic health checks: ./repair-scripts/health-validator.sh"
    echo "  4. Use restart-failed-services.sh for quick fixes"
    echo ""
    echo "📚 Additional Resources:"
    echo "  • Emergency recovery: ./repair-scripts/emergency-repair.sh"
    echo "  • Quick restart: ./repair-scripts/restart-failed-services.sh"
    echo "  • Full repair: ./repair-scripts/rtpi-pen-repair.sh"
}

# Function to show failure summary
show_failure_summary() {
    print_header "⚠️ Repair Completed with Issues"
    
    echo "Some repair phases failed. Please check the errors above."
    echo ""
    echo "🔧 Troubleshooting Steps:"
    echo "  1. Check Docker daemon status: sudo systemctl status docker"
    echo "  2. Check system resources: df -h && free -h"
    echo "  3. Review container logs: sudo docker logs <container_name>"
    echo "  4. Check permissions: ls -la /opt/kasm/1.15.0/"
    echo "  5. Verify network connectivity: sudo docker network ls"
    echo ""
    echo "🆘 Get Help:"
    echo "  1. Run health validator: ./repair-scripts/health-validator.sh"
    echo "  2. Check system logs: journalctl -u docker"
    echo "  3. Review repair logs in /var/log/rtpi-pen-repair/"
    echo ""
    echo "🔄 Retry Options:"
    echo "  • Run full repair again: ./repair-scripts/rtpi-pen-repair.sh"
    echo "  • Try individual phases from the menu"
    echo "  • Use emergency repair: ./repair-scripts/emergency-repair.sh"
}

# Function to create backup before repair
create_backup() {
    print_header "Creating System Backup"
    
    local backup_dir="/tmp/rtpi-pen-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup configurations
    if [ -f "docker-compose.yml" ]; then
        cp docker-compose.yml "$backup_dir/"
        print_success "Backed up docker-compose.yml"
    fi
    
    if [ -f ".env" ]; then
        cp .env "$backup_dir/"
        print_success "Backed up .env file"
    fi
    
    if [ -d "configs" ]; then
        cp -r configs "$backup_dir/"
        print_success "Backed up configs directory"
    fi
    
    # Save current state
    sudo docker ps -a > "$backup_dir/containers_before_repair.txt"
    sudo docker images > "$backup_dir/images_before_repair.txt"
    sudo docker volume ls > "$backup_dir/volumes_before_repair.txt"
    sudo docker network ls > "$backup_dir/networks_before_repair.txt"
    
    print_success "System backup created at: $backup_dir"
    return 0
}

# Function to show system information
show_system_info() {
    print_header "System Information"
    
    echo "🖥️ System Details:"
    echo "  • OS: $(uname -s) $(uname -r)"
    echo "  • Architecture: $(uname -m)"
    echo "  • User: $(whoami)"
    echo "  • Working Directory: $(pwd)"
    echo "  • Date: $(date)"
    echo ""
    
    echo "🐳 Docker Information:"
    echo "  • Docker Version: $(docker --version)"
    echo "  • Docker Compose Version: $(docker compose --version)"
    echo "  • Docker Daemon Status: $(sudo systemctl is-active docker)"
    echo ""
    
    echo "💾 System Resources:"
    echo "  • CPU: $(nproc) cores"
    echo "  • Memory: $(free -h | awk 'NR==2{printf "%s", $2}')"
    echo "  • Disk: $(df -h / | awk 'NR==2{printf "%s available", $4}')"
    echo ""
    
    echo "🔧 Current Container Status:"
    sudo docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" | head -10
}

# Main execution function
main() {
    # Show banner
    show_banner
    
    # Show system info
    show_system_info
    
    # Check prerequisites
    check_prerequisites
    
    # Assess current situation
    assess_situation
    
    # Create backup
    create_backup
    
    # Show repair menu
    show_repair_menu
}

# Trap for cleanup
trap 'print_error "Script interrupted"; exit 1' INT TERM

# Execute main function
main "$@"
