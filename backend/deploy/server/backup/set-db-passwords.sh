#!/bin/bash
# Re-applies or rotates the five database login passwords from production.env (the init script only runs on a new data
# directory). Edit production.env first, run this, then restart api and worker. Passwords are read inside the container with
# \getenv, never printed and never put on a command line.
set -euo pipefail
ENV_FILE=${BACKUP_ENV:-/etc/zaghlol/backup.env}
# shellcheck source=/dev/null
. "$ENV_FILE"
docker compose --project-directory "$COMPOSE_DIR" --env-file "$PRODUCTION_ENV" -f "$COMPOSE_DIR/docker-compose.prod.yml" \
  exec -T postgres sh /docker-entrypoint-initdb.d/20-set-passwords.sh
echo "passwords applied; now: docker compose ... up -d --force-recreate api worker"
