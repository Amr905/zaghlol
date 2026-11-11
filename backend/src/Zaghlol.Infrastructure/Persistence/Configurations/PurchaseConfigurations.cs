using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Infrastructure.Persistence.Configurations;

internal sealed class PurchaseConfiguration : IEntityTypeConfiguration<Purchase>
{
    public void Configure(EntityTypeBuilder<Purchase> builder)
    {
        builder.ToTable("purchases", t =>
        {
            t.HasCheckConstraint("ck_purchases_store", "store IN ('google_play','app_store')");
            t.HasCheckConstraint("ck_purchases_plan", "plan IN ('monthly','yearly','lifetime')");
            t.HasCheckConstraint("ck_purchases_account_linked_by", "account_linked_by IN ('signin','support')");
            t.HasCheckConstraint(
                "ck_purchases_state",
                "state IN ('pending','active','in_grace','on_hold','paused','canceled_active','expired','refunded','revoked')");
            t.HasCheckConstraint("ck_purchases_environment", "environment IN ('production','sandbox')");
            t.HasCheckConstraint("ck_purchases_account_link_pair", "(account_id IS NULL) = (account_linked_by IS NULL)");
            t.HasCheckConstraint("ck_purchases_store_key_length", $"char_length(store_key) <= {CheckSql.StoreKeyMaxLength}");
        });

        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).ValueGeneratedNever();
        builder.Property(x => x.Store).HasConversion(DbEnumMaps.Stores.Converter);
        builder.Property(x => x.Plan).HasConversion(DbEnumMaps.Plans.Converter);
        builder.Property(x => x.AccountLinkedBy).HasConversion(DbEnumMaps.AccountLinkSources.Converter);
        builder.Property(x => x.SupportLinkNoticePending).HasDefaultValue(false);
        builder.Property(x => x.State).HasConversion(DbEnumMaps.PurchaseStates.Converter);
        builder.Property(x => x.Acknowledged).HasDefaultValue(false);
        builder.Property(x => x.Environment).HasConversion(DbEnumMaps.StoreEnvironments.Converter);
        builder.Property(x => x.CreatedAt).HasDefaultValueSql("now()");

        builder.HasIndex(x => new { x.Store, x.StoreKey }).IsUnique();
        builder.HasIndex(x => x.InstallId).HasDatabaseName("ix_purchases_install");
        builder.HasIndex(x => x.AccountId).HasDatabaseName("ix_purchases_account");
        builder.HasIndex(x => x.CreatedAt)
            .HasDatabaseName("ix_purchases_unacked")
            .HasFilter("store = 'google_play' AND acknowledged = false");

        // ON DELETE SET NULL. Deleting an account must also clear account_linked_by: the BEFORE DELETE trigger on accounts
        // (InitialCreateSql) does both before the FK action runs, so the link-pair CHECK holds.
        builder.HasOne<Install>().WithMany().HasForeignKey(x => x.InstallId).OnDelete(DeleteBehavior.SetNull);
        builder.HasOne<Account>().WithMany().HasForeignKey(x => x.AccountId).OnDelete(DeleteBehavior.SetNull);
    }
}

internal sealed class PurchaseEventConfiguration : IEntityTypeConfiguration<PurchaseEvent>
{
    /// <summary>Exactly the causes documented for <c>purchase_events.cause</c>.</summary>
    public const string CausePattern =
        "^(verify|restore|seat_bind|sweep"
        + "|seat_move:(restore|signin|support|account_attach|verify)"
        + "|seat_rebind:(restore|signin)"
        + "|seat_rebind_over_cap:(restore|signin)"
        + "|(rtdn|assn):[A-Za-z0-9_]{1,64})$";

    public void Configure(EntityTypeBuilder<PurchaseEvent> builder)
    {
        builder.ToTable("purchase_events", t => t.HasCheckConstraint("ck_purchase_events_cause", $"cause ~ '{CausePattern}'"));

        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).ValueGeneratedNever();
        builder.Property(x => x.FromState).HasConversion(DbEnumMaps.PurchaseStates.Converter);
        builder.Property(x => x.ToState).HasConversion(DbEnumMaps.PurchaseStates.Converter);
        builder.Property(x => x.OccurredAt).HasDefaultValueSql("now()");
        builder.HasOne<Purchase>().WithMany().HasForeignKey(x => x.PurchaseId).OnDelete(DeleteBehavior.Cascade);
    }
}

