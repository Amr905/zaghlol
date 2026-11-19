-- Break-glass dispute-freeze unfreeze (T-137 runbook, R6-1). Run as `migrator` (the schema owner) by a database administrator, only
-- when the API refuses the unfreeze because there is no second operator (a different operator is required, after 24 h) and the
-- support lead and the product owner have both approved on the ticket. It is not an API bypass for convenience: the API stays strict.
--
--   psql "$MIGRATOR_URL" -v purchase='<purchase UUID>' -v ticket='<ticket ref>' -v operator_sub='<IdP sub of the requesting operator>' \
--        -f backend/deploy/db/break-glass-unfreeze.sql
--
-- What it does, in one transaction: checks that the purchase has a running freeze and that the operator is enabled, holds support_lead and is the only enabled support_lead; clears
-- `dispute_frozen_until` (nothing else: no seat, account, window or claimant changes, like the API's unfreeze); writes one
-- `support_unfreeze` audit row for that operator with `break_glass: true` and `ownership_outcome: manual`. The audit row also starts the
-- R6-1 24-hour lock for that operator (they cannot make the next ordinary move on this purchase for 24 hours), as for an API unfreeze.
-- The ownership check is manual (the order looked up in the store console by the lead) and its outcome is written on the ticket, never
-- the order ID. A script run raises no alert by itself: post it in the support-lead channel (runbook).
-- If a check fails nothing is changed and the script stops with a message that names no value.

\set ON_ERROR_STOP on

SELECT (:'purchase' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        AND :'ticket' ~ '^[A-Za-z0-9_-]{1,32}$'
        AND length(btrim(:'operator_sub')) BETWEEN 1 AND 255
        AND position('@' in :'operator_sub') = 0) AS input_ok \gset

\if :input_ok
BEGIN;

-- One statement, so the checks and the change see the same rows: the purchase must have a running freeze and the operator must exist
-- and be enabled; otherwise nothing is updated or written.
-- The operator must hold support_lead, and no OTHER enabled support_lead may exist: with a second lead the API route applies (R6-1).
WITH op AS (
    SELECT id FROM zaghlol.operators
     WHERE oidc_subject = btrim(:'operator_sub') AND disabled_at IS NULL AND 'support_lead' = ANY (roles)
       AND NOT EXISTS (SELECT 1 FROM zaghlol.operators o2
                        WHERE o2.disabled_at IS NULL AND 'support_lead' = ANY (o2.roles)
                          AND o2.oidc_subject <> btrim(:'operator_sub'))
), frozen AS (
    SELECT id, dispute_frozen_until FROM zaghlol.purchases WHERE id = :'purchase'::uuid AND dispute_frozen_until > now() FOR UPDATE
), cleared AS (
    UPDATE zaghlol.purchases p SET dispute_frozen_until = NULL
      FROM frozen f, op WHERE p.id = f.id
    RETURNING f.dispute_frozen_until AS was, op.id AS operator_id
), logged AS (
    INSERT INTO zaghlol.audit_log (operator_id, action, target, details)
    -- The target is the canonical lower-case UUID, as the API writes and looks it up (batch-44 review F1): an upper-case paste would
    -- otherwise hide the row from the server's R6-1 lock and from per-purchase audit queries.
    SELECT c.operator_id, 'support_unfreeze', (:'purchase'::uuid)::text,
           jsonb_build_object('ticket_ref', :'ticket', 'freeze_audit_id', NULL, 'frozen_until', c.was,
                              'ownership_check', 'order_id', 'ownership_outcome', 'manual', 'outcome', 'unfrozen', 'break_glass', true)
      FROM cleared c
    RETURNING id
)
SELECT (count(*) = 1) AS done FROM logged \gset

\if :done
COMMIT;
\echo 'break-glass-unfreeze: freeze cleared and audited.'
\else
ROLLBACK;
DO $$ BEGIN RAISE EXCEPTION 'break-glass-unfreeze: the purchase has no running freeze, or that subject is not the only enabled support_lead; nothing was changed'; END $$;
\endif
\else
DO $$ BEGIN RAISE EXCEPTION 'break-glass-unfreeze: purchase must be a UUID, ticket 1-32 letters, digits, - or _, operator_sub 1-255 characters without @'; END $$;
\endif
