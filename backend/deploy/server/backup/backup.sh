#!/bin/bash
# Nightly backup (ADR-025): a logical dump (pg_dump custom format), a physical base backup (pg_basebackup) that together with
# the archived WAL gives 14-day point-in-time recovery, retention pruning, and an rsync/ssh copy to an off-server target.
# Run by zaghlol-backup.timer as root. No row content is printed; only file names and sizes.
set -euo pipefail
umask 077

ENV_FILE=${BACKUP_ENV:-/etc/zaghlol/backup.env}
# shellcheck source=/dev/null
. "$ENV_FILE"
: "${COMPOSE_DIR:?}" "${PRODUCTION_ENV:?}" "${BACKUP_ROOT:?}" "${RETENTION_DAYS:?}"

stamp=$(date -u +%Y%m%dT%H%M%SZ)
dumps="$BACKUP_ROOT/dumps"
bases="$BACKUP_ROOT/base"
wal="$BACKUP_ROOT/wal"
install -d -m 0700 "$dumps" "$bases"
[ -d "$wal" ] || { echo "WAL archive folder $wal is missing (harden.sh creates it)" >&2; exit 1; }

compose() { docker compose --project-directory "$COMPOSE_DIR" --env-file "$PRODUCTION_ENV" -f "$COMPOSE_DIR/docker-compose.prod.yml" "$@"; }
pg() { compose exec -T postgres "$@"; }

# 1. Logical dump: portable, restores a single table or the whole database.
pg pg_dump -U zaghlol -d zaghlol --format=custom --compress=6 > "$dumps/zaghlol-$stamp.dump.tmp"
mv "$dumps/zaghlol-$stamp.dump.tmp" "$dumps/zaghlol-$stamp.dump"

# 2. Base backup (tar, WAL included so it restores on its own); then close the WAL segment so it is archived at once.
pg pg_basebackup -U zaghlol -D - --format=tar --wal-method=fetch --checkpoint=fast | gzip -6 > "$bases/base-$stamp.tar.gz.tmp"
mv "$bases/base-$stamp.tar.gz.tmp" "$bases/base-$stamp.tar.gz"
pg psql -U zaghlol -d zaghlol -qAt -c 'SELECT pg_switch_wal()' > /dev/null

# 3. Quick integrity checks: the dump lists, the archive reads.
pg_restore_list=$(pg pg_restore --list < "$dumps/zaghlol-$stamp.dump" | wc -l)
[ "$pg_restore_list" -gt 10 ] || { echo "dump looks empty" >&2; exit 1; }
gzip -t "$bases/base-$stamp.tar.gz"

# 4. Retention. WAL lives one day longer than the oldest kept base backup.
find "$dumps" -name 'zaghlol-*.dump' -mtime "+$RETENTION_DAYS" -delete
find "$bases" -name 'base-*.tar.gz' -mtime "+$RETENTION_DAYS" -delete
find "$wal" -type f -mtime "+$((RETENTION_DAYS + 1))" -delete

# 5. Off-server copy, mirrored (so retention applies there too). The host key is pinned, never accepted on first use.
if [ -n "${OFFSITE_TARGET:-}" ]; then
  ssh_cmd="ssh -i ${OFFSITE_SSH_KEY:?} -o IdentitiesOnly=yes -o UserKnownHostsFile=${OFFSITE_KNOWN_HOSTS:?} -o StrictHostKeyChecking=yes -o BatchMode=yes"
  for d in dumps base wal; do
    rsync -a --delete -e "$ssh_cmd" "$BACKUP_ROOT/$d/" "$OFFSITE_TARGET/$d/"
  done
fi

date -u +%FT%TZ > "$BACKUP_ROOT/last-success"
echo "backup $stamp ok: dump $(du -h "$dumps/zaghlol-$stamp.dump" | cut -f1), base $(du -h "$bases/base-$stamp.tar.gz" | cut -f1)"