internal sealed class PurchaseSeatConfiguration : IEntityTypeConfiguration<PurchaseSeat>
{
    public void Configure(EntityTypeBuilder<PurchaseSeat> builder)
    {
        builder.ToTable("purchase_seats", t =>
        {
            t.HasCheckConstraint("ck_purchase_seats_proof", "proof IN ('binding','attested','basic','account','support','device')");
            t.HasCheckConstraint("ck_purchase_seats_holder_proof", "(install_id IS NULL) = (proof IS NULL)");
            t.HasCheckConstraint("ck_purchase_seats_move_pair", "(last_moved_at IS NULL) = (next_move_at IS NULL)");

            // Deviation from the doc's date_trunc('hour', x): the two-argument form truncates in the session time zone, so
            // a whole UTC hour would fail in a zone with a non-hour offset (e.g. Asia/Kolkata). The three-argument form
            // truncates in UTC whatever the session time zone is.
            t.HasCheckConstraint(
                "ck_purchase_seats_next_move_whole_hour",
                "next_move_at IS NULL OR date_trunc('hour', next_move_at, 'UTC') = next_move_at");
            t.HasCheckConstraint("ck_purchase_seats_recent_rebinds_cap", "cardinality(recent_rebinds) <= 2");
            t.HasCheckConstraint("ck_purchase_seats_device_key_hash_length", "octet_length(device_key_hash) = 32");
        });

        builder.HasKey(x => x.PurchaseId);
        builder.Property(x => x.Proof).HasConversion(DbEnumMaps.SeatProofs.Converter);
        builder.Property(x => x.DeviceKeyTrusted).HasDefaultValue(false);
        builder.Property(x => x.RecentRebinds).HasDefaultValueSql("'{}'");
        builder.HasIndex(x => x.InstallId).HasDatabaseName("ix_purchase_seats_install");

        builder.HasOne<Purchase>().WithOne().HasForeignKey<PurchaseSeat>(x => x.PurchaseId).OnDelete(DeleteBehavior.Cascade);

        // ON DELETE SET NULL; the BEFORE DELETE trigger on installs vacates the seat first (install_id, proof, bound_at)
        // so the holder/proof CHECK holds, and keeps device_key_hash, device_key_trusted and the move times (D-55).
        builder.HasOne<Install>().WithMany().HasForeignKey(x => x.InstallId).OnDelete(DeleteBehavior.SetNull);
    }
}

