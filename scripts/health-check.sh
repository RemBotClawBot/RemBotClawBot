#!/bin/bash
# health-check.sh - System health monitoring for OpenClaw deployments
# Run via cron or heartbeat checks to monitor infrastructure

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

check_service() {
    local service_name=$1
    local port=${2:-0}
    
    if systemctl is-active --quiet "$service_name"; then
        success "$service_name is running"
        
        if [ "$port" -gt 0 ]; then
            if nc -z localhost "$port" 2>/dev/null; then
                success "$service_name is listening on port $port"
            else
                warning "$service_name is running but not listening on port $port"
            fi
        fi
        return 0
    else
        error "$service_name is NOT running"
        return 1
    fi
}

check_disk() {
    local usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$usage" -gt 90 ]; then
        error "Disk usage is critical: ${usage}%"
        return 1
    elif [ "$usage" -gt 80 ]; then
        warning "Disk usage is high: ${usage}%"
        return 0
    else
        success "Disk usage is normal: ${usage}%"
        return 0
    fi
}

check_memory() {
    local free_mb=$(free -m | awk 'NR==2 {print $4}')
    if [ "$free_mb" -lt 100 ]; then
        warning "Low memory available: ${free_mb}MB"
        return 0
    else
        success "Memory available: ${free_mb}MB"
        return 0
    fi
}

check_openclaw() {
    if pgrep -f "openclaw" > /dev/null; then
        success "OpenClaw process is running"
        
        # Check gateway status
        if openclaw gateway status 2>/dev/null | grep -q "running"; then
            success "OpenClaw gateway is running"
        else
            warning "OpenClaw gateway may not be fully operational"
        fi
        return 0
    else
        error "OpenClaw process is NOT running"
        return 1
    fi
}

check_git_servers() {
    log "Checking Git servers..."
    
    # Check Forgejo (port 3001)
    if nc -z localhost 3001 2>/dev/null; then
        success "Forgejo is accessible on port 3001"
    else
        error "Forgejo is NOT accessible on port 3001"
    fi
    
    # Check Gitea (port 3000 - may be backup)
    if nc -z localhost 3000 2>/dev/null; then
        warning "Gitea is still running on port 3000 (backup instance)"
    fi
}

check_ci_runner() {
    local runner_script="/opt/gitea/ci-runner.sh"
    
    if [ -f "$runner_script" ]; then
        success "CI runner script exists: $runner_script"
        
        if [ -x "$runner_script" ]; then
            success "CI runner script is executable"
        else
            warning "CI runner script is not executable (chmod +x needed)"
        fi
    else
        warning "CI runner script not found at $runner_script"
    fi
}

check_security() {
    log "Performing basic security checks..."
    
    # Check SSH configuration
    if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config 2>/dev/null; then
        success "SSH root login is disabled"
    else
        warning "SSH root login may be enabled (check /etc/ssh/sshd_config)"
    fi
    
    # Check firewall
    if command -v ufw > /dev/null; then
        if ufw status | grep -q "Status: active"; then
            success "UFW firewall is active"
        else
            warning "UFW firewall is not active"
        fi
    elif command -v firewall-cmd > /dev/null; then
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            success "Firewalld is running"
        fi
    fi
    
    # Check for failed login attempts
    local failed_logins=$(grep "Failed password" /var/log/auth.log 2>/dev/null | tail -5)
    if [ -n "$failed_logins" ]; then
        warning "Recent failed login attempts detected"
        echo "$failed_logins"
    fi
}

main() {
    log "Starting system health check..."
    
    # System resources
    check_disk
    check_memory
    
    # Services
    check_service "ssh" 22
    
    # OpenClaw ecosystem
    check_openclaw
    
    # Git infrastructure
    check_git_servers
    check_ci_runner
    
    # Security
    check_security
    
    log "Health check completed at $(date)"
    
    # Generate summary
    echo ""
    echo "=== SUMMARY ==="
    echo "Run time: $(date)"
    echo "Hostname: $(hostname)"
    echo "Uptime: $(uptime -p)"
    echo "Load average: $(cat /proc/loadavg | awk '{print $1,$2,$3}')"
    
    # Return non-zero if any critical errors
    if systemctl is-active --quiet "openclaw" && nc -z localhost 3001; then
        echo "Status: ${GREEN}HEALTHY${NC}"
        exit 0
    else
        echo "Status: ${RED}UNHEALTHY${NC}"
        exit 1
    fi
}

# Run main function
main "$@"