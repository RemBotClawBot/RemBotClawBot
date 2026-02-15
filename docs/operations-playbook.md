# Operations Playbook

This playbook outlines how Rem executes day-to-day operations, including proactive monitoring, incident response, and communication protocols.

## 1. Daily Rhythm

| Timeframe | Activity | Details |
|-----------|----------|---------|
| 08:00 UTC | Morning heartbeat | Run system health checks, skim logs, update memory. |
| 12:00 UTC | Project sync | Review CI/CD status, repository activity, outstanding tasks. |
| 16:00 UTC | Security sweep | Audit access logs, verify firewall + SSH posture. |
| 20:00 UTC | Memory maintenance | Curate learnings into `MEMORY.md`, archive completed tasks. |

## 2. Heartbeat Checklist

1. Read `HEARTBEAT.md` for the current list of checks.
2. Execute `scripts/health-check.sh` for infrastructure state.
3. Confirm Forgejo (3001) and fallback Gitea (3000) ports respond.
4. Inspect CI pipelines (manual runner logs, Nuxt builds, etc.).
5. Review `/var/log/auth.log` for failed logins or suspicious activity.
6. Update `memory/YYYY-MM-DD.md` with findings; escalate anomalies via main session.

## 3. Incident Response

**Trigger Examples:**
- Git server unreachable
- CI runner stuck or failing consecutively
- Security anomalies (unexpected logins, config drift)

**Response Steps:**
1. **Detect:** Alert raised by heartbeat, cron, or manual observation.
2. **Diagnose:** Collect logs, run targeted script (`health-check`, `git-server-backup`, etc.).
3. **Stabilize:** Restart services, rollback configs, or fail over to backup instance.
4. **Document:** Capture root cause + fix in daily memory; update `MEMORY.md` if long-term relevant.
5. **Report:** Summarize incident + remediation in user-facing channel when resolved.

## 4. Communication Protocol

- **Proactive Reports:** Share meaningful updates (downtime, deploys, security notices). Avoid noise.
- **Silence Windows:** Between 23:00–08:00 UTC unless urgent.
- **Tone:** Direct, factual, actionable. Skip pleasantries; focus on resolution.
- **External Actions:** Request confirmation before sending emails or posts outside trusted surfaces.

## 5. Change Management

1. **Plan:** Outline change (e.g., Forgejo upgrade) with rollback steps.
2. **Backup:** Use `git-server-backup.sh` before invasive operations.
3. **Execute:** Apply change during low-traffic windows.
4. **Validate:** Run smoke tests (git push, login, CI job) post-change.
5. **Record:** Log change summary + verification results.

## 6. Access Governance

- Maintain admin users: `Rem`, `Gerard`. Rotate credentials quarterly.
- Follow CTO Veld's directives for identity disputes.
- Remove unused accounts promptly; archive their repositories.
- Store secrets in environment-specific vault (not in git).

## 7. Tooling Matrix

| Tool | Purpose | Notes |
|------|---------|-------|
| `scripts/health-check.sh` | Infra pulse check | Integrate with cron/heartbeats. |
| `scripts/git-server-backup.sh` | Forgejo backup | Default retention 7 days. |
| `examples/openclaw_api_example.py` | API-driven reporting | Produces JSON + text reports. |
| `openclaw` CLI | Core control plane | `openclaw status`, `openclaw cron`, etc. |

## 8. Future Enhancements

- Automate incident templates for faster reporting.
- Add self-healing actions (auto-restart Forgejo when unhealthy).
- Build Grafana dashboard fed by script outputs.
- Integrate with secrets management (e.g., HashiCorp Vault) for runtime credentials.

---
*Last updated: 2026-02-15*