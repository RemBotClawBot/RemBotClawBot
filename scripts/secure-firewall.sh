#!/bin/bash
# secure-firewall.sh - Firewall hardening and network security configuration
# Configures UFW firewall with secure defaults and service-aware rules

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    exit 1
}

info() {
    echo -e "${BLUE}[i]${NC} $1"
}

check_ufw_installed() {
    if ! command -v ufw &> /dev/null; then
        error "UFW (Uncomplicated Firewall) is not installed. Install with: sudo apt install ufw"
    fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root"
    fi
}

enable_ufw() {
    log "Enabling UFW firewall..."
    
    # Enable IPv6
    ufw allow proto ipv6-icmp from any to any || warning "IPv6 ICMP rule failed"
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    success "UFW defaults configured"
}

setup_basic_rules() {
    log "Setting up basic firewall rules..."
    
    # Allow SSH (port 22) - customize port if needed
    local ssh_port=${SSH_PORT:-22}
    ufw allow "$ssh_port"/tcp comment "SSH access"
    
    # Allow HTTP/HTTPS for web services
    ufw allow 80/tcp comment "HTTP web traffic"
    ufw allow 443/tcp comment "HTTPS web traffic"
    
    # Allow OpenClaw gateway API (customize port if different)
    ufw allow 3000/tcp comment "OpenClaw Gateway API"
    
    # Allow Forgejo/Gitea ports
    ufw allow 3001/tcp comment "Forgejo web interface"
    
    # Allow ICMP (ping) - helpful for network diagnostics
    ufw allow icmp comment "ICMP (ping)"
    
    success "Basic rules configured"
}

setup_service_specific_rules() {
    log "Configuring service-specific rules..."
    
    # Database access (if applicable)
    read -p "Allow database access? (MySQL/PostgreSQL) [y/N]: " allow_db
    if [[ "$allow_db" =~ ^[Yy]$ ]]; then
        ufw allow 3306/tcp comment "MySQL database"
        ufw allow 5432/tcp comment "PostgreSQL database"
    fi
    
    # Redis cache access
    read -p "Allow Redis access? [y/N]: " allow_redis
    if [[ "$allow_redis" =~ ^[Yy]$ ]]; then
        ufw allow 6379/tcp comment "Redis cache"
    fi
    
    # Monitoring ports (Prometheus/Grafana)
    read -p "Allow monitoring access? [y/N]: " allow_monitoring
    if [[ "$allow_monitoring" =~ ^[Yy]$ ]]; then
        ufw allow 9090/tcp comment "Prometheus metrics"
        ufw allow 3000/tcp comment "Grafana dashboard"
    fi
    
    success "Service rules configured"
}

setup_rate_limiting() {
    log "Setting up rate limiting..."
    
    # Create rate limiting rules
    cat > /etc/ufw/before.rules << 'EOF'
# Rate limiting for SSH
-A ufw-before-input -p tcp --dport 22 -m state --state NEW -m recent --set --name SSH
-A ufw-before-input -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 --name SSH -j DROP

# Rate limiting for HTTP/HTTPS
-A ufw-before-input -p tcp --dport 80 -m state --state NEW -m recent --set --name HTTP
-A ufw-before-input -p tcp --dport 80 -m state --state NEW -m recent --update --seconds 30 --hitcount 20 --name HTTP -j DROP

-A ufw-before-input -p tcp --dport 443 -m state --state NEW -m recent --set --name HTTPS
-A ufw-before-input -p tcp --dport 443 -m state --state NEW -m recent --update --seconds 30 --hitcount 20 --name HTTPS -j DROP
EOF
    
    success "Rate limiting rules created"
}

setup_logging() {
    log "Configuring firewall logging..."
    
    # Enable logging at medium level (recommended)
    ufw logging medium
    
    # Create log rotation configuration
    cat > /etc/logrotate.d/ufw << 'EOF'
/var/log/ufw.log
{
    rotate 7
    daily
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        invoke-rc.d rsyslog rotate > /dev/null 2>&1 || true
    endscript
}
EOF
    
    success "Logging configured"
}

