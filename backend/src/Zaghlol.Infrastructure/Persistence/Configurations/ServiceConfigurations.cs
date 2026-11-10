using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Infrastructure.Persistence.Configurations;

internal sealed class FeatureFlagConfiguration : IEntityTypeConfiguration<FeatureFlag>
{
    public void Configure(EntityTypeBuilder<FeatureFlag> builder)
    {
        builder.ToTable("feature_flags");

        builder.HasKey(x => x.Key);
        builder.Property(x => x.Enabled).HasDefaultValue(false);
        builder.Property(x => x.Rules).HasColumnType("jsonb").HasDefaultValueSql("'{}'");
    }
}

internal sealed class PriceQuoteConfiguration : IEntityTypeConfiguration<PriceQuote>
{
    public void Configure(EntityTypeBuilder<PriceQuote> builder)
    {
        builder.ToTable("price_quotes", t =>
        {
            t.HasCheckConstraint("ck_price_quotes_price_positive", "price > 0 AND (feed_price IS NULL OR feed_price > 0)");
            t.HasCheckConstraint("ck_price_quotes_override_expiry", "is_override = (override_expires_at IS NOT NULL)");
        });

        builder.HasKey(x => new { x.Symbol, x.Currency });
        builder.Property(x => x.Price).HasPrecision(20, 6);
        builder.Property(x => x.FeedPrice).HasPrecision(20, 6);
        builder.Property(x => x.IsOverride).HasDefaultValue(false);
    }
}

internal sealed class FxRateConfiguration : IEntityTypeConfiguration<FxRate>
{
    public void Configure(EntityTypeBuilder<FxRate> builder)
    {
        builder.ToTable("fx_rates");

        builder.HasKey(x => new { x.Base, x.Quote });
        builder.Property(x => x.Rate).HasPrecision(24, 12);
    }
}

internal sealed class MerchantContributionConfiguration : IEntityTypeConfiguration<MerchantContribution>
{
    public void Configure(EntityTypeBuilder<MerchantContribution> builder)
    {
        builder.ToTable("merchant_contributions", t =>
        {
            // Privacy CHECKs (backend-schema.md section 3): no digit runs (phone/card/account numbers, any script), no "@",
            // a length cap, and the code columns restricted to their slug alphabets.
            t.HasCheckConstraint("ck_merchant_contributions_merchant_norm", CheckSql.PrivacySafeNorm("merchant_norm"));
            t.HasCheckConstraint(
                "ck_merchant_contributions_institution_code",
                $"institution_code ~ '{CheckSql.InstitutionCodeAlphabet}'");
            t.HasCheckConstraint("ck_merchant_contributions_category_code", $"category_code ~ '{CheckSql.CategoryCodeAlphabet}'");
            t.HasCheckConstraint("ck_merchant_contributions_install_hash_length", "octet_length(install_hash) = 32");
        });

        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).ValueGeneratedNever();
        builder.Property(x => x.ReceivedAt).HasDefaultValueSql("now()");
        // Named explicitly: the convention name would be 69 characters, over PostgreSQL's 63-byte identifier limit.
        builder.HasIndex(x => new { x.MerchantNorm, x.InstitutionCode, x.InstallHash })
            .IsUnique()
            .HasDatabaseName("ux_merchant_contributions_identity");
        builder.HasIndex(x => x.ReceivedAt).HasDatabaseName("ix_merchant_contributions_received_at");
    }
}

internal sealed class ContributionAggregateConfiguration : IEntityTypeConfiguration<ContributionAggregate>
{
    public void Configure(EntityTypeBuilder<ContributionAggregate> builder)
    {
        builder.ToTable(
            "contribution_aggregates",
            t => t.HasCheckConstraint(
                "ck_contribution_aggregates_status",
                "status IN ('collecting','ready_for_review','promoted','rejected')"));

        builder.HasKey(x => new { x.MerchantNorm, x.InstitutionCode });
        builder.Property(x => x.CategoryVotes).HasColumnType("jsonb");
        builder.Property(x => x.Status).HasConversion(DbEnumMaps.AggregateStatuses.Converter);
    }
}

