using Microsoft.EntityFrameworkCore;
using Zaghlol.Infrastructure.Persistence.Configurations;
using Zaghlol.Infrastructure.Persistence.Entities;

namespace Zaghlol.Infrastructure.Persistence;

/// <summary>
/// The backend schema of <c>docs/03-technical/backend-schema.md</c> section 2. It holds no user financial data
/// (BR-SYNC-03): no messages, transactions, amounts, balances, budgets, assets or user rules.
/// </summary>
/// <remarks>
/// <para><b>Migration rule (expand / contract).</b> A rolling deploy runs API version N-1 against schema N, so:</para>
/// <list type="number">
/// <item>Migration N is additive only: new tables, new nullable columns or columns with a default, new indexes, new
/// grants. It never renames, retypes or drops anything the N-1 code reads or writes.</item>
/// <item>The API and workers of version N-1 must run correctly against schema N.</item>
/// <item>A column or table is dropped only in release N+1, after no deployed code uses it.</item>
/// <item><c>Down()</c> methods exist for local work and tests only; they are never run in production.</item>
/// <item>Each migration that adds a table also adds its explicit GRANTs (<see cref="GrantMatrix"/>); there are no
/// default privileges.</item>
/// </list>
/// <para>Triggers, the <c>v_entitlements</c> view, grants and comments EF can't model are raw SQL in the migration
/// (<see cref="InitialCreateSql"/>). Crypto is never done in the database: hashes and ciphertexts arrive as bytes.</para>
/// </remarks>
public sealed class ZaghlolDbContext(DbContextOptions<ZaghlolDbContext> options) : DbContext(options)
{
    /// <summary>Every object lives in this schema, owned by <c>migrator</c>; nothing goes in <c>public</c>.</summary>
    public const string Schema = "zaghlol";

    public DbSet<Install> Installs => Set<Install>();

    public DbSet<Account> Accounts => Set<Account>();

    public DbSet<AccountInstall> AccountInstalls => Set<AccountInstall>();

    public DbSet<Purchase> Purchases => Set<Purchase>();

    public DbSet<PurchaseEvent> PurchaseEvents => Set<PurchaseEvent>();

    public DbSet<PurchaseSeat> PurchaseSeats => Set<PurchaseSeat>();

    public DbSet<SeatClaimant> SeatClaimants => Set<SeatClaimant>();

    public DbSet<AppAttestKey> AppAttestKeys => Set<AppAttestKey>();

    public DbSet<EffectiveEntitlement> Entitlements => Set<EffectiveEntitlement>();

    public DbSet<ReplayGuardEntry> ReplayGuard => Set<ReplayGuardEntry>();

    public DbSet<IdempotencyRecord> IdempotencyRecords => Set<IdempotencyRecord>();

    public DbSet<StoreNotification> StoreNotifications => Set<StoreNotification>();

    public DbSet<CatalogVersion> CatalogVersions => Set<CatalogVersion>();

    public DbSet<CatalogCategory> CatalogCategories => Set<CatalogCategory>();

    public DbSet<CatalogMerchant> CatalogMerchants => Set<CatalogMerchant>();

    public DbSet<CatalogAlias> CatalogAliases => Set<CatalogAlias>();

    public DbSet<CatalogKeyword> CatalogKeywords => Set<CatalogKeyword>();

    public DbSet<CatalogDraftEntry> CatalogDrafts => Set<CatalogDraftEntry>();

    public DbSet<FeatureFlag> FeatureFlags => Set<FeatureFlag>();

    public DbSet<PriceQuote> PriceQuotes => Set<PriceQuote>();

    public DbSet<FxRate> FxRates => Set<FxRate>();

    public DbSet<MerchantContribution> MerchantContributions => Set<MerchantContribution>();

    public DbSet<ContributionAggregate> ContributionAggregates => Set<ContributionAggregate>();

    public DbSet<BankRequest> BankRequests => Set<BankRequest>();

    public DbSet<DailyActiveCount> DailyActiveCounts => Set<DailyActiveCount>();

    public DbSet<OperatorAccount> Operators => Set<OperatorAccount>();

    public DbSet<AuditLogEntry> AuditLog => Set<AuditLogEntry>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        ArgumentNullException.ThrowIfNull(modelBuilder);

        modelBuilder.HasDefaultSchema(Schema);

        // In backend-schema.md order (T-122 design note); EF orders the CREATE TABLEs by foreign keys.
        modelBuilder.ApplyConfiguration(new InstallConfiguration());
        modelBuilder.ApplyConfiguration(new AccountConfiguration());
        modelBuilder.ApplyConfiguration(new AccountInstallConfiguration());
        modelBuilder.ApplyConfiguration(new PurchaseConfiguration());
        modelBuilder.ApplyConfiguration(new PurchaseEventConfiguration());
        modelBuilder.ApplyConfiguration(new PurchaseSeatConfiguration());
        modelBuilder.ApplyConfiguration(new SeatClaimantConfiguration());
        modelBuilder.ApplyConfiguration(new AppAttestKeyConfiguration());
        modelBuilder.ApplyConfiguration(new EffectiveEntitlementConfiguration());
        modelBuilder.ApplyConfiguration(new ReplayGuardEntryConfiguration());
        modelBuilder.ApplyConfiguration(new IdempotencyRecordConfiguration());
        modelBuilder.ApplyConfiguration(new StoreNotificationConfiguration());
        modelBuilder.ApplyConfiguration(new CatalogVersionConfiguration());
        modelBuilder.ApplyConfiguration(new CatalogCategoryConfiguration());
        modelBuilder.ApplyConfiguration(new CatalogMerchantConfiguration());
        modelBuilder.ApplyConfiguration(new CatalogAliasConfiguration());
        modelBuilder.ApplyConfiguration(new CatalogKeywordConfiguration());
        modelBuilder.ApplyConfiguration(new CatalogDraftEntryConfiguration());
        modelBuilder.ApplyConfiguration(new FeatureFlagConfiguration());
        modelBuilder.ApplyConfiguration(new PriceQuoteConfiguration());
        modelBuilder.ApplyConfiguration(new FxRateConfiguration());
        modelBuilder.ApplyConfiguration(new MerchantContributionConfiguration());
        modelBuilder.ApplyConfiguration(new ContributionAggregateConfiguration());
        modelBuilder.ApplyConfiguration(new BankRequestConfiguration());
        modelBuilder.ApplyConfiguration(new DailyActiveCountConfiguration());
        modelBuilder.ApplyConfiguration(new OperatorAccountConfiguration());
        modelBuilder.ApplyConfiguration(new AuditLogEntryConfiguration());

        SnakeCaseNaming.Apply(modelBuilder.Model);
    }
}
