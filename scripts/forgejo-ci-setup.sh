#!/bin/bash
# forgejo-ci-setup.sh - Complete Forgejo CI/CD setup with manual runners
# Configure Forgejo Actions, runner setup, and deployment workflows

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

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root"
    fi
}

check_forgejo_installed() {
    if ! command -v forgejo &> /dev/null; then
        error "Forgejo is not installed. Install it first."
    fi
}

enable_actions() {
    log "Enabling Forgejo Actions..."
    
    # Check if Actions are already enabled
    if grep -q "ENABLED=true" /etc/forgejo/app.ini 2>/dev/null || grep -q "\[actions\]" /etc/forgejo/app.ini 2>/dev/null; then
        warning "Actions may already be configured. Checking..."
    fi
    
    # Create Actions configuration
    cat >> /etc/forgejo/app.ini << 'EOF'

[actions]
ENABLED = true
DEFAULT_ACTIONS_URL = github
EOF
    
    success "Actions configuration added"
}

setup_runner_directory() {
    local runner_dir="/opt/forgejo-runner"
    
    if [ -d "$runner_dir" ]; then
        warning "Runner directory already exists at $runner_dir"
        return 0
    fi
    
    log "Creating runner directory..."
    mkdir -p "$runner_dir"
    chown -R git:git "$runner_dir"
    chmod 755 "$runner_dir"
    
    success "Runner directory created at $runner_dir"
}

install_runner_binary() {
    local runner_dir="/opt/forgejo-runner"
    local version="v2.6.0"
    local arch="$(uname -m)"
    
    if [ -f "$runner_dir/forgejo-runner" ]; then
        success "Runner binary already installed"
        return 0
    fi
    
    log "Downloading Forgejo runner version $version..."
    
    # Map architecture
    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
        *) warning "Unsupported architecture: $arch" && return 1 ;;
    esac
    
    local url="https://codeberg.org/forgejo/runner/releases/download/$version/forgejo-runner-$arch"
    
    curl -L "$url" -o "$runner_dir/forgejo-runner"
    chmod +x "$runner_dir/forgejo-runner"
    
    success "Runner binary installed"
}

create_runner_service() {
    local service_file="/etc/systemd/system/forgejo-runner.service"
    
    if [ -f "$service_file" ]; then
        warning "Runner service already exists"
        return 0
    fi
    
    log "Creating systemd service for runner..."
    
    cat > "$service_file" << EOF
[Unit]
Description=Forgejo Actions Runner
After=network.target forgejo.service
Requires=forgejo.service

[Service]
Type=simple
User=git
Group=git
WorkingDirectory=/opt/forgejo-runner
ExecStart=/opt/forgejo-runner/forgejo-runner daemon
Restart=always
RestartSec=10
Environment=GITHUB_TOKEN=your-token-here
Environment=FORGEJO_INSTANCE_URL=http://localhost:3001
Environment=FORGEJO_RUNNER_REGISTRATION_TOKEN=your-registration-token-here

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    success "Runner service created"
}

create_sample_workflow() {
    local workflow_dir="/var/lib/forgejo/repos/rem/experience-portal.git"
    local workflow_file="$workflow_dir/.github/workflows/build.yml"
    
    if [ ! -d "$workflow_dir" ]; then
        warning "Repository directory not found: $workflow_dir"
        info "Create the repository first in Forgejo"
        return 0
    fi
    
    mkdir -p "$(dirname "$workflow_file")"
    
    cat > "$workflow_file" << 'EOF'
name: CI/CD Pipeline

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build-and-test:
    runs-on: linux
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          
      - name: Install dependencies
        run: npm ci
        
      - name: Lint
        run: npm run lint
        
      - name: Type check
        run: npm run type-check
        
      - name: Build
        run: npm run build
        
      - name: Run tests
        run: npm run test
        
      - name: Upload build artifacts
        uses: actions/upload-artifact@v4
        with:
          name: dist
          path: .output/
          
  deploy:
    needs: build-and-test
    runs-on: linux
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Download artifacts
        uses: actions/download-artifact@v4
        with:
          name: dist
          
      - name: Deploy to server
        run: |
          rsync -avz ./ /srv/www/experience-portal/
          systemctl reload nginx
EOF
    
    success "Sample workflow created at $workflow_file"
}

create_manual_ci_script() {
    local script_path="/opt/gitea/ci-runner.sh"
    
    if [ -f "$script_path" ]; then
        warning "CI runner script already exists at $script_path"
        return 0
    fi
    
    log "Creating manual CI runner script..."
    
    cat > "$script_path" << 'EOF'
#!/bin/bash
# Manual CI Runner for Forgejo/Gitea
# Executes on post-receive hook or manually invoked

set -euo pipefail

# Configuration
REPO_NAME="experience-portal"
REPO_OWNER="rem"
DEPLOY_DIR="/srv/www/experience-portal"
LOG_FILE="/var/log/ci-runner.log"
BUILD_DIR="/tmp/ci-build-$(date +%s)"
ARTIFACT_DIR="/opt/ci-artifacts"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"
}

cleanup() {
    log "Cleaning up build directory: $BUILD_DIR"
    rm -rf "$BUILD_DIR"
}

trap cleanup EXIT

