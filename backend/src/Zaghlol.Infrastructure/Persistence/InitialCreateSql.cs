namespace Zaghlol.Infrastructure.Persistence;

/// <summary>
/// The parts of the InitialCreate migration EF can't model: the entitlement view, the BEFORE DELETE and BEFORE UPDATE
/// triggers, row-level security on <c>audit_log</c>, the grants and the comments. Frozen with the migration (a golden
/// test pins the SHA-256 of each block): a later change goes into a new migration, never here.
/// </summary>
internal static class InitialCreateSql
{
    /// <summary>backend-schema.md section 2, verbatim apart from schema-qualified names.</summary>
    public const string CreateEntitlementView = """
        CREATE VIEW zaghlol.v_entitlements AS
          SELECT s.install_id, p.id AS purchase_id, p.plan, p.state, p.expires_at, p.store, p.account_id, s.proof, s.next_move_at
          FROM zaghlol.purchase_seats s JOIN zaghlol.purchases p ON p.id = s.purchase_id
          WHERE s.install_id IS NOT NULL AND p.state IN ('active','in_grace','canceled_active');
        """;

    /// <summary>
    /// FK actions fire after the parent row is gone, so ON DELETE SET NULL alone would break two CHECKs. These BEFORE DELETE
    /// triggers clear the dependent columns first. SECURITY DEFINER (owner: migrator) so the deleting role needs no UPDATE
    /// grant on the other table; a fixed search_path so the definer's rights can't be redirected.
    /// </summary>
    public const string CreateTriggers = """
        CREATE FUNCTION zaghlol.accounts_before_delete() RETURNS trigger
          LANGUAGE plpgsql SECURITY DEFINER SET search_path = zaghlol, pg_temp AS $fn$
        BEGIN
          -- Clears the link and its source together (CHECK (account_id IS NULL) = (account_linked_by IS NULL));
          -- attach_reclaim_used_at is never touched (D-58).
          UPDATE zaghlol.purchases SET account_id = NULL, account_linked_by = NULL WHERE account_id = OLD.id;
          RETURN OLD;
        END
        $fn$;
        REVOKE ALL ON FUNCTION zaghlol.accounts_before_delete() FROM PUBLIC;
        CREATE TRIGGER accounts_before_delete BEFORE DELETE ON zaghlol.accounts
          FOR EACH ROW EXECUTE FUNCTION zaghlol.accounts_before_delete();

        CREATE FUNCTION zaghlol.installs_before_delete() RETURNS trigger
          LANGUAGE plpgsql SECURITY DEFINER SET search_path = zaghlol, pg_temp AS $fn$
        BEGIN
          -- Vacates the seat (CHECK (install_id IS NULL) = (proof IS NULL)); device_key_hash, device_key_trusted,
          -- last_moved_at, next_move_at and recent_rebinds are kept (D-55).
          UPDATE zaghlol.purchase_seats SET install_id = NULL, proof = NULL, bound_at = NULL WHERE install_id = OLD.id;
          RETURN OLD;
        END
        $fn$;
        REVOKE ALL ON FUNCTION zaghlol.installs_before_delete() FROM PUBLIC;
        CREATE TRIGGER installs_before_delete BEFORE DELETE ON zaghlol.installs
          FOR EACH ROW EXECUTE FUNCTION zaghlol.installs_before_delete();
        """;

    /// <summary>
    /// One-way invariants (SEC F9) that must hold whatever role writes: <c>installs.seat_key_hash</c> is set once (cleared
    /// only by the tombstone, R4-1(1)); <c>installs.seat_key_trusted</c> only goes false to true (R5-2);
    /// <c>purchases.attach_reclaim_used_at</c> is never cleared or changed (D-58). Violations raise SQLSTATE 23514 with a
    /// stable constraint name and no values. SECURITY INVOKER: they read only OLD and NEW.
    /// </summary>
    public const string CreateInvariantTriggers = """
        CREATE FUNCTION zaghlol.installs_before_update() RETURNS trigger
          LANGUAGE plpgsql SET search_path = zaghlol, pg_temp AS $fn$
        BEGIN
          IF OLD.seat_key_hash IS NOT NULL AND NEW.seat_key_hash IS DISTINCT FROM OLD.seat_key_hash
             AND NEW.deleted_at IS NULL THEN
            RAISE EXCEPTION 'installs.seat_key_hash is set once'
              USING ERRCODE = 'check_violation', CONSTRAINT = 'installs_seat_key_hash_set_once';
          END IF;
          IF OLD.seat_key_trusted AND NOT NEW.seat_key_trusted THEN
            RAISE EXCEPTION 'installs.seat_key_trusted only changes from false to true'
              USING ERRCODE = 'check_violation', CONSTRAINT = 'installs_seat_key_trusted_one_way';
          END IF;
          RETURN NEW;
        END
        $fn$;
        REVOKE ALL ON FUNCTION zaghlol.installs_before_update() FROM PUBLIC;
        CREATE TRIGGER installs_before_update BEFORE UPDATE ON zaghlol.installs
          FOR EACH ROW EXECUTE FUNCTION zaghlol.installs_before_update();

        CREATE FUNCTION zaghlol.purchases_before_update() RETURNS trigger
          LANGUAGE plpgsql SET search_path = zaghlol, pg_temp AS $fn$
        BEGIN
          IF OLD.attach_reclaim_used_at IS NOT NULL
             AND NEW.attach_reclaim_used_at IS DISTINCT FROM OLD.attach_reclaim_used_at THEN
            RAISE EXCEPTION 'purchases.attach_reclaim_used_at is never cleared'
              USING ERRCODE = 'check_violation', CONSTRAINT = 'purchases_attach_reclaim_never_cleared';
          END IF;
          RETURN NEW;
        END
        $fn$;
        REVOKE ALL ON FUNCTION zaghlol.purchases_before_update() FROM PUBLIC;
        CREATE TRIGGER purchases_before_update BEFORE UPDATE ON zaghlol.purchases
          FOR EACH ROW EXECUTE FUNCTION zaghlol.purchases_before_update();
        """;

