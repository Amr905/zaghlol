# Restore drill (every quarter, and after any change to the backup scripts)

Goal: prove that last night's backup restores, that the point-in-time path works, and measure the time (RTO target 4 h,
RPO 5 min: `archive_timeout=300`). Record the date, the backup used, the result and the time taken in the ops log. Nothing in
this drill touches the live database except step 5, which is marked.

All commands run as root on the server (or on a spare machine with the same compose folder and a copy of the backup files).

1. **Pick the files.** `ls -lh /var/lib/zaghlol/backup/dumps /var/lib/zaghlol/backup/base | tail` and
   `cat /var/lib/zaghlol/backup/last-success`. Check the off-server copy has the same newest files:
   `ssh -i /etc/zaghlol/backup/id_ed25519 backup@backup.example.com ls -l /srv/backups/zaghlol/dumps | tail -n 3`.
2. **Logical restore into a scratch database** (safe):
   `restore.sh dump /var/lib/zaghlol/backup/dumps/zaghlol-<stamp>.dump`. Expect `restored into database zaghlol_restore` and a
   table count equal to the live one: `docker compose ... exec -T postgres psql -U zaghlol -d zaghlol -qAt -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='zaghlol'"`.
   Compare row counts of three tables (`installs`, `catalog_versions`, `purchases`) between live and scratch; the scratch copy
   may be up to a day older. Drop it: `... psql -U zaghlol -d postgres -c 'DROP DATABASE zaghlol_restore'`.
3. **Point-in-time restore on a spare** (the full cluster path). On a spare Ubuntu host with Docker, copy
   `/opt/zaghlol/deploy`, a minimal `production.env` (any passwords) and `backup.env` (`BACKUP_ROOT` = where you copied
   `base/` and `wal/` from the off-server target), run `harden.sh --dirs-only`, then
   `restore.sh pitr <base-file> "<a time 10 minutes ago, UTC>"`. When it prints `cluster restored`, check
   `psql ... -c "SELECT now(), pg_is_in_recovery()"` (false) and that the newest rows are from just before the target time.
   Do this on the spare, never on the live server, unless this is a real restore.
4. **Schema check.** Start only `migrate` against the restored cluster: it must report nothing to apply (same image) or apply
   cleanly (newer image).
5. **Real restore (only after real data loss, on the live server).**
   - Whole-cluster loss or corruption: `restore.sh pitr <newest base> "<time just before the incident, UTC>"`.
   - Wrong data written, schema fine: restore the dump into the scratch database (step 2), copy the affected rows back by hand.
   - Everything lost including the server: new server, runbook steps 1 to 5 (deployment.md "Self-hosted server"), restore the
     key directory from the two offline media, then `restore.sh pitr`. A server without the keys can't serve (fingerprint pins).
6. **Write down**: elapsed time per step, the newest row timestamp restored, anything surprising. Fix the scripts or this
   document the same day.
