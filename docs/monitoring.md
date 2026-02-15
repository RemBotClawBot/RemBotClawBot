# Monitoring & Observability Guide

This guide explains how Rem captures, exports, and visualizes operational telemetry across OpenClaw, Forgejo, and supporting infrastructure.

## 1. Monitoring Objectives

1. **Availability:** Detect outages on OpenClaw gateway, Forgejo (3001), and legacy Gitea (3000) within 60 seconds.
2. **Performance:** Track disk/memory utilization, load averages, and CI runner queue depth.
3. **Security:** Surface failed SSH logins, firewall state, and certificate expirations.
4. **Compliance:** Maintain auditable health reports stored for ≥14 days.

## 2. Data Sources

| Source | Signals | Notes |
|--------|---------|-------|
| `scripts/health-check.sh` | Service reachability, disk/memory, SSH/login anomalies. | Use for on-demand troubleshooting or cron-based sweeps. |
| `examples/openclaw_api_example.py` | Structured JSON/HTML health snapshots. | Powers dashboards + webhook payloads. |
| `scripts/monitor-openclaw.sh` | Continuous watchdog w/ restart + escalation hooks. | Ideal for systemd service or tmux session. |
| `scripts/generate-health-report.sh` | Automated report generation, retention, and notifications. | Bundles multiple formats + webhook summary. |
| Forgejo/Gitea logs | HTTP status, auth attempts, Actions queue depth. | Ship to centralized logging for correlation. |

## 3. Health Report Pipeline

1. **Collect:** `generate-health-report.sh` calls `openclaw_api_example.py --health` to capture JSON, HTML, and text reports.
2. **Store:** Artifacts land in `reports/` (default) with ISO8601 timestamp naming.
3. **Retain:** Older files pruned automatically via `RETENTION_DAYS` (default 14).
4. **Notify:** Optional webhook receives summarized payload (OpenClaw status, disk %, memory %, Forgejo/Gitea state).

```bash
# Example cron entry (runs every 2 hours)
0 */2 * * * /opt/rembot/scripts/generate-health-report.sh \
  -o /opt/rembot/reports -f json,html >> /var/log/rembot-health.log 2>&1
```

JSON Schema excerpt:
```json
{
  "timestamp": "2026-02-15T15:42:10Z",
  "openclaw_status": {"Status": "running"},
  "gateway": {"output": "Gateway daemon: running"},
  "git_servers": {
    "forgejo": {"port": 3001, "status": true},
    "gitea": {"port": 3000, "status": true}
  },
  "disk": {"percent_used": 24.1, "free_gb": 380.2},
  "memory": {"percent_used": 31.5, "available_gb": 11.2}
}
```

## 4. Dashboard Patterns

### Grafana Panels
- **Status Board:** Display Forgejo/Gitea uptime using Prometheus `up{job="rembot"}` metrics.
- **Resource Cards:** Map disk/memory percentages from exported JSON via Loki/Promtail ingestion.
- **CI Queue Depth:** Use Forgejo Actions API metrics (queue length) to trigger autoscaling (see README auto-scaling example).

### HTML Snapshot
`openclaw_api_example.py --health --html > health.html` produces a dark-themed dashboard with platform status cards, resource grids, and git-service tables. Host it via Nginx/basic auth or attach to weekly status emails.

## 5. Alerting Strategy

| Trigger | Detection Method | Response |
|---------|------------------|----------|
| OpenClaw gateway stops | `monitor-openclaw.sh --auto-restart` + webhook | Restart service, send Discord/Slack alert.
| Forgejo port unreachable | JSON export consumed by Prometheus alertmanager | Page on-call (PagerDuty) and fail over to backup node.
| Disk usage > 80% | Alert rule on `disk.percent_used` | Invoke cleanup script + notify infra channel.
| SSH brute force | Fail2Ban + webhook integration | Block offending IPs, attach log excerpt to report.

Sample Alertmanager rule:
```yaml
- alert: RemBotDiskHigh
  expr: rembot_disk_used_percent > 80
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Disk usage high on {{ $labels.instance }}"
```

## 6. Integrations

- **Slack/Discord:** Point `WEBHOOK_URL` in `generate-health-report.sh` to team channel for continuous awareness.
- **PagerDuty:** Use Alertmanager or monitor-openclaw webhook stub to invoke PD events for Severity 1 incidents.
- **S3/Archive:** Sync `reports/*.json` to object storage for compliance (e.g., `aws s3 sync reports/ s3://rembot-health/`).
- **CI/CD:** Add a `reports` artifact upload step in GitHub Actions to keep historical logs per run.

## 7. Troubleshooting Checklist

1. **Missing `psutil`:** `pip install psutil` (script will fail fast with helpful message).
2. **Webhook errors:** Script echoes warning + retains reports locally; inspect `/var/log/rembot-health.log`.
3. **Permission denied:** Run under service account with access to `/opt/rembot` and target output directory.
4. **Stale data:** Confirm cron/systemd timers are enabled; verify `reports/` timestamps.
5. **No metrics ingestion:** Ensure JSON exported to location scraped by Promtail/Fluent Bit.

---
*Last updated: 2026-02-15*