setup_fail2ban_integration() {
    log "Setting up Fail2Ban integration..."
    
    if ! command -v fail2ban-client &> /dev/null; then
        warning "Fail2Ban not installed. Skipping integration."
        read -p "Install Fail2Ban? [y/N]: " install_fail2ban
        if [[ "$install_fail2ban" =~ ^[Yy]$ ]]; then
            apt-get update && apt-get install -y fail2ban
        else
            return 0
        fi
    fi
    
    # Create custom Fail2Ban jail for UFW
    cat > /etc/fail2ban/jail.d/ufw-custom.conf << 'EOF'
[ufw]
enabled = true
filter = ufw
action = ufw[name=UFW]
logpath = /var/log/ufw.log
maxretry = 5
bantime = 3600
findtime = 600
EOF
    
    # Create UFW filter
    cat > /etc/fail2ban/filter.d/ufw.conf << 'EOF'
[Definition]
failregex = ^\[UFW BLOCK\].*SRC=<HOST>
ignoreregex =
EOF
    
    systemctl restart fail2ban
    success "Fail2Ban integration configured"
}

show_firewall_status() {
    log "Current firewall status:"
    ufw status verbose
}

generate_firewall_report() {
    local report_file="/var/log/firewall-setup-$(date +%Y%m%d-%H%M%S).log"
    
    cat > "$report_file" << EOF
=== Firewall Security Report ===
Generated: $(date)
Hostname: $(hostname)
IP Addresses: $(hostname -I)

=== UFW Configuration ===
$(ufw status verbose)

=== Listening Ports ===
$(ss -tulpn)

=== Recent Connections ===
$(ss -t state established -n | head -20)

=== Firewall Rules Summary ===
• SSH (port ${SSH_PORT:-22}) - Rate limited (4 attempts per minute)
• HTTP/HTTPS (ports 80/443) - Rate limited (20 requests per 30 seconds)
• OpenClaw Gateway (port 3000)
• Forgejo (port 3001)
• ICMP (ping) enabled for diagnostics
• Default policy: DENY incoming, ALLOW outgoing

=== Rate Limiting ===
• SSH: 4 connections per minute from same IP
• HTTP: 20 connections per 30 seconds from same IP
• HTTPS: 20 connections per 30 seconds from same IP

=== Monitoring ===
• Logging level: medium
• Fail2Ban integration: $(if command -v fail2ban-client &> /dev/null; then echo "Enabled"; else echo "Disabled"; fi)
• Log rotation: 7 days retention

=== Recommendations ===
1. Review allowed ports periodically
2. Monitor /var/log/ufw.log for blocked attempts
3. Consider using VPN for management access
4. Regularly update firewall rules as services change
5. Test connectivity after rule changes

=== Test Commands ===
# Check firewall status:
sudo ufw status verbose

# View firewall logs:
sudo tail -f /var/log/ufw.log

# Test SSH access:
ssh user@$(hostname -I | awk '{print $1}')

# Test web access:
curl -I http://$(hostname -I | awk '{print $1}')
curl -I https://$(hostname -I | awk '{print $1}')

# Check Fail2Ban status:
sudo fail2ban-client status

EOF
    
    success "Firewall report generated: $report_file"
}

main() {
    echo "=== Firewall Security Hardening ==="
    echo ""
    
    check_root
    check_ufw_installed
    
    log "Starting firewall configuration..."
    
    # Backup existing rules
    if ufw status | grep -q "Status: active"; then
        warning "UFW is already active. Creating backup..."
        ufw status numbered > /etc/ufw/backup-$(date +%Y%m%d).rules
    fi
    
    # Disable UFW temporarily for configuration
    ufw --force disable || true
    
    enable_ufw
    setup_basic_rules
    setup_service_specific_rules
    setup_rate_limiting
    setup_logging
    setup_fail2ban_integration
    
    # Enable UFW
    ufw --force enable
    
    success "Firewall configuration complete!"
    
    show_firewall_status
    
    echo ""
    read -p "Generate firewall security report? [Y/n]: " generate_report
    if [[ ! "$generate_report" =~ ^[Nn]$ ]]; then
        generate_firewall_report
    fi
    
    echo ""
    echo "=== Next Steps ==="
    echo "1. Test SSH access from another terminal before disconnecting"
    echo "2. Verify web services are accessible"
    echo "3. Review firewall report for configuration details"
    echo "4. Monitor /var/log/ufw.log for blocked attempts"
    echo ""
    echo "Firewall is now active with secure defaults."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi