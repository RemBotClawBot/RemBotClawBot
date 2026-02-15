# RemBotClawBot Architecture

This document describes the technical architecture behind Rem — an OpenClaw-based operational assistant that manages infrastructure, security posture, and proactive automation.

## 1. High-Level Overview

```
+--------------------+        +-------------------+        +------------------+
|  Messaging Surfaces|  --->  |   OpenClaw Core   |  --->  |  Skills & Tools  |
|  (Discord, etc.)   |        |  (Rem Personality) |        |  (Automation)     |
+--------------------+        +-------------------+        +------------------+
          |                            |                            |
          |                            v                            v
          |                 +-------------------+        +------------------+
          |                 | Memory Subsystem  |        | Infrastructure    |
          |                 | (SOUL, USER, etc.)|        | (Forgejo, CI/CD)  |
          |                 +-------------------+        +------------------+
          v
+--------------------+
| Observability Stack|
| (Heartbeats, Logs) |
+--------------------+
```

1. **Messaging Surfaces** receive automation triggers (heartbeat polls) or user commands.
2. **OpenClaw Core** hosts the Rem persona, memory, and reasoning state.
3. **Skills & Tools** expose constrained automation (tmux, weather, Sonos, etc.).
4. **Memory Subsystem** persists identity (`SOUL.md`), user preferences, and curated knowledge (`MEMORY.md`).
5. **Infrastructure Layer** covers Forgejo/Gitea, CI runners, and supporting scripts.
6. **Observability Stack** combines heartbeats, logs, and cron jobs to create proactive alerts.

## 2. Memory & Persistence

| Artifact          | Purpose                                                   |
|-------------------|-----------------------------------------------------------|
| `SOUL.md`         | Defines identity, tone, and behavioral guardrails.        |
| `USER.md`         | Stores information about the human Rem supports.          |
| `MEMORY.md`       | Long-term curated knowledge, security notes, directives.  |
| `memory/YYYY-MM-DD.md` | Daily operational ledger (raw notes, incidents). |
| `HEARTBEAT.md`    | Checklist for recurring proactive checks.                 |

**Workflow:**
1. During heartbeats, Rem reviews `HEARTBEAT.md`, performs listed checks, and updates daily memory.
2. Significant learnings graduate from daily logs into `MEMORY.md` for persistence.
3. System identity is anchored by `SOUL.md` and `IDENTITY.md`, ensuring consistent behavior between sessions.

## 3. Infrastructure Footprint

- **Forgejo (port 3001):** Primary Git service with clean database and admin accounts (`Rem`, `Gerard`).
- **Gitea (port 3000):** Legacy instance retained as cold backup with data stored in `/opt/gitea/data.backup`.
- **Manual CI Runner:** `/opt/gitea/ci-runner.sh` orchestrates builds when Actions API is unavailable.
- **Experience Portal Repo:** Nuxt + TypeScript application showcasing OpenClaw interface work.
- **Backup Strategy:** `scripts/git-server-backup.sh` captures Forgejo data and repositories with retention enforcement.

## 4. Security Posture

- **Identity Verification:** CTO Veld is the authority for validating personnel accounts (Gerard vs. impersonators).
- **Competitor Awareness:** Xavin flagged as hostile actor; Yukine reinstated post-review. Identity incidents logged in `MEMORY.md`.
- **Access Controls:** Admin accounts created with strong credentials; multi-user repository ownership enforced.
- **Monitoring:** Heartbeats include log reviews (`/var/log/auth.log`), CI status, and git service reachability.
- **Hardening:** SSH root login disabled, firewall locked down to essential ports, auto security updates enabled.

## 5. Automation Surfaces

| Surface             | Purpose                                                | Example Trigger                          |
|---------------------|--------------------------------------------------------|-------------------------------------------|
| Heartbeats          | Routine system/security scan                          | Heartbeat prompt → run `health-check.sh`  |
| Cron Jobs           | Time-precise reminders or maintenance tasks            | Daily backup at 02:00 UTC                 |
| Manual Scripts      | Operational utilities (health, backup, diagnostics)    | `./scripts/health-check.sh`               |
| OpenClaw Skills     | Declarative tool integrations (weather, tmux, etc.)    | `weather` skill for proactive updates     |

## 6. Observability & Reporting

- **health-check.sh** prints colorized summaries: service status, disk/memory, OpenClaw gateway state, git reachability, security signals.
- **openclaw_api_example.py** demonstrates programmatic status gathering and report generation with JSON + human-readable output.
- **backup_report** files capture success/failure states for each Forgejo snapshot, enabling auditing.

## 7. Future Enhancements

- Add Prometheus exporters for Forgejo metrics and CI throughput.
- Automate doc sync between `README.md` highlights and `docs/` deep dives.
- Expand OpenClaw sub-agents for long-running maintenance tasks.
- Publish sanitized operational playbooks for public transparency.

---
*Last updated: 2026-02-15*