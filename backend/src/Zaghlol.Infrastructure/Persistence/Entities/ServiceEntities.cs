namespace Zaghlol.Infrastructure.Persistence.Entities;

// backend-schema.md section 2: feature flags, prices, contributions, bank requests, counters, operators and audit.

/// <summary><c>feature_flags</c> (FR-BE-05).</summary>
public sealed class FeatureFlag
{
    public required string Key { get; set; }

    public bool Enabled { get; set; }

    /// <summary><c>jsonb</c>: {platforms:[], min_app_version, rollout_percent}.</summary>
    public required string Rules { get; set; }

    public int Version { get; set; }

    public DateTimeOffset UpdatedAt { get; set; }

    public Guid UpdatedBy { get; set; }
}

/// <summary><c>price_quotes</c> (FR-BE-04). Prices are <c>numeric</c>, never floating point.</summary>
public sealed class PriceQuote
{
    public required string Symbol { get; set; }

    public required string Currency { get; set; }

    public decimal Price { get; set; }

    public required string PerUnit { get; set; }

    public DateTimeOffset AsOf { get; set; }

    public required string Source { get; set; }

    public bool IsOverride { get; set; }

    public DateTimeOffset? OverrideExpiresAt { get; set; }
}

/// <summary><c>fx_rates</c>.</summary>
public sealed class FxRate
{
    public required string Base { get; set; }

    public required string Quote { get; set; }

    public decimal Rate { get; set; }

    public DateTimeOffset AsOf { get; set; }

    public required string Source { get; set; }
}

/// <summary><c>merchant_contributions</c> (FR-BE-07, BR-SYNC-04).</summary>
public sealed class MerchantContribution
{
    public Guid Id { get; set; }

    public required string MerchantNorm { get; set; }

    public required string InstitutionCode { get; set; }

    public required string CategoryCode { get; set; }

    /// <summary>HMAC(install_id, pepper) from <c>IKeyedHasher</c>; can't be joined back to installs.</summary>
    public required byte[] InstallHash { get; set; }

    public DateTimeOffset ReceivedAt { get; set; }
}

/// <summary><c>contribution_aggregates</c>.</summary>
public sealed class ContributionAggregate
{
    public required string MerchantNorm { get; set; }

    public required string InstitutionCode { get; set; }

    public int DistinctInstalls { get; set; }

    public required string TopCategoryCode { get; set; }

    /// <summary><c>jsonb</c>.</summary>
    public required string CategoryVotes { get; set; }

    public AggregateStatus Status { get; set; }

    public Guid? ReviewedBy { get; set; }

    public DateTimeOffset? ReviewedAt { get; set; }
}

/// <summary><c>bank_requests</c> (FR-BE-10).</summary>
public sealed class BankRequest
{
    public required string InstitutionNameNorm { get; set; }

    public required string Country { get; set; }

    public BankRequestChannel Channel { get; set; }

    public required byte[] InstallHash { get; set; }

    public DateTimeOffset ReceivedAt { get; set; }
}

/// <summary><c>daily_active_counts</c> (OQ-01, ADR-021): anonymous aggregate counters.</summary>
public sealed class DailyActiveCount
{
    public DateOnly Day { get; set; }

    public required string Platform { get; set; }

    public required string AppVersion { get; set; }

    public int Installs { get; set; }
}

/// <summary><c>operators</c> (FR-BE-08).</summary>
public sealed class OperatorAccount
{
    public Guid Id { get; set; }

    public required string OidcSubject { get; set; }

    public required string DisplayName { get; set; }

    public required string[] Roles { get; set; }

    public DateTimeOffset? DisabledAt { get; set; }
}

/// <summary><c>audit_log</c>: append-only (no role has UPDATE); never an e-mail, an order ID or free text.</summary>
public sealed class AuditLogEntry
{
    public long Id { get; set; }

    public Guid OperatorId { get; set; }

    public required string Action { get; set; }

    public required string Target { get; set; }

    /// <summary><c>jsonb</c>; must not hold the keys email, order_id or orderId (CHECK).</summary>
    public required string Details { get; set; }

    public DateTimeOffset At { get; set; }
}
