# Automation Toolkit

This document explains the automation assets included in the RemBotClawBot repository and how to operationalize them in an OpenClaw deployment.

## 1. Directory Layout

```
scripts/
├─ health-check.sh         # Comprehensive infrastructure + security probe
├─ git-server-backup.sh    # Forgejo/Gitea snapshot utility with retention
├─ monitor-openclaw.sh     # Watchdog that restarts OpenClaw + services
├─ forgejo-ci-setup.sh     # End-to-end Forgejo Actions + manual CI bootstrapper
├─ secure-firewall.sh      # UFW + Fail2Ban hardening with reporting
examples/
├─ openclaw_api_example.py # Python client for querying OpenClaw + infra
└─ secure-reverse-proxy.yml# IaC template + scripts for hardened Nginx
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

## 4. `monitor-openclaw.sh`

**Purpose:** Supervises the OpenClaw process, gateway service, git ports, and resource headroom; optionally restarts services and emits notifications.

### Highlights
- Runs one-shot health checks or continuous monitoring loops.
- Configurable retry count, interval, and auto-restart behavior.
- Sends stubbed notifications (extend with Slack/Discord/webhook integrations).
- Tracks disk + memory thresholds alongside port probes for Forgejo/Gitea.
- Provides `--single-check`, `--once`, and daemonized loop modes for cron/systemd timers.

### Usage
```bash
chmod +x scripts/monitor-openclaw.sh
./scripts/monitor-openclaw.sh --single-check
./scripts/monitor-openclaw.sh --auto-restart --interval 30 --notify
```

**Systemd Service Stub:**
```ini
[Service]
ExecStart=/opt/rembot/scripts/monitor-openclaw.sh --auto-restart --notify
Restart=always
```

## 5. `forgejo-ci-setup.sh`

**Purpose:** Opinionated bootstrapper that enables Forgejo Actions, installs runners, seeds workflows, and wires manual CI fallbacks.

### What it does
1. Enables the `[actions]` stanza in `/etc/forgejo/app.ini`.
2. Creates `/opt/forgejo-runner`, downloads the proper runner binary, and registers a systemd service template.
3. Seeds `.github/workflows/build.yml` inside `experience-portal` with lint/test/build/deploy jobs.
4. Drops `/opt/gitea/ci-runner.sh` for manual builds + deployments (artifact retention, notifications, sanitized logs).
5. Installs a `post-receive` hook that triggers the manual runner when `main` receives new commits.

### Usage
```bash
sudo chmod +x scripts/forgejo-ci-setup.sh
sudo ./scripts/forgejo-ci-setup.sh
```
Follow the printed "Next Steps" section to inject runner registration tokens and start the service:
```bash
sudo systemctl enable --now forgejo-runner
```

## 6. `secure-firewall.sh`

**Purpose:** Hardens network boundaries using UFW + Fail2Ban with interactive prompts and detailed reporting.

### Capabilities
- Enforces "deny incoming / allow outgoing" defaults and safe service allow-lists.
- Adds rate limiting for SSH/HTTP/HTTPS via `ufw-before-input` rules.
- Integrates Fail2Ban with custom jail + filter tied to UFW logs.
- Configures log rotation, verbose status, and optional database/monitoring ports.
- Generates a comprehensive `/var/log/firewall-setup-*.log` report summarizing rules, listening sockets, and recommendations.

### Usage
```bash
sudo chmod +x scripts/secure-firewall.sh
sudo SSH_PORT=2222 ./scripts/secure-firewall.sh
```

## 7. `examples/openclaw_api_example.py`

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

## 8. `examples/secure-reverse-proxy.yml`

**Purpose:** Turn-key Infrastructure-as-Code bundle that provisions a hardened Nginx reverse proxy, automated Let's Encrypt certificates, and a follow-on hardening routine.

### Contents
- Production-ready Nginx vhost template with HSTS, CSP, rate limiting, WebSocket handling, health and metrics endpoints, plus service-specific routing (OpenClaw, Forgejo, Nuxt portal).
- `setup-letsencrypt.sh` helper that installs Certbot, obtains certificates, and wires renewal hooks.
- `harden-nginx.sh` script that applies security headers globally, enables JSON logging, adds timeout + connection limits, and secures the default site.

### Usage Tips
1. Copy the Nginx server block to `/etc/nginx/sites-available/secure-proxy` and adjust hostnames/IPs.
2. Run the SSL setup helper to request certificates and configure renewals.
3. Execute the hardening script to apply global defense-in-depth controls.
4. Validate with `nginx -t && systemctl reload nginx`.

## 9. Operational Recommendations

1. **Version Control:** Keep scripts in git to track changes and facilitate code review.
2. **Permissions:** Run operational scripts with least privilege possible; consider dedicated service accounts.
3. **Logging:** Pipe outputs to `/var/log` and ship to a centralized log stack (Loki, Elastic, etc.).
4. **Alerting:** Combine cron exit codes with `systemd` service units or monitoring tools to raise alerts on failure.
5. **Dry Runs:** Test backup restores periodically to ensure integrity.
6. **IaC Parity:** Keep shell automations paired with Nginx/firewall templates so environments stay reproducible.

## 10. Roadmap

- Add Ansible playbooks wrapping the shell scripts for wider rollout.
- Expand health checks to include Prometheus endpoint probing and SSL expiry monitoring.
- Introduce JSON output mode for easier ingestion into dashboards.
- Provide containerized versions of the scripts for immutable infrastructure.
- Publish Terraform snippets that deploy the reverse proxy and firewall policies alongside the application stack.

---
*Last updated: 2026-02-15*
