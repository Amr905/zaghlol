# ADR-025: Self-hosted single-server deployment

| | |
|---|---|
| Status | Proposed (built by batch 53; PO confirms) |
| Date | 2026-11-21 |
| Deciders | Product owner (no cloud provider, D-76), backend-engineer |
| References | ADR-015 (hosting region, provider-neutral), ADR-022, ADR-023 (key custody); `deployment.md` section 6; `backend/deploy/server/` |

## Context
ADR-015 kept the design provider-neutral and `backend/deploy/terraform` plus `backend-deploy.yml` assume a cloud. The product owner can't use a cloud
provider. ADR-023 already made key custody self-hostable. What was missing was the rest: database, TLS, deploys, backups, hardening.

## Options considered
1. **One Linux server, Docker Compose** (chosen). Fewest moving parts, fits the base topology (500k installs, about 100k daily syncs, backend-schema section 5).
2. **Kubernetes (k3s) on one or several hosts.** More capability (rolling updates, scheduling) for a service of this size, with an operations burden the team doesn't have.
3. **Two hosts with Patroni/streaming replication.** Real failover, but doubles cost and operations; the app works without the backend (NFR-BE-01), so a few hours of downtime is tolerable.
4. **Nginx or Traefik instead of Caddy.** Same job; Caddy gives automatic Let's Encrypt with the shortest configuration.

## Decision
Option 1:
- **Compose stack** `backend/deploy/server/docker-compose.prod.yml`: postgres:17, migrate, api (2 replicas), worker, Caddy, optional collector/Prometheus/Alertmanager/Grafana; images by digest; non-root, read-only roots, `no-new-privileges`, no core dumps; fixed subnet for exact `ForwardedHeaders` trust.
- **Caddy** terminates TLS (Let's Encrypt), is the only published service, limits bodies and timeouts, masks client addresses in logs, restricts `/admin/*` to listed networks and serves the signed catalog snapshots as static files.
- **Backups:** nightly `pg_dump` + base backup, WAL archive to a local folder (14-day PITR), rsync/ssh mirror to an off-server target, systemd timer, `restore.sh` and a quarterly drill. Plain `archive_command` rather than pgBackRest: no extra component, enough for one small database; revisit if the database grows past tens of GB.
- **Deploys:** a GitHub workflow with a protected environment builds the image, pushes it to GHCR, ships `backend/deploy` over SSH (pinned host key) and runs `deploy.sh` (migrate, restart, smoke, automatic rollback to the previous digest).
- **Hardening script** (`harden.sh`, idempotent): ufw, SSH keys only, unattended upgrades, swap off, no core dumps, Docker log rotation, folder owners and modes required by ADR-023.
- **Keys:** File KMS first, OpenBao Transit before Gold is sold (ADR-023); both fit the same compose file through the existing override.

## Consequences
- No cloud account is needed; monthly cost is one server plus an off-server backup target.
- Single point of failure: host loss means a restore (RTO about 4 h if the drill is kept current; RPO about 5 minutes with WAL archiving mirrored off-server, otherwise up to a day).
- The deploy key is effectively root on the host; it lives only in a GitHub environment with a required reviewer.
- A load-balanced, multi-host, or cloud setup stays possible later: the images, settings and migrations are unchanged (the OpenTofu files remain as the cloud alternative).
- Questions for the PO: hosting site and legal location (CR-03), the off-server backup target, who holds the offline key media, and the alert e-mail address.
