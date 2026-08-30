#!/bin/bash

# IDOL Monitoring Stack Manager
# Usage: ./monitor.sh [command] [service1] [service2] ...
# Commands: start, stop, restart, status, logs, enable, disable, urls, help
# Services: yacht, dockge, dozzle, cadvisor, prometheus, grafana, loki, promtail, dokemon, node-exporter, monitor-ui, all (or specify multiple services)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.monitor-ui.yml"
PROJECT_NAME="idol-monitoring"

# Service definitions with ports and descriptions
declare -A SERVICES=(
    ["yacht"]="5001:Container Management UI"
    ["dockge"]="5002:Docker Compose Stack Manager"
    ["dozzle"]="5003:Real-time Log Viewer"
    ["cadvisor"]="5004:Container Metrics Collector"
    ["prometheus"]="5005:Metrics Collection & Storage"
    ["grafana"]="5006:Metrics Visualization Dashboard"
    ["loki"]="5007:Log Aggregation System"
    ["promtail"]="5008:Log Shipper for Loki"
    ["dokemon"]="5009:Simple Docker Monitor"
    ["node-exporter"]="5010:System Metrics Exporter"
    ["monitor-ui"]="5011:Config Monitor UI (Flask Dashboard)"
)

# Helper functions
print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

check_compose_file() {
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "Docker Compose file not found: $COMPOSE_FILE"
        exit 1
    fi
}

get_service_status() {
    local service=$1
    if docker ps --format "{{.Names}}" | grep -q "^idol-${service}$"; then
        echo "running"
    elif docker ps -a --format "{{.Names}}" | grep -q "^idol-${service}$"; then
        echo "stopped"
    else
        echo "not_created"
    fi
}

# Check if the ports for the given services (or all) are already in use by
# something outside this stack. If conflicts are found, ask the user to
# confirm before killing them and continuing deployment.
check_port_conflicts() {
    local services=("$@")
    local ports_to_check=()

    if [ "${services[0]}" = "all" ]; then
        for svc in "${!SERVICES[@]}"; do
            IFS=':' read -r port desc <<< "${SERVICES[$svc]}"
            ports_to_check+=("$port:$svc")
        done
    else
        for svc in "${services[@]}"; do
            IFS=':' read -r port desc <<< "${SERVICES[$svc]}"
            ports_to_check+=("$port:$svc")
        done
    fi

    local conflicts=()
    for entry in "${ports_to_check[@]}"; do
        local port="${entry%%:*}"
        local svc="${entry##*:}"
        local pids
        pids=$(sudo lsof -t -i:"$port" 2>/dev/null || true)
        if [ -n "$pids" ]; then
            conflicts+=("$port:$svc:$pids")
        fi
    done

    if [ ${#conflicts[@]} -eq 0 ]; then
        print_success "No port conflicts detected on ports 5001-5011."
        return 0
    fi

    print_error "The following ports are already in use by processes outside this stack:"
    echo ""
    for entry in "${conflicts[@]}"; do
        IFS=':' read -r port svc pids <<< "$entry"
        echo -e "  ${YELLOW}Port $port${NC} (service: $svc)"
        for pid in $pids; do
            echo -e "    PID $pid: $(ps -o cmd= -p "$pid" 2>/dev/null)"
        done
    done
    echo ""

    read -r -p "$(echo -e "${YELLOW}Kill the above process(es) and continue deployment? [y/N]: ${NC}")" confirm
    case "$confirm" in
        [yY]|[yY][eE][sS])
            for entry in "${conflicts[@]}"; do
                IFS=':' read -r port svc pids <<< "$entry"
                print_info "Killing process(es) on port $port ($svc)..."
                sudo kill -9 $pids 2>/dev/null || true
            done
            sleep 2
            print_success "Conflicting processes terminated. Proceeding with deployment."
            ;;
        *)
            print_error "Deployment aborted by user. Conflicting ports still in use."
            exit 1
            ;;
    esac
}

