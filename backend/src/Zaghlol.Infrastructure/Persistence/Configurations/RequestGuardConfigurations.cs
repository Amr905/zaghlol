using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Infrastructure.Persistence.Configurations;

internal sealed class ReplayGuardEntryConfiguration : IEntityTypeConfiguration<ReplayGuardEntry>
{
    public void Configure(EntityTypeBuilder<ReplayGuardEntry> builder)
    {
        builder.ToTable("replay_guard", t =>
        {
            t.HasCheckConstraint("ck_replay_guard_kind", "kind IN ('signin_google','signin_apple','play_integrity')");
            t.HasCheckConstraint("ck_replay_guard_key_hash_length", "octet_length(key_hash) = 32");
        });

        builder.HasKey(x => x.KeyHash);
        builder.Property(x => x.Kind).HasConversion(DbEnumMaps.ReplayGuardKinds.Converter);
        builder.HasIndex(x => x.ExpiresAt).HasDatabaseName("ix_replay_guard_expires_at");
    }
}

internal sealed class IdempotencyRecordConfiguration : IEntityTypeConfiguration<IdempotencyRecord>
{
    public void Configure(EntityTypeBuilder<IdempotencyRecord> builder)
    {
        builder.ToTable("idempotency_records", t =>
        {
            t.HasCheckConstraint("ck_idempotency_records_operation_id", "operation_id IN ('verifyPurchase','signIn')");
            t.HasCheckConstraint("ck_idempotency_records_idempotency_key_length", "char_length(idempotency_key) = 26");
            t.HasCheckConstraint("ck_idempotency_records_body_sha256_length", "octet_length(body_sha256) = 32");

            // T-130 (FU-052 S-2): a claim row (status 0, with its lease) or a stored final result; nothing else.
            t.HasCheckConstraint("ck_idempotency_records_status", "status = 0 OR status BETWEEN 200 AND 299 OR status IN (409, 422)");
            t.HasCheckConstraint("ck_idempotency_records_claim", "(status = 0) = (claim_id IS NOT NULL)");
        });

        builder.HasKey(x => new { x.InstallId, x.OperationId, x.IdempotencyKey });
        builder.Property(x => x.OperationId).HasConversion(DbEnumMaps.IdempotentOperations.Converter);
        builder.HasIndex(x => x.AccountId).HasDatabaseName("ix_idempotency_account").HasFilter("account_id IS NOT NULL");
        builder.HasIndex(x => x.ExpiresAt).HasDatabaseName("ix_idempotency_records_expires_at");
    }
}