    /// <summary>
    /// Tamper resistance for <c>audit_log</c> (SEC F4). The table-level grants decide who may try; these policies decide
    /// which rows. Readers see every row. <c>ops_rw</c> may only append rows stamped now (so it can't backdate a forged
    /// row into the purge window). <c>worker_rw</c> may delete only rows past their retention age: support actions after
    /// 1 year (D-47), all others after 3 years. Nobody has an UPDATE policy. The owner (<c>migrator</c>) isn't subject to
    /// RLS (no FORCE), so migrations still work.
    /// </summary>
    public const string AuditLogRowLevelSecurity = """
        ALTER TABLE zaghlol.audit_log ENABLE ROW LEVEL SECURITY;
        CREATE POLICY audit_log_read ON zaghlol.audit_log FOR SELECT TO ops_ro, ops_rw, worker_rw USING (true);
        CREATE POLICY audit_log_append ON zaghlol.audit_log FOR INSERT TO ops_rw
          WITH CHECK (at BETWEEN now() - interval '1 minute' AND now() + interval '1 minute');
        CREATE POLICY audit_log_retention_delete ON zaghlol.audit_log FOR DELETE TO worker_rw
          USING (CASE WHEN action IN ('support_lookup','support_seat_move','support_detach','support_unfreeze')
                      THEN at < now() - interval '1 year'
                      ELSE at < now() - interval '3 years' END);
        """;

    public const string Comments = """
        COMMENT ON VIEW zaghlol.v_entitlements IS 'Effective entitlement, computed not stored: purchases whose seat the install holds, in an entitling state. A row with account_id set counts only with a valid account token for that account (D-61(c)).';
        COMMENT ON FUNCTION zaghlol.accounts_before_delete() IS 'Backstop for account deletion: clears purchases.account_id and account_linked_by together; never attach_reclaim_used_at (D-58).';
        COMMENT ON FUNCTION zaghlol.installs_before_delete() IS 'Vacates purchase_seats held by the deleted install; keeps device_key_hash, device_key_trusted and the move times (D-55).';
        COMMENT ON FUNCTION zaghlol.installs_before_update() IS 'One-way invariants: seat_key_hash set once (cleared only at tombstone), seat_key_trusted only false to true (R4-1(1), R5-2).';
        COMMENT ON FUNCTION zaghlol.purchases_before_update() IS 'One-way invariant: attach_reclaim_used_at is never cleared or changed (D-58).';
        COMMENT ON POLICY audit_log_retention_delete ON zaghlol.audit_log IS 'RetentionPurger: support actions after 1 year (D-47), other operator actions after 3 years (backend-schema.md section 4).';
        """;

    /// <summary>Undo of the raw SQL, run by Down() before EF drops the tables (the view depends on two of them).</summary>
    public const string DropViewAndTriggers = """
        DROP VIEW IF EXISTS zaghlol.v_entitlements;
        DROP TRIGGER IF EXISTS accounts_before_delete ON zaghlol.accounts;
        DROP TRIGGER IF EXISTS installs_before_delete ON zaghlol.installs;
        DROP TRIGGER IF EXISTS installs_before_update ON zaghlol.installs;
        DROP TRIGGER IF EXISTS purchases_before_update ON zaghlol.purchases;
        DROP FUNCTION IF EXISTS zaghlol.accounts_before_delete();
        DROP FUNCTION IF EXISTS zaghlol.installs_before_delete();
        DROP FUNCTION IF EXISTS zaghlol.installs_before_update();
        DROP FUNCTION IF EXISTS zaghlol.purchases_before_update();
        """;

    public static string Grants => GrantMatrix.ToSql(GrantMatrix.InitialCreate);
}
