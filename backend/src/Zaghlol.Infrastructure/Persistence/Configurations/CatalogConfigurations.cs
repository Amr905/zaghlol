using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Infrastructure.Persistence.Configurations;

internal sealed class CatalogVersionConfiguration : IEntityTypeConfiguration<CatalogVersion>
{
    public void Configure(EntityTypeBuilder<CatalogVersion> builder)
    {
        builder.ToTable(
            "catalog_versions",
            t => t.HasCheckConstraint("ck_catalog_versions_full_snapshot_sha256_length", "octet_length(full_snapshot_sha256) = 32"));

        builder.HasKey(x => x.Version);
        builder.Property(x => x.Version).ValueGeneratedNever();
        builder.Property(x => x.FullSnapshotUrl).HasConversion<string>();
    }
}

internal sealed class CatalogCategoryConfiguration : IEntityTypeConfiguration<CatalogCategory>
{
    public void Configure(EntityTypeBuilder<CatalogCategory> builder)
    {
        builder.ToTable("catalog_categories");

        builder.HasKey(x => x.Code);
        builder.Property(x => x.Deleted).HasDefaultValue(false);
        builder.HasOne<CatalogCategory>().WithMany().HasForeignKey(x => x.ParentCode).OnDelete(DeleteBehavior.NoAction);
    }
}

internal sealed class CatalogMerchantConfiguration : IEntityTypeConfiguration<CatalogMerchant>
{
    public void Configure(EntityTypeBuilder<CatalogMerchant> builder)
    {
        builder.ToTable("catalog_merchants");

        builder.HasKey(x => x.Id);
        builder.Property(x => x.Id).UseIdentityAlwaysColumn();
        builder.Property(x => x.Deleted).HasDefaultValue(false);
        builder.HasIndex(x => x.Canonical).IsUnique();
        builder.HasOne<CatalogCategory>().WithMany().HasForeignKey(x => x.CategoryCode).OnDelete(DeleteBehavior.NoAction);
    }
}

internal sealed class CatalogAliasConfiguration : IEntityTypeConfiguration<CatalogAlias>
{
    public void Configure(EntityTypeBuilder<CatalogAlias> builder)
    {
        builder.ToTable("catalog_aliases");

        builder.HasKey(x => new { x.AliasNorm, x.MerchantId });
        builder.Property(x => x.Deleted).HasDefaultValue(false);
        builder.HasOne<CatalogMerchant>().WithMany().HasForeignKey(x => x.MerchantId).OnDelete(DeleteBehavior.NoAction);
    }
}

internal sealed class CatalogKeywordConfiguration : IEntityTypeConfiguration<CatalogKeyword>
{
    public void Configure(EntityTypeBuilder<CatalogKeyword> builder)
    {
        // No FK on category_code: backend-schema.md declares none for keywords.
        builder.ToTable("catalog_keywords");

        builder.HasKey(x => new { x.KeywordNorm, x.Lang });
        builder.Property(x => x.Deleted).HasDefaultValue(false);
    }
}

internal sealed class CatalogDraftEntryConfiguration : IEntityTypeConfiguration<CatalogDraftEntry>
{
    public void Configure(EntityTypeBuilder<CatalogDraftEntry> builder)
    {
        builder.ToTable(
            "catalog_drafts",
            t => t.HasCheckConstraint("ck_catalog_drafts_entity", "entity IN ('categories','merchants','aliases','keywords')"));

        builder.HasKey(x => new { x.Entity, x.EntryKey });

        // The identity is the merchant id allocator (an identity needs no sequence grant, FU-026) and the paging order.
        builder.Property(x => x.Seq).UseIdentityAlwaysColumn();
        builder.HasIndex(x => x.Seq).IsUnique();

        builder.Property(x => x.Body).HasColumnType("jsonb");
        builder.Property(x => x.Deleted).HasDefaultValue(false);
        builder.Property(x => x.Published).HasDefaultValue(false);
        builder.Property(x => x.UpdatedAt).HasDefaultValueSql("now()");
    }
}
