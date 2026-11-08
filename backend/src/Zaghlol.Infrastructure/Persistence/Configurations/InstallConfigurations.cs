using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Infrastructure.Persistence.Configurations;

// CHECK SQL is copied verbatim from backend-schema.md section 2; names follow ck_<table>_<rule> (stable for the tests).

internal sealed class InstallConfiguration : IEntityTypeConfiguration<Install>
{
    /// <summary>The R5-2 column comment, word for word from backend-schema.md section 2.</summary>
    public const string SeatKeyTrustedComment =
        "set ONLY by an App Attest-covered request (R5-2): a restore whose assertion covered this key as element 0. "
        + "iOS sign-in has no App Attest (D-66), so it never sets it. Verify and sign-in register the key UNTRUSTED. "
        + "Only false -> true. Gates the over-cap sign-in rebind (D-65(a), backend-api §4.3)";

    public void Configure(EntityTypeBuilder<Install> builder)
    {
        builder.ToTable("installs", t =>
        {
            t.HasCheckConstraint("ck_installs_platform", "platform IN ('android','ios')");
            t.HasCheckConstraint("ck_installs_app_version", CheckSql.AppVersion("app_version"));
            t.HasCheckConstraint("ck_installs_token_hash_length", "octet_length(token_hash) = 32");
            t.HasCheckConstraint("ck_installs_registration_key_hash_length", "octet_length(registration_key_hash) = 32");
            t.HasCheckConstraint("ck_installs_registration_body_sha256_length", "octet_length(registration_body_sha256) = 32");
            t.HasCheckConstraint("ck_installs_seat_key_hash_length", "octet_length(seat_key_hash) = 32");
        });

        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).ValueGeneratedNever();
        builder.Property(x => x.Platform).HasConversion(DbEnumMaps.Platforms.Converter);
        builder.Property(x => x.CatalogVersion).HasDefaultValue(0);
        builder.Property(x => x.FirstSeenAt).HasDefaultValueSql("now()");
        builder.Property(x => x.LastSeenAt).HasDefaultValueSql("now()");
        builder.Property(x => x.SeatKeyTrusted).HasDefaultValue(false).HasComment(SeatKeyTrustedComment);

        // T-124: install-token auth is one indexed lookup by SHA-256(token); two installs can never share a token hash.
        builder.HasIndex(x => x.TokenHash).IsUnique().HasDatabaseName("ux_installs_token_hash");

        // Retention indexes (backend-schema.md section 4).
        builder.HasIndex(x => x.LastSeenAt).HasDatabaseName("ix_installs_last_seen");
        builder.HasIndex(x => x.DeletedAt).HasDatabaseName("ix_installs_deleted_at").HasFilter("deleted_at IS NOT NULL");
        builder.HasIndex(x => x.FirstSeenAt)
            .HasDatabaseName("ix_installs_registration_pending")
            .HasFilter("registration_key_hash IS NOT NULL");
    }
}

internal sealed class AccountConfiguration : IEntityTypeConfiguration<Account>
{
    public void Configure(EntityTypeBuilder<Account> builder)
    {
        builder.ToTable("accounts", t => t.HasCheckConstraint("ck_accounts_provider", "provider IN ('google','apple')"));

        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).ValueGeneratedNever();
        builder.Property(x => x.Provider).HasConversion(DbEnumMaps.AccountProviders.Converter);
        builder.Property(x => x.CreatedAt).HasDefaultValueSql("now()");
        builder.HasIndex(x => new { x.Provider, x.ProviderSubject }).IsUnique();
    }
}

internal sealed class AccountInstallConfiguration : IEntityTypeConfiguration<AccountInstall>
{
    public void Configure(EntityTypeBuilder<AccountInstall> builder)
    {
        builder.ToTable("account_installs");

        builder.HasKey(x => new { x.AccountId, x.InstallId });
        builder.Property(x => x.LinkedAt).HasDefaultValueSql("now()");
        builder.HasOne<Account>().WithMany().HasForeignKey(x => x.AccountId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne<Install>().WithMany().HasForeignKey(x => x.InstallId).OnDelete(DeleteBehavior.Cascade);
    }
}
