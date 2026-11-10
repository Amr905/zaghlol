-- Provision or update one operator (T-136, FU-024). Run as `migrator` (the schema owner); no runtime login can write
-- zaghlol.operators, so this script (or a later `zaghlol-ops operators` command run as migrator) is the only way in.
-- Idempotent: re-running with the same subject updates the display name and replaces the roles. It never re-enables a
-- disabled operator.
--
--   psql "$MIGRATOR_URL" -v sub='<IdP subject (sub claim)>' -v display_name='<name>' \
--        -v roles='{support_viewer,support_agent}' -f backend/deploy/db/seed-operator.sql
--
-- `sub` is the IdP's immutable subject (Entra: the token's `sub` for the zaghlol-ops/admin app; Google: the account's `sub`),
-- never an e-mail. Roles: catalog_editor, flags_admin, prices_admin, support_viewer, support_agent, support_lead. A role
-- implies no other role; give support agents support_viewer too if they look users up. Changes take effect within 30 s.
--
-- Disable (immediate within 30 s, row and audit history kept; operators are never deleted):
--   UPDATE zaghlol.operators SET disabled_at = now() WHERE oidc_subject = '<sub>';

\set ON_ERROR_STOP on

SELECT (cardinality(:'roles'::text[]) > 0
        AND :'roles'::text[] <@ ARRAY['catalog_editor','flags_admin','prices_admin','support_viewer','support_agent','support_lead']::text[]
        AND length(btrim(:'sub')) BETWEEN 1 AND 255
        AND position('@' in :'sub') = 0
        AND length(btrim(:'display_name')) BETWEEN 1 AND 100) AS operator_input_ok \gset

\if :operator_input_ok
INSERT INTO zaghlol.operators (id, oidc_subject, display_name, roles)
VALUES (gen_random_uuid(), btrim(:'sub'), btrim(:'display_name'), :'roles'::text[])
ON CONFLICT (oidc_subject) DO UPDATE SET display_name = EXCLUDED.display_name, roles = EXCLUDED.roles;
\else
DO $$ BEGIN RAISE EXCEPTION 'seed-operator: roles must be a non-empty subset of the six operator roles, sub 1-255 characters without @, display_name 1-100 characters'; END $$;
\endif
