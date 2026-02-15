#!/bin/bash
# monitor-openclaw.sh - Monitor OpenClaw services and restart if needed
# Usage: ./monitor-openclaw.sh [--auto-restart] [--notify]
# Can be scheduled via cron (e.g., */5 * * * *)

set -euo pipefail

# Configuration
SCRIPT_NAME=$(basename "$0")
AUTO_RESTART=false
NOTIFY=false
CHECK_INTERVAL=60  # seconds between checks
MAX_RETRIES=3
OPENCLAW_PROCESS="openclaw"
GATEWAY_SERVICE="openclaw"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1"
}

info() {
    echo -e "${BLUE}[i]${NC} $1"
}

send_notification() {
    local message="$1"
    local level="$2"
    
    if [ "$NOTIFY" = true ]; then
        # This is a template - implement your notification method
        # Examples: email, Slack webhook, Discord, etc.
        case "$level" in
            "critical")
                echo "CRITICAL: $message" >> /tmp/openclaw-monitor.log
                # Example: curl -X POST -H 'Content-type: application/json' \
                #   --data "{\"text\":\"$message\"}" $SLACK_WEBHOOK
                ;;
            "warning")
                echo "WARNING: $message" >> /tmp/openclaw-monitor.log
                ;;
            "info")
                echo "INFO: $message" >> /tmp/openclaw-monitor.log
                ;;
        esac
    fi
}

check_openclaw_process() {
    if pgrep -f "$OPENCLAW_PROCESS" > /dev/null; then
        success "OpenClaw process is running"
        return 0
    else
        error "OpenClaw process is NOT running"
        send_notification "OpenClaw process is not running" "critical"
        return 1
    fi
}

check_gateway_service() {
    if systemctl is-active --quiet "$GATEWAY_SERVICE"; then
        success "OpenClaw gateway service is running"
        return 0
    else
        error "OpenClaw gateway service is NOT running"
        send_notification "OpenClaw gateway service is not running" "critical"
        return 1
    fi
}

check_port_access() {
    local port=$1
    local service=$2
    
    if nc -z localhost "$port" 2>/dev/null; then
        success "$service is accessible on port $port"
        return 0
    else
        warning "$service is NOT accessible on port $port"
        send_notification "$service port $port unreachable" "warning"
        return 1
    fi
}

check_git_servers() {
    log "Checking Git servers..."
    
    # Check Forgejo (port 3001)
    check_port_access 3001 "Forgejo"
    
    # Check Gitea (port 3000 - optional backup)
    if nc -z localhost 3000 2>/dev/null; then
        info "Gitea backup instance is running on port 3000"
    fi
}

restart_openclaw() {
    log "Attempting to restart OpenClaw..."
    
    if systemctl restart "$GATEWAY_SERVICE"; then
        success "OpenClaw gateway restarted successfully"
        send_notification "OpenClaw gateway restarted successfully" "info"
        
        # Wait for service to come up
        sleep 5
        
        if systemctl is-active --quiet "$GATEWAY_SERVICE"; then
            success "OpenClaw gateway is now running"
            return 0
        else
            error "OpenClaw gateway failed to start after restart"
            send_notification "OpenClaw gateway failed to start after restart" "critical"
            return 1
        fi
    else
        error "Failed to restart OpenClaw gateway"
        send_notification "Failed to restart OpenClaw gateway" "critical"
        return 1
    fi
}

perform_health_check() {
    local failures=0
    
    log "=== OpenClaw Health Check ==="
    log "Time: $(date)"
    log "Host: $(hostname)"
    
    # Check OpenClaw process
    if ! check_openclaw_process; then
        failures=$((failures + 1))
    fi
    
    # Check gateway service
    if ! check_gateway_service; then
        failures=$((failures + 1))
    fi
    
    # Check Git servers
    check_git_servers
    
    # Check disk space
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 90 ]; then
        error "Critical disk usage: ${disk_usage}%"
        send_notification "Critical disk usage: ${disk_usage}%" "critical"
        failures=$((failures + 1))
    elif [ "$disk_usage" -gt 80 ]; then
        warning "High disk usage: ${disk_usage}%"
        send_notification "High disk usage: ${disk_usage}%" "warning"
    else
        success "Disk usage: ${disk_usage}%"
    fi
    
    # Check memory
    local free_mb=$(free -m | awk 'NR==2 {print $4}')
    if [ "$free_mb" -lt 100 ]; then
        warning "Low memory available: ${free_mb}MB"
        send_notification "Low memory available: ${free_mb}MB" "warning"
    else
        success "Memory available: ${free_mb}MB"
    fi
    
    log "=== Health Check Complete ==="
    
    if [ "$failures" -gt 0 ]; then
        error "Found $failures critical issue(s)"
        return 1
    else
        success "All checks passed"
        return 0
    fi
}

monitor_loop() {
    local consecutive_failures=0
    
    while true; do
        log "Starting monitoring cycle..."
        
        if ! perform_health_check; then
            consecutive_failures=$((consecutive_failures + 1))
            warning "Consecutive failures: $consecutive_failures"
            
            if [ "$consecutive_failures" -ge "$MAX_RETRIES" ] && [ "$AUTO_RESTART" = true ]; then
                error "Max retries ($MAX_RETRIES) reached. Attempting restart..."
                if restart_openclaw; then
                    consecutive_failures=0
                fi
            fi
        else
            consecutive_failures=0
        fi
        
        log "Sleeping for $CHECK_INTERVAL seconds..."
        sleep "$CHECK_INTERVAL"
    done
}

show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTION]...

Monitor OpenClaw services and optionally restart them if they fail.

Options:
  -h, --help          Show this help message
  -a, --auto-restart  Automatically restart OpenClaw if checks fail $MAX_RETRIES times
  -n, --notify        Send notifications on failures (configure notification method)
  -i, --interval N    Set check interval in seconds (default: $CHECK_INTERVAL)
  -r, --retries N     Set maximum retries before restart (default: $MAX_RETRIES)
  --single-check      Run a single health check and exit
  --once              Run one monitoring cycle and exit

Examples:
  $SCRIPT_NAME --single-check      # Run one health check
  $SCRIPT_NAME --auto-restart     # Monitor with auto-restart
  $SCRIPT_NAME --interval 30      # Check every 30 seconds
  $SCRIPT_NAME --once             # Run one cycle and exit

Cron example (check every 5 minutes):
  */5 * * * * /path/to/monitor-openclaw.sh --single-check

EOF
}

main() {
    local single_check=false
    local run_once=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -a|--auto-restart)
                AUTO_RESTART=true
                shift
                ;;
            -n|--notify)
                NOTIFY=true
                shift
                ;;
            -i|--interval)
                CHECK_INTERVAL="$2"
                shift 2
                ;;
            -r|--retries)
                MAX_RETRIES="$2"
                shift 2
                ;;
            --single-check)
                single_check=true
                shift
                ;;
            --once)
                run_once=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    if [ "$single_check" = true ]; then
        perform_health_check
        exit $?
    elif [ "$run_once" = true ]; then
        perform_health_check
        exit $?
    else
        monitor_loop
    fi
}

# Run main function
main "$@"