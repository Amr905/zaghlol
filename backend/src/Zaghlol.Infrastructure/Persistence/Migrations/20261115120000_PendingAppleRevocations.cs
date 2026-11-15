using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Zaghlol.Infrastructure.Persistence.Migrations
{
    /// <summary>
    /// T-135 (Lead decision): <c>DELETE /v1/accounts/me</c> always deletes the account; when Apple can't revoke the Sign in with Apple
    /// refresh token, only the re-sealed token goes here and a worker retries with back-off until <c>expires_at</c> (30 days), then drops
    /// it. The table deliberately has no account, install or subject column. It is plain SQL outside the EF model (like the trigger
    /// migrations), so the model snapshot is unchanged. Down drops the table and its grants.
    /// </summary>
    public partial class PendingAppleRevocations : Migration
    {
        internal const string Sql =
                """
                CREATE TABLE zaghlol.pending_apple_revocations (
                  id uuid NOT NULL,
                  sealed_blob bytea NOT NULL,
                  attempts integer NOT NULL DEFAULT 0,
                  created_at timestamptz NOT NULL,
                  next_attempt_at timestamptz NOT NULL,
                  expires_at timestamptz NOT NULL,
                  CONSTRAINT pk_pending_apple_revocations PRIMARY KEY (id),
                  CONSTRAINT ck_pending_apple_revocations_attempts CHECK (attempts >= 0),
                  CONSTRAINT ck_pending_apple_revocations_window CHECK (expires_at > created_at)
                );
                CREATE INDEX ix_pending_apple_revocations_next_attempt_at ON zaghlol.pending_apple_revocations (next_attempt_at);
                CREATE INDEX ix_pending_apple_revocations_expires_at ON zaghlol.pending_apple_revocations (expires_at);
                """;

        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql(Sql);
            migrationBuilder.Sql(GrantMatrix.ToSql(GrantMatrix.PendingAppleRevocations));
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder) =>
            migrationBuilder.Sql("DROP TABLE zaghlol.pending_apple_revocations;");
    }
}
