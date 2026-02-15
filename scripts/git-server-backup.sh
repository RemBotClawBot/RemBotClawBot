#!/bin/bash
# git-server-backup.sh - Backup script for Gitea/Forgejo instances
# Creates consistent backups with retention policy

set -euo pipefail

# Configuration
BACKUP_DIR="/opt/gitea/backups"
RETENTION_DAYS=7
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/forgejo_backup_${DATE}.zip"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

error() {
    echo -e "${RED}[✗]${NC} $1"
}

check_prerequisites() {
    # Check if forgejo-cli is available
    if ! command -v forgejo &> /dev/null; then
        error "forgejo command not found"
        return 1
    fi
    
    # Check backup directory
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        success "Created backup directory: $BACKUP_DIR"
    fi
    
    # Ensure permissions
    chmod 700 "$BACKUP_DIR"
}

create_backup() {
    echo "Creating Forgejo backup..."
    
    # Stop Forgejo for consistent backup (optional - comment out for hot backup)
    # systemctl stop forgejo
    
    # Create backup using forgejo dump
    if forgejo dump --config /etc/forgejo/app.ini --file "$BACKUP_FILE"; then
        success "Backup created successfully: $BACKUP_FILE"
        
        # Get backup size
        local size=$(du -h "$BACKUP_FILE" | cut -f1)
        echo "Backup size: $size"
        
        # Verify backup integrity
        if unzip -t "$BACKUP_FILE" &> /dev/null; then
            success "Backup integrity verified"
        else
            error "Backup integrity check failed!"
            return 1
        fi
    else
        error "Backup creation failed!"
        return 1
    fi
    
    # Start Forgejo if we stopped it
    # systemctl start forgejo
}

backup_database_only() {
    # Alternative: Database-only backup
    local db_backup="${BACKUP_DIR}/forgejo_db_${DATE}.sql"
    
    # Extract database config from app.ini
    local db_type=$(grep -A 5 "^\[database\]" /etc/forgejo/app.ini | grep "^DB_TYPE" | cut -d= -f2 | tr -d ' ')
    local db_host=$(grep -A 5 "^\[database\]" /etc/forgejo/app.ini | grep "^HOST" | cut -d= -f2 | tr -d ' ')
    local db_name=$(grep -A 5 "^\[database\]" /etc/forgejo/app.ini | grep "^NAME" | cut -d= -f2 | tr -d ' ')
    local db_user=$(grep -A 5 "^\[database\]" /etc/forgejo/app.ini | grep "^USER" | cut -d= -f2 | tr -d ' ')
    
    case "$db_type" in
        "mysql"|"mariadb")
            echo "Creating MySQL database backup..."
            mysqldump -h "$db_host" -u "$db_user" -p "$db_name" > "$db_backup"
            success "MySQL backup created: $db_backup"
            ;;
        "postgres")
            echo "Creating PostgreSQL database backup..."
            PGPASSWORD=$(grep "^PASSWD" /etc/forgejo/app.ini | cut -d= -f2 | tr -d ' ') \
                pg_dump -h "$db_host" -U "$db_user" "$db_name" > "$db_backup"
            success "PostgreSQL backup created: $db_backup"
            ;;
        "sqlite3")
            echo "Creating SQLite database backup..."
            local db_path=$(grep "^PATH" /etc/forgejo/app.ini | cut -d= -f2 | tr -d ' ')
            cp "$db_path" "${BACKUP_DIR}/$(basename "$db_path")_${DATE}.db"
            success "SQLite backup created"
            ;;
        *)
            warning "Unknown database type: $db_type"
            ;;
    esac
}

backup_repositories() {
    # Backup repository data directory
    local repo_backup="${BACKUP_DIR}/repositories_${DATE}.tar.gz"
    local repo_path="/var/lib/gitea/repositories"
    
    if [ -d "$repo_path" ]; then
        echo "Backing up repositories..."
        tar -czf "$repo_backup" -C "$(dirname "$repo_path")" "$(basename "$repo_path")"
        success "Repository backup created: $repo_backup"
        
        local size=$(du -h "$repo_backup" | cut -f1)
        echo "Repository backup size: $size"
    else
        warning "Repository directory not found: $repo_path"
    fi
}

apply_retention_policy() {
    echo "Applying retention policy (${RETENTION_DAYS} days)..."
    
    # Find and delete old backups
    find "$BACKUP_DIR" -name "forgejo_backup_*.zip" -mtime +$RETENTION_DAYS -delete
    find "$BACKUP_DIR" -name "forgejo_db_*.sql" -mtime +$RETENTION_DAYS -delete
    find "$BACKUP_DIR" -name "repositories_*.tar.gz" -mtime +$RETENTION_DAYS -delete
    
    local remaining=$(find "$BACKUP_DIR" -type f -name "*.zip" -o -name "*.sql" -o -name "*.tar.gz" | wc -l)
    success "Retention policy applied. $remaining backup files remaining"
}

generate_report() {
    local report_file="${BACKUP_DIR}/backup_report_${DATE}.txt"
    
    cat > "$report_file" << EOF
=== Forgejo Backup Report ===
Timestamp: $(date)
Backup File: $(basename "$BACKUP_FILE")
Location: $BACKUP_DIR

=== System Information ===
Hostname: $(hostname)
Disk Usage: $(df -h / | awk 'NR==2 {print $5}')
Available Space: $(df -h / | awk 'NR==2 {print $4}')

=== Backup Details ===
Backup Size: $(du -h "$BACKUP_FILE" | cut -f1)
Total Backups: $(find "$BACKUP_DIR" -name "*.zip" | wc -l)
Retention: ${RETENTION_DAYS} days

=== Status ===
$(if [ $? -eq 0 ]; then echo "SUCCESS: Backup completed successfully"; else echo "FAILURE: Backup encountered errors"; fi)
EOF
    
    success "Report generated: $report_file"
    cat "$report_file"
}

main() {
    echo "=== Forgejo/Gitea Backup Script ==="
    echo "Started: $(date)"
    
    # Check prerequisites
    check_prerequisites || exit 1
    
    # Create backup
    create_backup || exit 1
    
    # Additional backup types
    backup_database_only
    backup_repositories
    
    # Apply retention policy
    apply_retention_policy
    
    # Generate report
    generate_report
    
    echo ""
    echo "=== Backup Complete ==="
    echo "Finished: $(date)"
    echo "Backup location: $BACKUP_DIR"
    
    # List all backups
    echo ""
    echo "Current backups:"
    ls -lh "$BACKUP_DIR"/*.zip 2>/dev/null | head -10
}

# Handle command line arguments
case "${1:-}" in
    "database-only")
        check_prerequisites
        backup_database_only
        apply_retention_policy
        ;;
    "repos-only")
        check_prerequisites
        backup_repositories
        apply_retention_policy
        ;;
    "report")
        generate_report
        ;;
    *)
        main
        ;;
esac