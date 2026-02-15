# Security Hardening Playbook

This document aggregates the defensive automation included in RemBotClawBot and shows how to apply it to perimeter services, git infrastructure, and OpenClaw itself.

## 1. Overview

| Asset | Path | Focus |
|-------|------|-------|
| Firewall hardening script | `scripts/secure-firewall.sh` | UFW defaults, rate limits, Fail2Ban integration, reporting |
| Reverse proxy IaC | `examples/secure-reverse-proxy.yml` | Nginx TLS, security headers, rate limiting, health endpoints |
| SSL automation helper | (within `secure-reverse-proxy.yml`) | Certbot provisioning + renewal cron |
| Nginx hardening helper | (within `secure-reverse-proxy.yml`) | Logging, timeouts, connection caps, default vhost lockdown |
| Fail2Ban jail pack | `examples/fail2ban-jails.conf` | Opinionated jail/filter definitions for SSH, Nginx, Forgejo, OpenClaw |

## 2. Firewall Hardening Workflow

1. **Preparation**
   - SSH into the host with sudo privileges.
   - Review existing `ufw status numbered` output and export a backup: `sudo ufw status numbered > ~/ufw-backup.txt`.
2. **Execution**
   - Run the script with optional overrides (e.g., custom SSH port):
     ```bash
     sudo SSH_PORT=2222 scripts/secure-firewall.sh
     ```
   - Respond to prompts regarding database, Redis, or monitoring exposure.
3. **Outcome**
   - UFW defaults to `deny incoming/allow outgoing`.
   - Rate limits throttle brute-force attempts on SSH/HTTP/HTTPS.
   - Fail2Ban monitors `/var/log/ufw.log` with a dedicated jail.
   - `/var/log/firewall-setup-*.log` captures the rule summary, listening sockets, and recommendations.
4. **Next Steps**
   - Tail `/var/log/ufw.log` for blocked attempts.
   - Confirm services are reachable from expected networks only.
   - Store the generated report alongside runbooks for auditing.

## 2.1. Fail2Ban Profiles

Drop `examples/fail2ban-jails.conf` into `/etc/fail2ban/jail.d/` to apply hardened defaults for SSH, Nginx, Forgejo, and the OpenClaw API. The file bundles:

- Dedicated jails for brute-force, botsearch, bad requests, and rate-limit violations
- Custom filters for Forgejo and OpenClaw log formats
- Recidive handling and UFW tie-ins
- Email alerts via the bundled `action_mwl` template

Adjust `destemail`, `sender`, and any port numbers before reloading Fail2Ban (`sudo systemctl restart fail2ban`).

## 3. Reverse Proxy Blueprint

`examples/secure-reverse-proxy.yml` bundles a hardened Nginx server block plus two helper scripts. Highlights include:

- **TLS Everywhere:** HTTP→HTTPS redirect, TLS 1.2/1.3 ciphers, and HSTS preloading.
- **Security Headers:** CSP baseline, XFO, X-Content-Type-Options, Referrer-Policy, Permissions-Policy.
- **Rate Limiting:** Dedicated `limit_req_zone` for API surfaces and global request throttling to blunt DDoS bursts.
- **Service Isolation:** Separate locations for OpenClaw API, Forgejo, and the Nuxt “experience portal,” each with tailored proxy settings and caching rules.
- **Observability:** `/health` JSON endpoint and `/metrics` upstream passthrough for Prometheus.
- **Abuse Prevention:** Blocks WordPress artifacts, sensitive file extensions, and unknown default traffic with a catch-all.

### Deployment Steps

1. Copy the server block into `/etc/nginx/sites-available/secure-proxy` and symlink it under `sites-enabled`.
2. Run the bundled `setup-letsencrypt.sh` to install Certbot, answer ACME challenges, and configure renewals via `/etc/cron.weekly/letsencrypt-renew`.
3. Execute `harden-nginx.sh` to apply global headers, logging, rate limiting, and timeout policies.
4. Validate with `nginx -t` and reload: `sudo systemctl reload nginx`.
5. Monitor `/var/log/nginx/secure-proxy-access.log` (JSON format) for anomalies and feed into a log stack.

## 4. Operational Tips

- **Layered Controls:** Use the firewall to restrict management ports (SSH, runner APIs) while the reverse proxy enforces app-layer policies.
- **Automation Hooks:** Pair `secure-firewall.sh` with cron/systemd timers for periodic audits, or run it ad hoc after provisioning new hosts.
- **Secret Handling:** Templates intentionally omit secrets; populate tokens/hostnames via environment variables or CI/CD at deploy time.
- **Testing:** Leverage tools like `sslyze`, `nmap --script ssl-enum-ciphers`, and `curl -I` to verify TLS + header posture after changes.
- **Documentation:** Archive generated reports and Nginx configs in a private repo to maintain change history.

## 5. Roadmap

- Add Ansible roles that wrap both scripts for fleet deployments.
- Publish sample Fail2Ban filters for Forgejo and OpenClaw logs.
- Extend the reverse proxy template with ACME DNS-01 automation for wildcard certs.
- Provide Terraform modules for provisioning security groups + load balancers that mirror these rules in cloud environments.

---
*Last updated: 2026-02-15*
