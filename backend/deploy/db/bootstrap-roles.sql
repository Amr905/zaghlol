-- Zaghlol database roles and schema (T-122 design note, backend-schema.md conventions).
--
-- Run ONCE per database by an administrator (superuser or the provider's admin role), never by a migration:
--   * production / staging: by T-140's provisioning, which then sets passwords or IAM auth for the LOGIN roles;
--   * local compose: docker-entrypoint-initdb.d (dev-only passwords come from dev-passwords.sql);
--   * tests: the Testcontainers fixture, as superuser.
-- Idempotent: safe to run again. It creates no passwords and no tables; per-table GRANTs live in the migrations.
--
-- Roles:
--   migrator         LOGIN, owns schema zaghlol and every object in it; no CREATEROLE / CREATEDB / SUPERUSER.
--   app_rw           NOLOGIN group: /v1/* endpoints            <- login zaghlol_api
--   ops_rw           NOLOGIN group: /admin/v1/* endpoints      <- login zaghlol_admin
--   worker_rw        NOLOGIN group: background jobs            <- login zaghlol_worker
--   ops_ro           NOLOGIN group: read-only operators        <- login zaghlol_ops_ro

DO $bootstrap$
DECLARE
  r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['app_rw', 'worker_rw', 'ops_ro', 'ops_rw'] LOOP
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN', r);
    END IF;
    EXECUTE format('ALTER ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS', r);
  END LOOP;

  FOREACH r IN ARRAY ARRAY['migrator', 'zaghlol_api', 'zaghlol_admin', 'zaghlol_worker', 'zaghlol_ops_ro'] LOOP
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I LOGIN', r);
    END IF;
    EXECUTE format('ALTER ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS', r);
  END LOOP;
END
$bootstrap$;

-- Each login is a member of exactly one group.
GRANT app_rw TO zaghlol_api;
GRANT ops_rw TO zaghlol_admin;
GRANT worker_rw TO zaghlol_worker;
GRANT ops_ro TO zaghlol_ops_ro;

-- Nothing in public; nobody but migrator creates objects.
REVOKE ALL ON SCHEMA public FROM PUBLIC;

DO $db$
BEGIN
  EXECUTE format('REVOKE CREATE, TEMPORARY ON DATABASE %I FROM PUBLIC', current_database());
END
$db$;

CREATE SCHEMA IF NOT EXISTS zaghlol AUTHORIZATION migrator;
ALTER SCHEMA zaghlol OWNER TO migrator;
REVOKE ALL ON SCHEMA zaghlol FROM PUBLIC;
GRANT USAGE ON SCHEMA zaghlol TO app_rw, worker_rw, ops_ro, ops_rw;