main() {
    log "=== Starting CI Run for $REPO_NAME ==="
    log "Build directory: $BUILD_DIR"
    
    # Clone repository
    log "Cloning repository..."
    git clone "/var/lib/forgejo/repos/$REPO_OWNER/$REPO_NAME.git" "$BUILD_DIR" || {
        error "Failed to clone repository"
    }
    
    cd "$BUILD_DIR"
    
    # Get commit info
    COMMIT_HASH=$(git rev-parse --short HEAD)
    COMMIT_MSG=$(git log -1 --pretty=%B)
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    
    log "Commit: $COMMIT_HASH ($BRANCH)"
    log "Message: $COMMIT_MSG"
    
    # Check for package.json
    if [ ! -f "package.json" ]; then
        error "No package.json found"
    fi
    
    # Install dependencies
    log "Installing dependencies..."
    npm ci || {
        warning "npm ci failed, trying npm install..."
        npm install || error "Failed to install dependencies"
    }
    
    # Run linting
    log "Running linting..."
    if grep -q '"lint"' package.json; then
        npm run lint || warning "Linting failed"
    else
        log "No lint script found, skipping"
    fi
    
    # Run type check
    log "Running type check..."
    if grep -q '"type-check"' package.json; then
        npm run type-check || error "Type check failed"
    elif grep -q '"typecheck"' package.json; then
        npm run typecheck || error "Type check failed"
    else
        log "No type check script found, skipping"
    fi
    
    # Build project
    log "Building project..."
    if grep -q '"build"' package.json; then
        npm run build || error "Build failed"
    else
        error "No build script found in package.json"
    fi
    
    # Deploy
    log "Deploying to $DEPLOY_DIR..."
    mkdir -p "$DEPLOY_DIR"
    rsync -a --delete ./.output/ "$DEPLOY_DIR/" || error "Deployment failed"
    
    # Set permissions
    chown -R www-data:www-data "$DEPLOY_DIR"
    chmod -R 755 "$DEPLOY_DIR"
    
    # Save artifacts
    mkdir -p "$ARTIFACT_DIR"
    tar -czf "$ARTIFACT_DIR/build-$COMMIT_HASH.tar.gz" -C . .output/
    
    # Log success
    success "CI run completed successfully"
    log "Artifact saved to: $ARTIFACT_DIR/build-$COMMIT_HASH.tar.gz"
    
    # Send notification
    send_notification "success" "$COMMIT_HASH" "$BRANCH"
}

send_notification() {
    local status="$1"
    local commit="$2"
    local branch="$3"
    
    # Example notification - extend with your preferred method
    # Discord webhook, email, Slack, etc.
    
    local message="CI/CD Run $status\n"
    message+="Repository: $REPO_NAME\n"
    message+="Branch: $branch\n"
    message+="Commit: $commit\n"
    message+="Time: $(date '+%Y-%m-%d %H:%M:%S')"
    
    echo -e "$message" >> "$LOG_FILE"
    
    # Example Discord webhook (uncomment and configure)
    # curl -H "Content-Type: application/json" \
    #   -X POST \
    #   -d "{\"content\":\"$message\"}" \
    #   https://discord.com/api/webhooks/YOUR_WEBHOOK_URL
}

# Run main function
main "$@"
EOF
    
    chmod +x "$script_path"
    chown git:git "$script_path"
    
    success "Manual CI runner script created at $script_path"
}

setup_post_receive_hook() {
    local hook_file="/var/lib/forgejo/repos/rem/experience-portal.git/hooks/post-receive"
    
    if [ -f "$hook_file" ]; then
        warning "Post-receive hook already exists"
        return 0
    fi
    
    log "Creating post-receive hook..."
    
    cat > "$hook_file" << 'EOF'
#!/bin/bash
# Post-receive hook for automatic CI triggering

set -euo pipefail

REPO_NAME="experience-portal"
CI_SCRIPT="/opt/gitea/ci-runner.sh"
LOG_FILE="/var/log/git-hooks.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Only run CI for pushes to main branch
while read oldrev newrev refname; do
    branch=$(git rev-parse --symbolic --abbrev-ref "$refname")
    
    if [ "$branch" = "main" ]; then
        log "Triggering CI for $REPO_NAME ($branch:$newrev)"
        
        # Run CI in background
        nohup "$CI_SCRIPT" >> "$LOG_FILE" 2>&1 &
        
        log "CI triggered (PID: $!)"
    fi
done
EOF
    
    chmod +x "$hook_file"
    chown git:git "$hook_file"
    
    success "Post-receive hook created"
}

show_summary() {
    echo ""
    echo "=== Forgejo CI/CD Setup Summary ==="
    echo ""
    echo "✅ Actions enabled in Forgejo config"
    echo "✅ Runner directory created: /opt/forgejo-runner"
    echo "✅ Runner binary downloaded"
    echo "✅ Systemd service created: forgejo-runner.service"
    echo "✅ Sample workflow created"
    echo "✅ Manual CI runner script: /opt/gitea/ci-runner.sh"
    echo "✅ Post-receive hook configured"
    echo ""
    echo "=== Next Steps ==="
    echo ""
    echo "1. Edit /etc/systemd/system/forgejo-runner.service:"
    echo "   - Set GITHUB_TOKEN"
    echo "   - Set FORGEJO_RUNNER_REGISTRATION_TOKEN"
    echo ""
    echo "2. Get registration token from Forgejo:"
    echo "   - Go to Settings → Actions → Runners"
    echo "   - Click 'Add Runner' and copy the token"
    echo ""
    echo "3. Start the runner service:"
    echo "   sudo systemctl enable --now forgejo-runner"
    echo ""
    echo "4. Test the setup by pushing to your repository"
    echo ""
    echo "5. Configure notifications in ci-runner.sh"
    echo ""
}

main() {
    echo "=== Forgejo CI/CD Setup ==="
    echo ""
    
    check_root
    check_forgejo_installed
    
    log "Starting setup..."
    
    enable_actions
    setup_runner_directory
    install_runner_binary
    create_runner_service
    create_sample_workflow
    create_manual_ci_script
    setup_post_receive_hook
    
    success "Setup completed!"
    
    show_summary
    
    log "Remember to restart Forgejo for configuration changes:"
    echo "sudo systemctl restart forgejo"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi