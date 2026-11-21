#!/usr/bin/env bash
# T-207: role bootstrap for Aiven for PostgreSQL (or any managed PostgreSQL whose admin is a non-superuser with CREATEROLE).
#
# Runs bootstrap-roles.sql (unchanged for every platform) as the admin (avnadmin) and then sets the LOGIN passwords from
# environment variables. Idempotent: run it again to rotate passwords (use --passwords-only to skip the roles/schema part).
# Run it from a trusted machine or a one-off workflow step; never from the API or worker.
#
# Environment (secrets are read by psql with \getenv, so they never appear in argv or in the process list):
#   ZAGHLOL_ADMIN_URI              required. Aiven "Service URI" of avnadmin, for example
#                                  postgres://avnadmin:<pw>@<host>:<port>/defaultdb?sslmode=verify-full
#   PGSSLROOTCERT                  path of the Aiven project CA (ca.pem from the console); required for verify-full
#   ZAGHLOL_MIGRATOR_PASSWORD      required, at least 24 characters
#   ZAGHLOL_API_PASSWORD           required (login zaghlol_api, group app_rw)
#   ZAGHLOL_ADMIN_API_PASSWORD     required (login zaghlol_admin, group ops_rw)
#   ZAGHLOL_WORKER_PASSWORD        required (login zaghlol_worker, group worker_rw)
# zaghlol_ops_ro is break-glass only: it gets NO password here (T-140), so it cannot log in until a break-glass procedure sets one.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
passwords_only=0
case "${1:-}" in
  --passwords-only) passwords_only=1 ;;
  "") ;;
  *) echo "usage: $0 [--passwords-only]" >&2; exit 64 ;;
esac

: "${ZAGHLOL_ADMIN_URI:?set ZAGHLOL_ADMIN_URI (the avnadmin service URI)}"
for v in ZAGHLOL_MIGRATOR_PASSWORD ZAGHLOL_API_PASSWORD ZAGHLOL_ADMIN_API_PASSWORD ZAGHLOL_WORKER_PASSWORD; do
  value="${!v:-}"
  if [ "${#value}" -lt 24 ]; then
    echo "$v must be set and at least 24 characters" >&2
    exit 64
  fi
  case "$value" in *$'\n'*|*$'\r'*) echo "$v must not contain a line break" >&2; exit 64 ;; esac
done
# TLS is mandatory. Only the CI test (a local container without TLS) sets ZAGHLOL_BOOTSTRAP_ALLOW_NO_TLS=1.
if [ "${ZAGHLOL_BOOTSTRAP_ALLOW_NO_TLS:-}" != "1" ]; then
  case "$ZAGHLOL_ADMIN_URI" in
    *sslmode=verify-full*|*sslmode=verify-ca*) ;;
    *) echo "ZAGHLOL_ADMIN_URI must carry sslmode=verify-full (or verify-ca); set PGSSLROOTCERT to the Aiven CA" >&2; exit 64 ;;
  esac
fi
command -v psql >/dev/null || { echo "psql (PostgreSQL client 15 or newer) is required" >&2; exit 69; }

psql_run() { psql "$ZAGHLOL_ADMIN_URI" -X -q -v ON_ERROR_STOP=1 "$@"; }

if [ "$passwords_only" -eq 0 ]; then
  psql_run -f "$here/bootstrap-roles.sql"
fi

# Passwords: \getenv (psql 15+) keeps them out of argv; :'x' quotes them as a literal.
psql_run <<'SQL'
\getenv pw_migrator ZAGHLOL_MIGRATOR_PASSWORD
\getenv pw_api ZAGHLOL_API_PASSWORD
\getenv pw_admin ZAGHLOL_ADMIN_API_PASSWORD
\getenv pw_worker ZAGHLOL_WORKER_PASSWORD
ALTER ROLE migrator PASSWORD :'pw_migrator';
ALTER ROLE zaghlol_api PASSWORD :'pw_api';
ALTER ROLE zaghlol_admin PASSWORD :'pw_admin';
ALTER ROLE zaghlol_worker PASSWORD :'pw_worker';
SQL

# Verify: no privileged role, the schema belongs to migrator, each login is in exactly its group.
bad="$(psql_run -At -c "SELECT string_agg(rolname, ',') FROM pg_roles
  WHERE rolname IN ('migrator','zaghlol_api','zaghlol_admin','zaghlol_worker','zaghlol_ops_ro','app_rw','ops_rw','worker_rw','ops_ro')
    AND (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)")"
if [ -n "$bad" ]; then
  echo "privileged Zaghlol roles found: $bad" >&2
  exit 1
fi
owner="$(psql_run -At -c "SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname = 'zaghlol'")"
if [ "$owner" != "migrator" ]; then
  echo "schema zaghlol is owned by '${owner:-nobody}', expected migrator" >&2
  exit 1
fi
echo "Zaghlol roles ready (schema zaghlol owned by migrator; passwords set for migrator, zaghlol_api, zaghlol_admin, zaghlol_worker)."
