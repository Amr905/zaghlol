#!/bin/sh
# Production role passwords (ADR-025). Runs ONCE, when the data directory is first initialised, after
# 10-bootstrap-roles.sql has created the roles. The passwords come from the container environment (production.env);
# psql reads them with \getenv (psql 15+, so they never appear on a command line) and quotes them with :'name', so they are
# never pasted into the SQL text and never echoed. Re-apply or rotate later with backup/set-db-passwords.sh.
# Works when sourced or executed (no `exit`).
set -eu
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
\getenv migrator DB_MIGRATOR_PASSWORD
\getenv api DB_API_PASSWORD
\getenv admin DB_ADMIN_PASSWORD
\getenv worker DB_WORKER_PASSWORD
\getenv opsro DB_OPS_RO_PASSWORD
ALTER ROLE migrator PASSWORD :'migrator';
ALTER ROLE zaghlol_api PASSWORD :'api';
ALTER ROLE zaghlol_admin PASSWORD :'admin';
ALTER ROLE zaghlol_worker PASSWORD :'worker';
ALTER ROLE zaghlol_ops_ro PASSWORD :'opsro';
SQL
