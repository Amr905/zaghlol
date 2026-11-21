-- Zaghlol database roles and schema (T-122 design note, backend-schema.md conventions).
--
-- Run ONCE per database by an administrator (superuser, or the provider's admin role with CREATEROLE that owns the
-- database, e.g. Aiven's avnadmin: see aiven-bootstrap.sh / T-207), never by a migration:
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
--
-- zaghlol_ops_ro is a direct database login, so its reads leave no audit row. It is BREAK-GLASS ONLY: credentials stay
-- unissued until T-140 documents the procedure (who may request it, approval, time-boxed credentials, pgaudit on, review
-- afterwards). Day-to-day operator access goes through the audited admin API (security-model.md). ops_ro can't read
-- e-mails, provider subjects, store keys, tokens or stored responses (GrantMatrix.cs).

DO $bootstrap$
DECLARE
  r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['app_rw', 'worker_rw', 'ops_ro', 'ops_rw'] LOOP
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS', r);
    ELSIF EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = r
                  AND (rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)) THEN
      -- Drift repair. Changing SUPERUSER / REPLICATION / BYPASSRLS needs a superuser; a managed provider's admin
      -- (Aiven avnadmin) fails here loudly, which is right: such a role must not exist.
      EXECUTE format('ALTER ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS', r);
    END IF;
  END LOOP;

  FOREACH r IN ARRAY ARRAY['migrator', 'zaghlol_api', 'zaghlol_admin', 'zaghlol_worker', 'zaghlol_ops_ro'] LOOP
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS', r);
    ELSIF EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = r
                  AND (NOT rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls)) THEN
      EXECUTE format('ALTER ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS', r);
    END IF;
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

-- Only the five logins may connect; nobody else may create schemas or temporary tables.
DO $db$
BEGIN
  EXECUTE format('REVOKE CONNECT, CREATE, TEMPORARY ON DATABASE %I FROM PUBLIC', current_database());
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO migrator, zaghlol_api, zaghlol_admin, zaghlol_worker, zaghlol_ops_ro',
                 current_database());
END
$db$;

-- PostgreSQL 16+: a CREATEROLE user that created `migrator` has ADMIN on it but not SET, and CREATE SCHEMA ... AUTHORIZATION /
-- ALTER SCHEMA ... OWNER need SET. Superusers don't need it. (Older versions: a CREATEROLE user is implicitly a member.)
DO $setrole$
BEGIN
  IF current_setting('server_version_num')::int >= 160000
     AND NOT (SELECT rolsuper FROM pg_catalog.pg_roles WHERE rolname = current_user)
     AND NOT pg_catalog.pg_has_role(current_user, 'migrator', 'SET') THEN
    EXECUTE format('GRANT migrator TO %I WITH SET TRUE', current_user);
  END IF;
END
$setrole$;

CREATE SCHEMA IF NOT EXISTS zaghlol AUTHORIZATION migrator;
ALTER SCHEMA zaghlol OWNER TO migrator;
REVOKE ALL ON SCHEMA zaghlol FROM PUBLIC;
GRANT USAGE ON SCHEMA zaghlol TO app_rw, worker_rw, ops_ro, ops_rw;