internal sealed class BankRequestConfiguration : IEntityTypeConfiguration<BankRequest>
{
    public void Configure(EntityTypeBuilder<BankRequest> builder)
    {
        builder.ToTable("bank_requests", t =>
        {
            t.HasCheckConstraint("ck_bank_requests_institution_name_norm", CheckSql.PrivacySafeNorm("institution_name_norm"));
            t.HasCheckConstraint("ck_bank_requests_country", "country ~ '^[A-Z]{2}$'");
            t.HasCheckConstraint("ck_bank_requests_channel", "channel IN ('sms','notification')");
            t.HasCheckConstraint("ck_bank_requests_install_hash_length", "octet_length(install_hash) = 32");
        });

        builder.HasKey(x => new { x.InstitutionNameNorm, x.Country, x.Channel, x.InstallHash });
        builder.Property(x => x.Channel).HasConversion(DbEnumMaps.BankRequestChannels.Converter);
        builder.Property(x => x.ReceivedAt).HasDefaultValueSql("now()");
        builder.HasIndex(x => x.ReceivedAt).HasDatabaseName("ix_bank_requests_received_at");
    }
}

internal sealed class DailyActiveCountConfiguration : IEntityTypeConfiguration<DailyActiveCount>
{
    public void Configure(EntityTypeBuilder<DailyActiveCount> builder)
    {
        builder.ToTable(
            "daily_active_counts",
            t => t.HasCheckConstraint("ck_daily_active_counts_app_version", CheckSql.AppVersion("app_version")));

        builder.HasKey(x => new { x.Day, x.Platform, x.AppVersion });
    }
}

internal sealed class OperatorAccountConfiguration : IEntityTypeConfiguration<OperatorAccount>
{
    public void Configure(EntityTypeBuilder<OperatorAccount> builder)
    {
        builder.ToTable("operators");

        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).ValueGeneratedNever();
        builder.HasIndex(x => x.OidcSubject).IsUnique();
    }
}

internal sealed class AuditLogEntryConfiguration : IEntityTypeConfiguration<AuditLogEntry>
{
    /// <summary>
    /// No e-mail or order ID under any key at any depth, in any letter case, and no "@" in any value (D-57, NFR-PRIV-07).
    /// <c>jsonb_path_exists</c> without <c>_tz</c> is immutable.
    /// </summary>
    public const string DetailsNoIdentifiers =
        "NOT jsonb_path_exists(details, 'lax $.** ? (@.type() == \"object\").keyvalue() "
        + "? (@.key like_regex \"^(e-?mail|order_?id)$\" flag \"i\")') AND details::text !~ '@'";

    public void Configure(EntityTypeBuilder<AuditLogEntry> builder)
    {
        builder.ToTable("audit_log", t =>
        {
            t.HasCheckConstraint("ck_audit_log_details_no_identifiers", DetailsNoIdentifiers);
            t.HasCheckConstraint("ck_audit_log_target_no_email", "position('@' in target) = 0");
        });

        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).UseIdentityAlwaysColumn();
        builder.Property(x => x.Details).HasColumnType("jsonb");
        builder.Property(x => x.At).HasDefaultValueSql("now()");

        // Rows can only name a real operator (operators are disabled, never deleted). Append-only and the retention-gated
        // DELETE are enforced by row-level security (InitialCreateSql.AuditLogRowLevelSecurity).
        builder.HasOne<OperatorAccount>().WithMany().HasForeignKey(x => x.OperatorId).OnDelete(DeleteBehavior.NoAction);

        // Retention (backend-schema.md section 4): support rows after exactly 1 year, all others after 3 years.
        // Two indexes on the same column, so both are named in the model too.
        builder.HasIndex(x => x.At, "ix_audit_log_at").HasDatabaseName("ix_audit_log_at");
        builder.HasIndex(x => x.At, "ix_audit_log_support_at")
            .HasDatabaseName("ix_audit_log_support_at")
            .HasFilter("action IN ('support_lookup','support_seat_move','support_detach','support_unfreeze')");
    }
}
