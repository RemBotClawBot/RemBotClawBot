# Automation Toolkit

This document explains the automation assets included in the RemBotClawBot repository and how to operationalize them in an OpenClaw deployment.

## 1. Directory Layout

```
scripts/
├─ health-check.sh        # Comprehensive infrastructure + security probe
├─ git-server-backup.sh   # Forgejo/Gitea snapshot utility with retention
examples/
└─ openclaw_api_example.py # Python client for querying OpenClaw + infra
```

## 2. `health-check.sh`

**Purpose:** Lightweight diagnostic sweep covering system resources, OpenClaw gateway health, git servers, CI runner presence, and basic security hygiene.

### Features
- Colorized output with timestamps for readable logs.
- Disk usage + memory availability thresholds.
- `systemctl` service checks (SSH, OpenClaw, Forgejo).
- Port reachability tests for Forgejo (3001) and legacy Gitea (3000).
- CI runner validation (`/opt/gitea/ci-runner.sh`).
- Security signals: SSH hardening, firewall state, recent failed logins.
- Summary block with uptime, load averages, and overall health verdict.

### Usage
```bash
chmod +x scripts/health-check.sh
sudo ./scripts/health-check.sh | tee /var/log/rem-health.log
```

**Cron Example (every 4 hours):**
```cron
0 */4 * * * /usr/local/bin/rembot/scripts/health-check.sh \
  >> /var/log/rem-health.log 2>&1
```

## 3. `git-server-backup.sh`

**Purpose:** Creates consistent backups of Forgejo (and legacy Gitea) including repositories, database dumps, and integrity reports.

### Features
- Configurable backup directory + retention window (default 7 days).
- Uses `forgejo dump` for full snapshots, with optional database-only or repos-only modes.
- Integrity verification (`unzip -t`), size reporting, and permission hardening.
- Repository tarball backups (`/var/lib/gitea/repositories`).
- Generates timestamped report summarizing disk usage, backup size, and status.

### Usage
```bash
chmod +x scripts/git-server-backup.sh
sudo ./scripts/git-server-backup.sh            # Full backup
sudo ./scripts/git-server-backup.sh database-only
sudo ./scripts/git-server-backup.sh repos-only
```

**Cron Example (02:00 UTC nightly):**
```cron
0 2 * * * /usr/local/bin/rembot/scripts/git-server-backup.sh \
  >> /var/log/rem-backups.log 2>&1
```

### Requirements
- `forgejo` CLI in `$PATH`
- Sufficient disk space in `/opt/gitea/backups` (configurable inside script)
- Optional: Database client tools (`mysqldump`, `pg_dump`) depending on backend

## 4. `examples/openclaw_api_example.py`

**Purpose:** Demonstrates how to script against OpenClaw using Python for health reporting, gateway monitoring, and git server status checks.

### Capabilities
- Wraps the `openclaw` CLI with a typed client.
- Fetches status, gateway state, cron info, and health checks.
- Performs socket checks for Forgejo/Gitea, disk/memory inspection via `shutil` + `psutil`.
- Generates JSON output or human-readable summaries.

### Usage
```bash
python3 examples/openclaw_api_example.py --health --report
python3 examples/openclaw_api_example.py --status
python3 examples/openclaw_api_example.py --git
```

### Dependencies
- Python 3.10+
- `psutil` (`pip install psutil`)

## 5. Operational Recommendations

1. **Version Control:** Keep scripts in git to track changes and facilitate code review.
2. **Permissions:** Run operational scripts with least privilege possible; consider dedicated service accounts.
3. **Logging:** Pipe outputs to `/var/log` and ship to a centralized log stack (Loki, Elastic, etc.).
4. **Alerting:** Combine cron exit codes with `systemd` service units or monitoring tools to raise alerts on failure.
5. **Dry Runs:** Test backup restores periodically to ensure integrity.

## 6. Roadmap

- Add Ansible playbooks wrapping the shell scripts for wider rollout.
- Expand health checks to include Prometheus endpoint probing and SSL expiry monitoring.
- Introduce JSON output mode for easier ingestion into dashboards.
- Provide containerized versions of the scripts for immutable infrastructure.

---
*Last updated: 2026-02-15*