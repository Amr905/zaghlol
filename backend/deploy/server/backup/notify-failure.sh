#!/bin/sh
# Called by zaghlol-backup-failed.service when the backup unit fails: journal line plus an optional e-mail.
set -eu
ENV_FILE=${BACKUP_ENV:-/etc/zaghlol/backup.env}
# shellcheck source=/dev/null
. "$ENV_FILE"
msg="zaghlol backup FAILED on $(hostname) at $(date -u +%FT%TZ); see: journalctl -u zaghlol-backup.service"
echo "$msg" >&2
if [ -n "${ALERT_EMAIL:-}" ] && command -v mail >/dev/null 2>&1; then
  echo "$msg" | mail -s "zaghlol backup failed" "$ALERT_EMAIL" || true
fi
