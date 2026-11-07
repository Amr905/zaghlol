namespace Zaghlol.Infrastructure.Persistence;

/// <summary>
/// The parts of the InitialCreate migration EF can't model: the entitlement view, the two BEFORE DELETE triggers, the
/// grants and the comments. Frozen with the migration: a later change goes into a new migration, never here.
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

    public const string Comments = """
        COMMENT ON VIEW zaghlol.v_entitlements IS 'Effective entitlement, computed not stored: purchases whose seat the install holds, in an entitling state. A row with account_id set counts only with a valid account token for that account (D-61(c)).';
        COMMENT ON FUNCTION zaghlol.accounts_before_delete() IS 'Backstop for account deletion: clears purchases.account_id and account_linked_by together; never attach_reclaim_used_at (D-58).';
        COMMENT ON FUNCTION zaghlol.installs_before_delete() IS 'Vacates purchase_seats held by the deleted install; keeps device_key_hash, device_key_trusted and the move times (D-55).';
        """;

    /// <summary>Undo of the raw SQL, run by Down() before EF drops the tables (the view depends on two of them).</summary>
    public const string DropViewAndTriggers = """
        DROP VIEW IF EXISTS zaghlol.v_entitlements;
        DROP TRIGGER IF EXISTS accounts_before_delete ON zaghlol.accounts;
        DROP TRIGGER IF EXISTS installs_before_delete ON zaghlol.installs;
        DROP FUNCTION IF EXISTS zaghlol.accounts_before_delete();
        DROP FUNCTION IF EXISTS zaghlol.installs_before_delete();
        """;

    public static string Grants => GrantMatrix.ToSql(GrantMatrix.InitialCreate);
}
