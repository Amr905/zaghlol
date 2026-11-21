#!/bin/bash
# CI test for backup/restore.sh (live and dump modes) against a throwaway postgres container. A `docker` shim stands in for
# docker compose: `compose exec -T postgres <cmd>` runs inside the throwaway container, stop/up are recorded in a log.
# Asserts a bad path / garbage / empty dump never touches the source database, a good dump swaps atomically, and services
# are restarted. Needs docker. Usage: tests/restore-test.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
CNAME=zaghlol-restore-test
trap 'docker rm -f "$CNAME" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

docker run -d --name "$CNAME" -e POSTGRES_USER=zaghlol -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=zaghlol postgres:17 >/dev/null
for _ in $(seq 1 30); do docker exec "$CNAME" pg_isready -U zaghlol -d zaghlol -q && break; sleep 2; done
sleep 2

mkdir "$WORK/bin"
cat > "$WORK/bin/docker" <<SHIM
#!/bin/bash
# shim: docker compose ... <verb> ...
[ "\$1" = compose ] || exit 99
shift
while [ \$# -gt 0 ]; do
  case "\$1" in
    --project-directory|--env-file|-f) shift 2 ;;
    exec) shift; [ "\$1" = -T ] && shift; shift; exec docker-real exec -i $CNAME "\$@" ;;
    stop|up) echo "\$*" >> "$WORK/compose.log"; exit 0 ;;
    *) shift ;;
  esac
done
SHIM
REAL=$(command -v docker)
ln -s "$REAL" "$WORK/bin/docker-real"
chmod +x "$WORK/bin/docker"
export PATH="$WORK/bin:$PATH"

: > "$WORK/prod.env"
cat > "$WORK/backup.env" <<ENV
COMPOSE_DIR=$WORK
PRODUCTION_ENV=$WORK/prod.env
BACKUP_ROOT=$WORK
ENV
export BACKUP_ENV="$WORK/backup.env" ZAGHLOL_RESTORE_YES=RESTORE

psql_() { docker-real exec -i "$CNAME" psql -U zaghlol -qAt "$@"; }
fail=0
expect() { if [ "$2" = "$3" ]; then echo "ok:   $1"; else echo "FAIL: $1 (expected '$3', got '$2')"; fail=1; fi; }

# Source database with data, and a good dump of different content.
psql_ -d zaghlol -c "CREATE SCHEMA zaghlol; CREATE TABLE zaghlol.t(v text); INSERT INTO zaghlol.t VALUES ('live-original')" >/dev/null
psql_ -d postgres -c "CREATE DATABASE donor" >/dev/null
psql_ -d donor -c "CREATE SCHEMA zaghlol; CREATE TABLE zaghlol.t(v text); INSERT INTO zaghlol.t VALUES ('from-dump')" >/dev/null
docker-real exec -i "$CNAME" pg_dump -U zaghlol -Fc -d donor > "$WORK/good.dump"
echo "not a dump" > "$WORK/garbage.dump"
: > "$WORK/empty.dump"

live_value() { psql_ -d zaghlol -c "SELECT string_agg(v, ',') FROM zaghlol.t"; }

for bad in "$WORK/missing.dump" "$WORK/garbage.dump" "$WORK/empty.dump"; do
  rc=0
  bash "$HERE/../backup/restore.sh" live "$bad" >/dev/null 2>&1 || rc=$?
  expect "live with $(basename "$bad") fails" "$([ "$rc" -ne 0 ] && echo failed || echo succeeded)" failed
  expect "  source database intact after $(basename "$bad")" "$(live_value)" live-original
  expect "  services never stopped after $(basename "$bad")" "$(grep -c '^stop' "$WORK/compose.log" 2>/dev/null || echo 0)" 0
done

for name in postgres template1 zaghlol; do
  rc=0
  bash "$HERE/../backup/restore.sh" dump "$WORK/good.dump" "$name" >/dev/null 2>&1 || rc=$?
  expect "dump mode refuses scratch name $name" "$rc" 2
done

bash "$HERE/../backup/restore.sh" live "$WORK/good.dump" >/dev/null
expect "good dump replaces the live content" "$(live_value)" from-dump
expect "previous database kept" "$(psql_ -d postgres -c "SELECT count(*) FROM pg_database WHERE datname LIKE 'zaghlol_before_restore_%'")" 1
expect "scratch database gone" "$(psql_ -d postgres -c "SELECT count(*) FROM pg_database WHERE datname = 'zaghlol_restore_new'")" 0
expect "services restarted after the swap" "$(grep -c '^up' "$WORK/compose.log")" 1

exit "$fail"