internal sealed class SeatClaimantConfiguration : IEntityTypeConfiguration<SeatClaimant>
{
    public void Configure(EntityTypeBuilder<SeatClaimant> builder)
    {
        builder.ToTable("seat_claimants", t =>
        {
            t.HasCheckConstraint("ck_seat_claimants_channel", "channel IN ('restore','signin','verify')");
            t.HasCheckConstraint("ck_seat_claimants_device_key_hash_length", "octet_length(device_key_hash) = 32");
        });

        builder.HasKey(x => new { x.PurchaseId, x.InstallId });
        builder.Property(x => x.Channel).HasConversion(DbEnumMaps.ClaimantChannels.Converter);
        builder.HasIndex(x => x.ClaimedAt).HasDatabaseName("ix_seat_claimants_claimed_at");
        builder.HasOne<Purchase>().WithMany().HasForeignKey(x => x.PurchaseId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne<Install>().WithMany().HasForeignKey(x => x.InstallId).OnDelete(DeleteBehavior.Cascade);
    }
}

internal sealed class AppAttestKeyConfiguration : IEntityTypeConfiguration<AppAttestKey>
{
    public void Configure(EntityTypeBuilder<AppAttestKey> builder)
    {
        builder.ToTable("app_attest_keys", t =>
        {
            t.HasCheckConstraint("ck_app_attest_keys_environment", "environment IN ('production','development')");
            t.HasCheckConstraint("ck_app_attest_keys_key_id_length", "octet_length(key_id) = 32");
        });

        builder.HasKey(x => x.KeyId);
        builder.Property(x => x.Environment).HasConversion(DbEnumMaps.AttestEnvironments.Converter);
        builder.Property(x => x.AttestedAt).HasDefaultValueSql("now()");
        builder.HasIndex(x => x.InstallId).IsUnique();
        builder.HasOne<Install>().WithMany().HasForeignKey(x => x.InstallId).OnDelete(DeleteBehavior.Cascade);
    }
}

internal sealed class EffectiveEntitlementConfiguration : IEntityTypeConfiguration<EffectiveEntitlement>
{
    public void Configure(EntityTypeBuilder<EffectiveEntitlement> builder)
    {
        // Created by raw SQL in InitialCreate; a view mapping is never part of a migration.
        builder.HasNoKey().ToView("v_entitlements");
        builder.Property(x => x.Plan).HasConversion(DbEnumMaps.Plans.Converter);
        builder.Property(x => x.State).HasConversion(DbEnumMaps.PurchaseStates.Converter);
        builder.Property(x => x.Store).HasConversion(DbEnumMaps.Stores.Converter);
        builder.Property(x => x.Proof).HasConversion(DbEnumMaps.SeatProofs.Converter);
    }
}

internal sealed class StoreNotificationConfiguration : IEntityTypeConfiguration<StoreNotification>
{
    /// <summary>The <c>ck_store_notifications_google_shape</c> expression (backend-schema <c>store_notifications</c>, T-133).</summary>
    public const string GoogleShapeSql =
        "store <> 'google_play' OR (subtype IS NULL AND environment IS NULL AND (external_id ~ '^[A-Za-z0-9_-]{1,100}$' "
        + "OR external_id ~ '^voided:[0-9a-f]{64}$' OR external_id ~ '^sweep:[0-9a-f-]{36}:[0-9]{1,12}$'))";

    public void Configure(EntityTypeBuilder<StoreNotification> builder)
    {
        builder.ToTable("store_notifications", t =>
        {
            t.HasCheckConstraint("ck_store_notifications_environment", "environment IN ('production','sandbox')");
            t.HasCheckConstraint("ck_store_notifications_payload_digest_length", "octet_length(payload_digest) = 32");

            // "error code only; never payload text"
            t.HasCheckConstraint("ck_store_notifications_last_error", "last_error ~ '^[A-Z0-9_]{1,64}$'");
            t.HasCheckConstraint(
                "ck_store_notifications_store_key_length",
                $"char_length(store_key) <= {CheckSql.StoreKeyMaxLength}");

            // T-134: store-defined type names only (T-133 reuses both).
            t.HasCheckConstraint("ck_store_notifications_type", "type ~ '^[A-Z0-9_]{1,64}$'");
            t.HasCheckConstraint("ck_store_notifications_subtype", "subtype IS NULL OR subtype ~ '^[A-Z0-9_]{1,64}$'");

            // T-133 (§2): Google rows have no subtype or environment, and an external_id that is a Pub/Sub messageId or one of the two
            // job keys, so a worker-login row injection can't fake another shape (the processor's step 0 refuses the rest).
            t.HasCheckConstraint("ck_store_notifications_google_shape", GoogleShapeSql);
        });

        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).ValueGeneratedNever();
        builder.Property(x => x.NotificationType).HasColumnName("type");
        builder.Property(x => x.Environment).HasConversion(DbEnumMaps.StoreEnvironments.Converter);
        builder.Property(x => x.ReceivedAt).HasDefaultValueSql("now()");
        builder.Property(x => x.Attempts).HasDefaultValue(0);
        builder.HasIndex(x => new { x.Store, x.ExternalId }).IsUnique();
        builder.HasIndex(x => x.ReceivedAt).HasDatabaseName("ix_store_notifications_received_at");

        // T-134: the processor's pick (never-failed first, then due, then oldest) over unprocessed rows only.
        builder.HasIndex(x => new { x.Store, x.NextAttemptAt, x.ReceivedAt })
            .HasDatabaseName("ix_store_notifications_due")
            .HasNullSortOrder(NullSortOrder.NullsFirst, NullSortOrder.NullsLast, NullSortOrder.NullsLast)
            .HasFilter("processed_at IS NULL");
    }
}
