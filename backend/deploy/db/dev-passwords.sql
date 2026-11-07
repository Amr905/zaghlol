-- LOCAL DEVELOPMENT ONLY (docker compose). Never run against staging or production: real credentials come from the
-- secrets manager / IAM auth set up by T-140. Runs after bootstrap-roles.sql in docker-entrypoint-initdb.d.
ALTER ROLE migrator PASSWORD 'migrator_dev_only';
ALTER ROLE zaghlol_api PASSWORD 'api_dev_only';
ALTER ROLE zaghlol_admin PASSWORD 'admin_dev_only';
ALTER ROLE zaghlol_worker PASSWORD 'worker_dev_only';
ALTER ROLE zaghlol_ops_ro PASSWORD 'ops_ro_dev_only';
