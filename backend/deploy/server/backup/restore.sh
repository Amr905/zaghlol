#!/bin/bash
# Restore helper (ADR-025). Run as root on the server. Three modes:
#
#   restore.sh dump  <dump-file> [scratch-db]   restore a logical dump into a NEW scratch database (default zaghlol_restore)
#                                               next to the live one; changes nothing that is live. Used by the drill.
#   restore.sh live  <dump-file>                replace the LIVE database content from a dump (api and worker are stopped first).
#   restore.sh pitr  <base-tar.gz> [time]       rebuild the whole cluster from a base backup and the WAL archive, up to `time`
#                                               (UTC, e.g. "2026-12-01 14:20:00+00"); without `time` replay all archived WAL.
#                                               The old data directory is kept as <data>.before-restore-<stamp>.
#
# Every mode asks you to type RESTORE (except `dump`, which is safe); set ZAGHLOL_RESTORE_YES=RESTORE to skip the prompt in
# an automated drill. Nothing secret is printed.
set -euo pipefail
umask 077

ENV_FILE=${BACKUP_ENV:-/etc/zaghlol/backup.env}
# shellcheck source=/dev/null
. "$ENV_FILE"
: "${COMPOSE_DIR:?}" "${PRODUCTION_ENV:?}" "${BACKUP_ROOT:?}"
DATA_DIR=${DATA_DIR:-/var/lib/zaghlol/postgres}

compose() { docker compose --project-directory "$COMPOSE_DIR" --env-file "$PRODUCTION_ENV" -f "$COMPOSE_DIR/docker-compose.prod.yml" "$@"; }
pg() { compose exec -T postgres "$@"; }

confirm() {
  if [ "${ZAGHLOL_RESTORE_YES:-}" = "RESTORE" ]; then return 0; fi
  printf '%s\nType RESTORE to continue: ' "$1" >&2
  read -r answer
  [ "$answer" = "RESTORE" ] || { echo "aborted" >&2; exit 1; }
}

usage() { sed -n '2,14p' "$0" >&2; exit 2; }

mode=${1:-}
[ -n "$mode" ] || usage
shift

case "$mode" in
  dump)
    file=${1:?dump file}
    scratch=${2:-zaghlol_restore}
    case "$scratch" in zaghlol) echo "refusing to use the live database name; use 'live'" >&2; exit 2 ;; esac
    case "$scratch" in *[!a-z0-9_]*) echo "scratch database name: lower-case letters, digits, _" >&2; exit 2 ;; esac
    pg psql -U zaghlol -d postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS $scratch" -c "CREATE DATABASE $scratch"
    pg pg_restore -U zaghlol -d "$scratch" --exit-on-error < "$file"
    pg psql -U zaghlol -d "$scratch" -qAt -c "SELECT 'tables in schema zaghlol: ' || count(*) FROM information_schema.tables WHERE table_schema = 'zaghlol'"
    echo "restored into database $scratch (drop it with: DROP DATABASE $scratch)"
    ;;

  live)
    file=${1:?dump file}
    confirm "This REPLACES the live database content with $file. api and worker are stopped first."
    compose stop api worker caddy
    pg psql -U zaghlol -d zaghlol -v ON_ERROR_STOP=1 -c 'DROP SCHEMA IF EXISTS zaghlol CASCADE'
    pg pg_restore -U zaghlol -d zaghlol --exit-on-error < "$file"
    compose up -d api worker caddy
    echo "live database restored from $file"
    ;;

  pitr)
    base=${1:?base backup tar.gz}
    target=${2:-}
    gzip -t "$base"
    confirm "This REPLACES the whole PostgreSQL cluster in $DATA_DIR from $base${target:+ up to $target}."
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    compose stop api worker caddy
    compose stop postgres
    mv "$DATA_DIR" "$DATA_DIR.before-restore-$stamp"
    install -d -m 0700 -o 999 -g 999 "$DATA_DIR"
    tar -xzf "$base" -C "$DATA_DIR"
    touch "$DATA_DIR/recovery.signal"
    {
      echo "restore_command = 'cp /wal-archive/%f %p'"
      [ -n "$target" ] && echo "recovery_target_time = '$target'"
      echo "recovery_target_action = 'promote'"
    } >> "$DATA_DIR/postgresql.auto.conf"
    chown -R 999:999 "$DATA_DIR"
    chmod 0700 "$DATA_DIR"
    compose up -d postgres
    echo "waiting for recovery to finish (the server accepts connections when it is promoted)..."
    for _ in $(seq 1 120); do
      if pg pg_isready -U zaghlol -d zaghlol -q 2>/dev/null; then
        in_recovery=$(pg psql -U zaghlol -d zaghlol -qAt -c 'SELECT pg_is_in_recovery()' 2>/dev/null || echo t)
        if [ "$in_recovery" = "f" ]; then break; fi
      fi
      sleep 5
    done
    [ "${in_recovery:-t}" = "f" ] || { echo "recovery did not finish in 10 minutes; check: docker compose logs postgres" >&2; exit 1; }
    compose up -d
    echo "cluster restored; old data kept in $DATA_DIR.before-restore-$stamp (delete it when satisfied)"
    ;;

  *) usage ;;
esac
