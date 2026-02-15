# Setup and Development Guide

This guide helps you set up and develop with RemBotClawBot repository. Follow these steps to deploy a complete infrastructure automation suite.

## Quick Deployment Guide

```bash
# Clone repository
git clone https://github.com/RemBotClawBot/RemBotClawBot.git
cd RemBotClawBot

# Install dependencies
sudo apt-get update && sudo apt-get install -y \
  git curl wget nginx certbot python3-pip \
  fail2ban ufw postfix

# Run security hardening
sudo ./scripts/secure-firewall.sh

# Configure reverse proxy
sudo cp examples/secure-reverse-proxy.yml /etc/nginx/sites-available/secure-proxy
sudo ln -s /etc/nginx/sites-available/secure-proxy /etc/nginx/sites-enabled/

# Setup SSL certificates
sudo certbot --nginx -d your-domain.com

# Test configuration
sudo nginx -t && sudo systemctl reload nginx
```

## Production Deployment Checklist

### Infrastructure Setup ✓
- [ ] Deploy Forgejo/Gitea on port 3001
- [ ] Configure OpenClaw Gateway on port 3000  
- [ ] Setup experience-portal on port 3002
- [ ] Install Nginx reverse proxy

### Security Hardening ✓
- [ ] Run `./scripts/secure-firewall.sh`
- [ ] Configure UFW firewall rules
- [ ] Install and configure Fail2Ban (`examples/fail2ban-jails.conf`)
- [ ] Setup SSL certificates (Let's Encrypt)
- [ ] Apply security headers in Nginx

### Monitoring & Alerts ✓
- [ ] Enable health checks (`./scripts/health-check.sh`)
- [ ] Setup cron jobs for automated monitoring
- [ ] Configure log rotation
- [ ] Setup Discord/Slack notifications

### CI/CD Pipeline ✓
- [ ] Run `./scripts/forgejo-ci-setup.sh`
- [ ] Configure Forgejo Actions
- [ ] Setup manual runner as backup (`/opt/gitea/ci-runner.sh`)
- [ ] Configure post-receive hooks

### Backup Strategy ✓
- [ ] Run `./scripts/git-server-backup.sh`
- [ ] Schedule automated backups
- [ ] Test restore procedures
- [ ] Store backups offsite

### Validation Tests ✓
- [ ] Test SSH access with new firewall rules
- [ ] Verify HTTPS endpoints (ports 80/443)
- [ ] Test Git server connectivity (3000/3001)
- [ ] Validate CI/CD pipeline execution
- [ ] Check monitoring alerts

## Development Environment Setup

### 1. Clone the Repository
```bash
git clone https://github.com/RemBotClawBot/RemBotClawBot.git
cd RemBotClawBot
```

### 2. Python Environment (Optional for API examples)
```bash
# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Linux/Mac
# .venv\Scripts\activate    # On Windows

# Install dependencies
pip install -r requirements.txt  # If requirements.txt exists
# Or install minimal dependencies
pip install psutil
```

### 3. Make Scripts Executable
```bash
chmod +x scripts/*.sh
```

### 4. Add Scripts to PATH (Optional)
```bash
# Add to your shell profile (~/.bashrc, ~/.zshrc, etc.)
export PATH="$PATH:$(pwd)/scripts"
```

## Development Workflow

### Running Tests
```bash
# Syntax check shell scripts
for script in scripts/*.sh; do
  bash -n "$script" && echo "✓ $script: Syntax OK" || echo "✗ $script: Syntax error"
done

# Test Python examples
python3 -m py_compile examples/*.py
```

### Testing Scripts Locally
```bash
# Test health check (non-destructive)
./scripts/health-check.sh

# Dry run of backup script
./scripts/git-server-backup.sh --dry-run
```

### Running API Examples
```bash
# Basic health check
python3 examples/openclaw_api_example.py --health

# Health check with report
python3 examples/openclaw_api_example.py --health --report

# Check Git servers
python3 examples/openclaw_api_example.py --git
```

## Adding New Scripts

### 1. Shell Script Template
```bash
#!/bin/bash
# script-name.sh - Brief description
# Usage: ./script-name.sh [options]

set -euo pipefail

# Configuration
SCRIPT_NAME=$(basename "$0")
VERSION="1.0.0"

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

show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTION]...

Description of script goes here.

Options:
  -h, --help      Show this help message
  -v, --version   Show version information
  -d, --dry-run   Perform dry run without making changes
  --verbose       Enable verbose output

Examples:
  $SCRIPT_NAME                   # Run normally
  $SCRIPT_NAME --dry-run         # Test without changes
EOF
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "$SCRIPT_NAME v$VERSION"
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    log "Starting $SCRIPT_NAME..."
    
    # Main logic here
    
    log "Completed successfully."
}

# Run main function
main "$@"
```

### 2. Python Script Template
```python
#!/usr/bin/env python3
"""
script_name.py - Brief description
Usage: python3 script_name.py [options]
"""

import argparse
import sys
from typing import Optional


class ScriptName:
    """Main script class"""
    
    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        
    def run(self) -> int:
        """Main execution method"""
        try:
            # Your logic here
            return 0
        except Exception as e:
            print(f"Error: {e}", file=sys.stderr)
            return 1


def main():
    """CLI entry point"""
    parser = argparse.ArgumentParser(description="Script description")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose output")
    parser.add_argument("--dry-run", action="store_true", help="Dry run mode")
    
    args = parser.parse_args()
    
    script = ScriptName(verbose=args.verbose)
    return script.run()


if __name__ == "__main__":
    sys.exit(main())
```

## Version Control Best Practices

### Commit Structure
```bash
# Good commit messages
git commit -m "feat: add automated backup script"
git commit -m "fix: correct port detection in health check"
git commit -m "docs: update README with new examples"
git commit -m "refactor: simplify Python client class"
```

### Branch Strategy
- `main` - Stable production-ready code
- `develop` - Development branch (optional)
- `feature/*` - New features
- `bugfix/*` - Bug fixes
- `docs/*` - Documentation updates

### Tagging Releases
```bash
# Create annotated tag
git tag -a v1.0.0 -m "Release v1.0.0: Initial automation suite"
git push origin v1.0.0
```

## Continuous Integration

### GitHub Actions Example (.github/workflows/ci.yml)
```yaml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.10'
    
    - name: Run syntax checks
      run: |
        for script in scripts/*.sh; do
          bash -n "$script" || exit 1
        done
    
    - name: Run Python tests
      run: |
        python3 -m py_compile examples/*.py
```

## Useful Development Commands

```bash
# Format Markdown files
prettier --write "**/*.md"

# Check for broken links in Markdown
# Install: npm install -g markdown-link-check
markdown-link-check README.md

# Generate table of contents
# Install: npm install -g markdown-toc
markdown-toc -i README.md
```

## Troubleshooting

### Permission Issues
```bash
# Fix script permissions
chmod +x scripts/*.sh
```

### Python Import Errors
```bash
# Ensure Python path includes current directory
export PYTHONPATH="$PYTHONPATH:$(pwd)"
```

### Git Issues
```bash
# Set correct identity
git config user.name "Your Name"
git config user.email "your.email@example.com"
```

---
*Maintained by Rem • Last updated: 2026-02-15*