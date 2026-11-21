#!/bin/bash
# Restore helper (ADR-025). Run as root on the server. Three modes:
#
#   restore.sh dump  <dump-file> [scratch-db]   restore a logical dump into a NEW scratch database (default zaghlol_restore)
#                                               next to the live one; changes nothing that is live. Used by the drill.
#   restore.sh live  <dump-file>                replace the LIVE database from a dump. The dump is checked first, restored into a scratch
#                                               database and verified; only then are api/worker/caddy stopped and the databases swapped by
#                                               rename. The old database is kept as zaghlol_before_restore_<stamp>. Services restart on any exit.
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

# The dump must exist, be non-empty and be listable by pg_restore before anything is changed.
check_dump() {
  [ -f "$1" ] && [ -r "$1" ] || { echo "dump file not found or not readable: $1" >&2; exit 2; }
  [ -s "$1" ] || { echo "dump file is empty: $1" >&2; exit 2; }
  pg pg_restore --list < "$1" > /dev/null || { echo "not a valid pg_restore dump: $1" >&2; exit 2; }
}

usage() { sed -n '2,16p' "$0" >&2; exit 2; }

mode=${1:-}
[ -n "$mode" ] || usage
shift

case "$mode" in
  dump)
    file=${1:?dump file}
    scratch=${2:-zaghlol_restore}
    case "$scratch" in zaghlol|postgres|template0|template1) echo "refusing to use '$scratch' as scratch name (live or system database); use 'live' for the live one" >&2; exit 2 ;; esac
    case "$scratch" in *[!a-z0-9_]*) echo "scratch database name: lower-case letters, digits, _" >&2; exit 2 ;; esac
    check_dump "$file"
    pg psql -U zaghlol -d postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS $scratch" -c "CREATE DATABASE $scratch"
    pg pg_restore -U zaghlol -d "$scratch" --exit-on-error < "$file"
    pg psql -U zaghlol -d "$scratch" -qAt -c "SELECT 'tables in schema zaghlol: ' || count(*) FROM information_schema.tables WHERE table_schema = 'zaghlol'"
    echo "restored into database $scratch (drop it with: DROP DATABASE $scratch)"
    ;;

  live)
    file=${1:?dump file}
    # 1. Nothing is touched until the dump is known to be readable.
    check_dump "$file"
    confirm "This REPLACES the live database with $file. api, worker and caddy are stopped for the swap."
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    scratch=zaghlol_restore_new
    old=zaghlol_before_restore_$stamp
    # 2. Restore into a scratch database next to the live one (the live one keeps serving) and verify it.
    pg psql -U zaghlol -d postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS $scratch" -c "CREATE DATABASE $scratch"
    if ! pg pg_restore -U zaghlol -d "$scratch" --exit-on-error < "$file"; then
      pg psql -U zaghlol -d postgres -qAt -c "DROP DATABASE IF EXISTS $scratch" || true
      echo "restore into the scratch database failed; the live database is untouched" >&2
      exit 1
    fi
    tables=$(pg psql -U zaghlol -d "$scratch" -qAt -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'zaghlol'")
    if [ "${tables:-0}" -lt 1 ]; then
      pg psql -U zaghlol -d postgres -qAt -c "DROP DATABASE IF EXISTS $scratch" || true
      echo "the dump has no tables in schema zaghlol; the live database is untouched" >&2
      exit 1
    fi
    # 3. Swap by rename. Services are restarted on every exit path (success or failure).
    trap 'compose up -d api worker caddy || echo "could not restart services; run: docker compose up -d" >&2' EXIT
    compose stop api worker caddy
    pg psql -U zaghlol -d postgres -v ON_ERROR_STOP=1 \
      -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname IN ('zaghlol', '$scratch') AND pid <> pg_backend_pid()" \
      -c "ALTER DATABASE zaghlol RENAME TO $old"
    if ! pg psql -U zaghlol -d postgres -v ON_ERROR_STOP=1 -c "ALTER DATABASE $scratch RENAME TO zaghlol"; then
      pg psql -U zaghlol -d postgres -v ON_ERROR_STOP=1 -c "ALTER DATABASE $old RENAME TO zaghlol"
      echo "swap failed; the previous database was put back" >&2
      exit 1
    fi
    echo "live database restored from $file ($tables tables); the previous database is kept as $old (drop it when satisfied)"
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
