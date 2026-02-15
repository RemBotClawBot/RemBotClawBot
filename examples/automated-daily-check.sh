#!/bin/bash
# automated-daily-check.sh - Example of daily automated system monitoring
# Shows how to combine multiple scripts into a comprehensive daily check
# Perfect for cron jobs or scheduled monitoring

set -euo pipefail

# Configuration
LOG_DIR="/var/log/rembot"
REPORT_DIR="/opt/rembot/reports"
RETENTION_DAYS=7

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_message() {
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

# Create directories if they don't exist
mkdir -p "$LOG_DIR"
mkdir -p "$REPORT_DIR"

log_message "Starting daily automated system check..."

# Run comprehensive health check
log_message "1. Running system health check..."
if ./scripts/health-check.sh > "$LOG_DIR/health-$(date +%Y%m%d).log" 2>&1; then
    success "Health check completed"
else
    warning "Health check reported issues - check $LOG_DIR/health-$(date +%Y%m%d).log"
fi

# Create system report
log_message "2. Generating detailed health report..."
if ./scripts/generate-health-report.sh --output "$REPORT_DIR" --format json,html,txt > "$LOG_DIR/report-$(date +%Y%m%d).log" 2>&1; then
    success "Report generated in $REPORT_DIR"
else
    warning "Report generation had issues"
fi

# Backup Git server data
log_message "3. Performing Git server backup..."
if sudo ./scripts/git-server-backup.sh daily > "$LOG_DIR/backup-$(date +%Y%m%d).log" 2>&1; then
    success "Git server backup completed"
else
    error "Git server backup failed - check logs"
fi

# Monitor OpenClaw status
log_message "4. Checking OpenClaw services..."
if ./scripts/monitor-openclaw.sh --notify > "$LOG_DIR/monitor-$(date +%Y%m%d).log" 2>&1; then
    success "OpenClaw monitoring completed"
else
    warning "OpenClaw monitoring reported issues"
fi

# Run security checks
log_message "5. Running security audit..."
if sudo ./scripts/secure-firewall.sh --dry-run > "$LOG_DIR/security-$(date +%Y%m%d).log" 2>&1; then
    success "Security audit passed"
else
    warning "Security audit found issues - review $LOG_DIR/security-$(date +%Y%m%d).log"
fi

# Clean up old logs
log_message "6. Cleaning up old logs (keeping $RETENTION_DAYS days)..."
find "$LOG_DIR" -name "*.log" -mtime +$RETENTION_DAYS -delete
find "$REPORT_DIR" -name "*.json" -o -name "*.html" -o -name "*.txt" -mtime +$RETENTION_DAYS -delete
success "Old logs cleaned up"

# Generate summary
log_message "7. Generating daily summary..."
DAILY_SUMMARY="$REPORT_DIR/daily-summary-$(date +%Y%m%d).txt"
cat > "$DAILY_SUMMARY" << EOF
Daily System Check Summary
===========================
Date: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)

Health Check Status: $(grep -c "\[✓\]" "$LOG_DIR/health-$(date +%Y%m%d).log" || echo "0") passes
                    $(grep -c "\[✗\]" "$LOG_DIR/health-$(date +%Y%m%d).log" || echo "0") failures
                    $(grep -c "\[!\]" "$LOG_DIR/health-$(date +%Y%m%d).log" || echo "0") warnings

Reports Generated:
$(find "$REPORT_DIR" -name "*$(date +%Y%m%d)*" -type f | sed 's|^|  - |')

Backup Status: $(tail -1 "$LOG_DIR/backup-$(date +%Y%m%d).log" 2>/dev/null || echo "Unknown")

Security Issues Found:
$(grep -c "FAILED\|WARNING\|ERROR" "$LOG_DIR/security-$(date +%Y%m%d).log" 2>/dev/null || echo "0")

Disk Usage:
$(df -h / | tail -1)

Memory Usage:
$(free -h | grep Mem | awk '{print "Used: " $3 "/" $2 " (" $3/$2*100 "%)"}')

Uptime: $(uptime -p)

Next Steps:
1. Review $LOG_DIR/*-$(date +%Y%m%d).log for details
2. Check $REPORT_DIR/ for generated reports
3. Address any warnings or failures reported above
EOF

success "Daily summary saved to $DAILY_SUMMARY"

log_message "Daily automated check completed successfully!"
echo ""
echo "📊 Summary Report: $DAILY_SUMMARY"
echo "📁 Logs Directory: $LOG_DIR"
echo "📈 Reports Directory: $REPORT_DIR"
echo ""
echo "To schedule this check daily via cron, add to crontab:"
echo "0 6 * * * /path/to/RemBotClawBot/examples/automated-daily-check.sh"
echo ""