# Command functions - now support multiple services or "all"
cmd_start() {
    local services=("$@")
    
    # Normalize: if no args, treat as all
    if [ ${#services[@]} -eq 0 ]; then
        services=("all")
    fi
    
    local has_all=false
    for svc in "${services[@]}"; do
        if [ "$svc" = "all" ]; then
            has_all=true
            break
        fi
    done
    
    check_compose_file
    
    if $has_all; then
        print_header "Starting All Monitoring Services"
        check_port_conflicts "all"
        docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d
        print_success "All services started"
        cmd_status "all"
        return
    fi
    
    # Validate all services
    for service in "${services[@]}"; do
        if [ -z "${SERVICES[$service]}" ]; then
            print_error "Unknown service: $service"
            cmd_help
            exit 1
        fi
    done
    
    print_header "Starting Services: ${services[*]}"
    check_port_conflicts "${services[@]}"
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" up -d "${services[@]}"
    print_success "Services started: ${services[*]}"
    
    # Show service info for each
    for service in "${services[@]}"; do
        IFS=':' read -r port desc <<< "${SERVICES[$service]}"
        echo -e "\n${GREEN}Service Info:${NC}"
        echo -e "  Name: $service"
        echo -e "  Description: $desc"
        echo -e "  Port: $port"
        echo -e "  URL: http://localhost:$port"
        
        # Show service-specific credentials
        if [ "$service" = "yacht" ]; then
            echo -e "  Credentials: admin@idol.local / opentext1!"
        else
            echo -e "  Credentials: admin / opentext1!"
        fi
    done
}

cmd_stop() {
    local services=("$@")
    
    if [ ${#services[@]} -eq 0 ]; then
        services=("all")
    fi
    
    local has_all=false
    for svc in "${services[@]}"; do
        if [ "$svc" = "all" ]; then
            has_all=true
            break
        fi
    done
    
    check_compose_file
    
    if $has_all; then
        print_header "Stopping All Monitoring Services"
        docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down
        print_success "All services stopped"
        return
    fi
    
    # Validate all services
    for service in "${services[@]}"; do
        if [ -z "${SERVICES[$service]}" ]; then
            print_error "Unknown service: $service"
            exit 1
        fi
    done
    
    print_header "Stopping Services: ${services[*]}"
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" stop "${services[@]}"
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" rm -f "${services[@]}"
    print_success "Services stopped: ${services[*]}"
}

cmd_restart() {
    local services=("$@")
    
    if [ ${#services[@]} -eq 0 ]; then
        services=("all")
    fi
    
    local has_all=false
    for svc in "${services[@]}"; do
        if [ "$svc" = "all" ]; then
            has_all=true
            break
        fi
    done
    
    check_compose_file
    
    if $has_all; then
        print_header "Restarting All Monitoring Services"
        docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" restart
        print_success "All services restarted"
        return
    fi
    
    # Validate all services
    for service in "${services[@]}"; do
        if [ -z "${SERVICES[$service]}" ]; then
            print_error "Unknown service: $service"
            exit 1
        fi
    done
    
    print_header "Restarting Services: ${services[*]}"
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" restart "${services[@]}"
    print_success "Services restarted: ${services[*]}"
}

cmd_status() {
    local services=("$@")
    
    if [ ${#services[@]} -eq 0 ]; then
        services=("all")
    fi
    
    local has_all=false
    for svc in "${services[@]}"; do
        if [ "$svc" = "all" ]; then
            has_all=true
            break
        fi
    done
    
    print_header "IDOL Monitoring Stack Status"
    
    printf "%-20s %-12s %-8s %-50s\n" "SERVICE" "STATUS" "PORT" "DESCRIPTION"
    echo "--------------------------------------------------------------------------------"
    
    if $has_all; then
        # Sort services by port number
        for svc in $(for s in "${!SERVICES[@]}"; do
            IFS=':' read -r port desc <<< "${SERVICES[$s]}"
            echo "$port:$s"
        done | sort -n | cut -d: -f2); do
            status=$(get_service_status "$svc")
            IFS=':' read -r port desc <<< "${SERVICES[$svc]}"
            
            case $status in
                "running")
                    status_color="${GREEN}RUNNING${NC}"
                    ;;
                "stopped")
                    status_color="${YELLOW}STOPPED${NC}"
                    ;;
                *)
                    status_color="${RED}NOT CREATED${NC}"
                    ;;
            esac
            
            printf "%-20s " "$svc"
            echo -en "$status_color"
            printf "%-8s " "$port"
            printf "%-50s\n" "$desc"
        done
    else
        # Show only requested services (in provided order)
        for svc in "${services[@]}"; do
            if [ -z "${SERVICES[$svc]}" ]; then
                print_error "Unknown service: $svc"
                exit 1
            fi
            
            status=$(get_service_status "$svc")
            IFS=':' read -r port desc <<< "${SERVICES[$svc]}"
            
            case $status in
                "running")
                    status_color="${GREEN}RUNNING${NC}"
                    ;;
                "stopped")
                    status_color="${YELLOW}STOPPED${NC}"
                    ;;
                *)
                    status_color="${RED}NOT CREATED${NC}"
                    ;;
            esac
            
            printf "%-20s " "$svc"
            echo -en "$status_color"
            printf "%-8s " "$port"
            printf "%-50s\n" "$desc"
        done
    fi
    
    echo ""
    print_info "Default Credentials: admin / opentext1!"
}

cmd_logs() {
    local services=("$@")
    
    if [ ${#services[@]} -eq 0 ]; then
        services=("all")
    fi
    
    local has_all=false
    for svc in "${services[@]}"; do
        if [ "$svc" = "all" ]; then
            has_all=true
            break
        fi
    done
    
    check_compose_file
    
    if $has_all; then
        print_info "Showing logs for all services (Ctrl+C to exit)..."
        docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" logs -f
    else
        # Validate all services
        for service in "${services[@]}"; do
            if [ -z "${SERVICES[$service]}" ]; then
                print_error "Unknown service: $service"
                exit 1
            fi
        done
        
        print_info "Showing logs for ${services[*]} (Ctrl+C to exit)..."
        docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" logs -f "${services[@]}"
    fi
}

cmd_enable() {
    # Enable is alias for start
    cmd_start "$@"
}

cmd_disable() {
    local services=("$@")
    
    if [ ${#services[@]} -eq 0 ]; then
        services=("all")
    fi
    
    local has_all=false
    for svc in "${services[@]}"; do
        if [ "$svc" = "all" ]; then
            has_all=true
            break
        fi
    done
    
    check_compose_file
    
    if $has_all; then
        print_header "Disabling All Monitoring Services"
        docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" down -v
        print_success "All services disabled and volumes removed"
    else
        # Validate all services
        for service in "${services[@]}"; do
            if [ -z "${SERVICES[$service]}" ]; then
                print_error "Unknown service: $service"
                exit 1
            fi
        done
        
        print_header "Disabling Services: ${services[*]}"
        docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" stop "${services[@]}"
        docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" rm -f "${services[@]}"
        print_success "Services disabled: ${services[*]}"
    fi
}

cmd_urls() {
    print_header "IDOL Monitoring Service URLs"
    
    # Sort services by port number
    for svc in $(for s in "${!SERVICES[@]}"; do
        IFS=':' read -r port desc <<< "${SERVICES[$s]}"
        echo "$port:$s"
    done | sort -n | cut -d: -f2); do
        status=$(get_service_status "$svc")
        IFS=':' read -r port desc <<< "${SERVICES[$svc]}"
        
        if [ "$status" = "running" ]; then
            echo -e "${GREEN}✓${NC} $svc: http://localhost:$port - $desc"
        else
            echo -e "${RED}✗${NC} $svc: http://localhost:$port - $desc (not running)"
        fi
    done
    
    echo ""
    print_info "Default Credentials: admin / opentext1!"
}

cmd_help() {
    print_header "IDOL Monitoring Stack Manager"
    
    echo "Usage: $0 [command] [service1] [service2] ... [serviceN]"
    echo ""
    echo "Commands:"
    echo "  start [services]   - Start one or more services or 'all' (default: all)"
    echo "  stop [services]    - Stop one or more services or 'all' (default: all)"
    echo "  restart [services] - Restart one or more services or 'all' (default: all)"
    echo "  status [services]  - Show status of one or more services or 'all' (default: all)"
    echo "  logs [services]    - Show/tail logs for one or more services or 'all' (default: all)"
    echo "  enable [services]  - Enable and start one or more services or 'all' (default: all)"
    echo "  disable [services] - Stop and remove one or more services or 'all' (default: all)"
    echo "  urls               - Show all service URLs (no service arguments needed)"
    echo "  help               - Show this help message"
    echo ""
    echo "Services (specify one, multiple, or 'all'):"
    # Sort services by port number
    for svc in $(for s in "${!SERVICES[@]}"; do
        IFS=':' read -r port desc <<< "${SERVICES[$s]}"
        echo "$port:$s"
    done | sort -n | cut -d: -f2); do
        IFS=':' read -r port desc <<< "${SERVICES[$svc]}"
        printf "  %-15s - %-35s (Port: %s)\n" "$svc" "$desc" "$port"
    done
    echo "  all             - All services (default when no service specified)"
    echo ""
    echo "Examples:"
    echo "  $0 start grafana                         # Start only Grafana"
    echo "  $0 start dozzle monitor-ui               # Start Dozzle and Monitor UI together"
    echo "  $0 stop all                              # Stop all services"
    echo "  $0 restart prometheus node-exporter      # Restart specific services"
    echo "  $0 logs dozzle monitor-ui                # Tail combined logs for both"
    echo "  $0 status                                # Show status of all services"
    echo "  $0 status dozzle grafana                 # Show status only for listed services"
    echo "  $0 enable loki promtail                  # Enable/start Loki and Promtail"
    echo "  $0 disable cadvisor                      # Disable Cadvisor"
    echo "  $0 urls                                  # Show all service URLs"
}

# Main script logic
if [ $# -eq 0 ]; then
    cmd_help
    exit 0
fi

COMMAND=$1
shift

# Handle commands that don't take service arguments
if [[ "$COMMAND" == "urls" || "$COMMAND" == "help" || "$COMMAND" == "--help" || "$COMMAND" == "-h" ]]; then
    if [ $# -gt 0 ]; then
        print_info "Extra arguments ignored for command: $COMMAND"
    fi
    case $COMMAND in
        urls) cmd_urls ;;
        help|--help|-h) cmd_help ;;
    esac
    exit 0
fi

# For service-aware commands, collect remaining args as services list
if [ $# -eq 0 ]; then
    SERVICES_LIST=("all")
else
    SERVICES_LIST=("$@")
fi

case $COMMAND in
    start)
        cmd_start "${SERVICES_LIST[@]}"
        ;;
    stop)
        cmd_stop "${SERVICES_LIST[@]}"
        ;;
    restart)
        cmd_restart "${SERVICES_LIST[@]}"
        ;;
    status)
        cmd_status "${SERVICES_LIST[@]}"
        ;;
    logs)
        cmd_logs "${SERVICES_LIST[@]}"
        ;;
    enable)
        cmd_enable "${SERVICES_LIST[@]}"
        ;;
    disable)
        cmd_disable "${SERVICES_LIST[@]}"
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        cmd_help
        exit 1
        ;;
esac

exit 0