#!/bin/bash
# quick-demo.sh - Quick demonstration of RemBotClawBot automation toolkit
# Shows how to use key scripts with minimal configuration

set -euo pipefail

echo "🔧 RemBotClawBot - Quick Demo"
echo "================================"
echo ""

# Check if we're in the right directory
if [ ! -f "README.md" ]; then
    echo "⚠️  Please run this script from the RemBotClawBot directory"
    echo "   cd /path/to/RemBotClawBot"
    exit 1
fi

echo "1️⃣  System Health Check"
echo "----------------------"
echo "Running basic health diagnostics..."
./scripts/health-check.sh --brief || true
echo ""

echo "2️⃣  Security Hardening Preview"
echo "----------------------------"
echo "Running firewall configuration preview..."
echo "(Dry-run mode - no changes made)"
sudo ./scripts/secure-firewall.sh --dry-run 2>/dev/null | head -10 || true
echo ""

echo "3️⃣  OpenClaw API Example"
echo "------------------------"
echo "Testing OpenClaw connection..."
python3 examples/openclaw_api_example.py --status --simple 2>/dev/null | head -5 || {
    echo "  (OpenClaw not running or not configured)"
}
echo ""

echo "4️⃣  Backup Script Preview"
echo "------------------------"
echo "Checking backup prerequisites..."
if [ -f ./scripts/git-server-backup.sh ]; then
    echo "  ✓ Backup script available"
    echo "  ✓ Example usage: ./scripts/git-server-backup.sh daily"
else
    echo "  ✗ Backup script not found"
fi
echo ""

echo "5️⃣  Report Generation"
echo "-------------------"
if [ -f ./scripts/generate-health-report.sh ]; then
    echo "Generating minimal health report..."
    OUTPUT_DIR="./reports/demo-$(date +%Y%m%d-%H%M%S)" \
    ./scripts/generate-health-report.sh --format txt --quiet 2>/dev/null || true
    
    if [ -d "./reports" ]; then
        LATEST_REPORT=$(find ./reports -name "*.txt" -type f | head -1)
        if [ -n "$LATEST_REPORT" ]; then
            echo "  ✓ Report generated: $LATEST_REPORT"
            echo "  Sample output:"
            tail -5 "$LATEST_REPORT" 2>/dev/null | sed 's/^/    /' || true
        fi
    fi
else
    echo "  ✗ Report script not found"
fi
echo ""

echo "✅ Demo Complete!"
echo ""
echo "📚 Next Steps:"
echo "  • Review README.md for detailed documentation"
echo "  • Check SETUP.md for deployment instructions"
echo "  • Explore scripts/ directory for automation tools"
echo "  • Customize examples/ for your specific needs"
echo ""
echo "⚡ For production use:"
echo "  • Schedule health checks with cron"
echo "  • Configure alerting in monitor-openclaw.sh"
echo "  • Set up automated backups"
echo "  • Monitor logs regularly"
echo ""
echo "🔗 Repository: https://github.com/RemBotClawBot/RemBotClawBot"