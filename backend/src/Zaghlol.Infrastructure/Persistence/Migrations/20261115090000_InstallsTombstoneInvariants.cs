using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Zaghlol.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// FU-020 (T-122 R2-1, tests N1): tightens <c>installs_before_update</c>. (1) The tombstone exemption used to let
    /// <c>seat_key_hash</c> change to any value once <c>deleted_at</c> was set; now the only change allowed on an existing hash is
    /// to NULL, in the statement that sets <c>deleted_at</c> or later on an already tombstoned row, and a tombstoned install can never gain a hash. (2)
    /// <c>deleted_at</c> is one-way: once set it can't be cleared or changed. Behaviour for live installs is unchanged. Trigger text
    /// only, no schema change (the model snapshot is unchanged). Down restores the InitialCreate function body.
    /// </summary>
    public partial class InstallsTombstoneInvariants : Migration
    {
        /// <summary>The replacement function (a constant so the integration test runs exactly this text).</summary>
        internal const string Sql =
                """
                CREATE OR REPLACE FUNCTION zaghlol.installs_before_update() RETURNS trigger
                  LANGUAGE plpgsql SET search_path = zaghlol, pg_temp AS $fn$
                BEGIN
                  IF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS DISTINCT FROM OLD.deleted_at THEN
                    RAISE EXCEPTION 'installs.deleted_at is one-way'
                      USING ERRCODE = 'check_violation', CONSTRAINT = 'installs_deleted_at_one_way';
                  END IF;
                  IF NEW.seat_key_hash IS DISTINCT FROM OLD.seat_key_hash
                     AND (NEW.seat_key_hash IS NOT NULL AND (OLD.seat_key_hash IS NOT NULL OR NEW.deleted_at IS NOT NULL)
                          OR NEW.seat_key_hash IS NULL AND NEW.deleted_at IS NULL) THEN
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
                """;

        internal const string DownSql =
                """
                CREATE OR REPLACE FUNCTION zaghlol.installs_before_update() RETURNS trigger
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
                """;

        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder) => migrationBuilder.Sql(Sql);

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder) => migrationBuilder.Sql(DownSql);
    }
}
