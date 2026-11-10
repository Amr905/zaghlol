using System.Globalization;

namespace Zaghlol.Application.Prices;

/// <summary>A validated override request (the endpoint has already parsed the JSON strictly).</summary>
public sealed record PriceOverrideInput(string? Symbol, string? Currency, string? Price, string? Reason, DateTimeOffset? ExpiresAt);

/// <summary>The outcome of an override request: the stored row, or <see cref="Invalid"/> for any <c>400 VALIDATION_FAILED</c>.</summary>
public sealed record PriceOverrideResult(PriceRow? Row, bool Invalid)
{
    public static PriceOverrideResult Rejected { get; } = new(null, true);
}

/// <summary>
/// <c>PUT /admin/v1/prices/override</c> (backend-api §4.8): validation and the audited write. <c>expiresAt</c> defaults to 24 h
/// and may be at most 7 days ahead; after it the feed value applies again.
/// </summary>
public sealed class PriceOverrideService(IPriceAdminStore store, TimeProvider clock)
{
    public static readonly TimeSpan DefaultExpiry = TimeSpan.FromHours(24);
    public static readonly TimeSpan MaxExpiry = TimeSpan.FromDays(7);

    /// <summary>The OpenAPI <c>reason</c> limits.</summary>
    public const int ReasonMin = 3;
    public const int ReasonMax = 200;

    /// <summary>Wire <c>DecimalString</c> limited to the 6 decimals of <c>numeric(20,6)</c>.</summary>
    public const int MaxDecimals = 6;

    public async Task<PriceOverrideResult> SetAsync(PriceOverrideInput input, Guid operatorId, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(input);

        var now = clock.GetUtcNow();
        if (!PriceSymbols.IsGold(input.Symbol)
            || !PriceSymbols.IsGoldCurrency(input.Currency)
            || !TryParsePrice(input.Price, out var price)
            || !IsValidReason(input.Reason))
        {
            return PriceOverrideResult.Rejected;
        }

        var expiresAt = input.ExpiresAt ?? now + DefaultExpiry;
        if (expiresAt <= now || expiresAt > now + MaxExpiry)
        {
            return PriceOverrideResult.Rejected;
        }

        var row = await store.SetOverrideAsync(input.Symbol!, input.Currency!, price, input.Reason!.Trim(), now, expiresAt, operatorId, cancellationToken);
        return new PriceOverrideResult(row, false);
    }

    /// <summary>Ends an override early (audited). No HTTP route: the signed-off contract has none (T-137 decides).</summary>
    public Task<bool> ClearAsync(string symbol, string currency, Guid operatorId, CancellationToken cancellationToken) =>
        PriceSymbols.IsGold(symbol) && PriceSymbols.IsGoldCurrency(currency)
            ? store.ClearOverrideAsync(symbol, currency, clock.GetUtcNow(), operatorId, cancellationToken)
            : Task.FromResult(false);

    public static bool IsValidReason(string? reason)
    {
        var length = reason?.Trim().Length ?? 0;
        // No "@": the audit CHECK refuses it (no e-mail in details), and the API must reject before the INSERT so the CHECK never fires.
        return length is >= ReasonMin and <= ReasonMax && !reason!.Any(c => char.IsControl(c) || c == '@');
    }

    /// <summary>Integer digits allowed in an override: far above any gram price, and well inside <c>numeric(20,6)</c> (14 integer digits).</summary>
    public const int MaxIntegerDigits = 12;

    /// <summary>ASCII digits only, 1-12 integer digits, at most 6 decimals, strictly positive.</summary>
    public static bool TryParsePrice(string? text, out decimal price)
    {
        price = 0;
        if (string.IsNullOrEmpty(text) || text.Length > 20)
        {
            return false;
        }

        var dot = text.IndexOf('.', StringComparison.Ordinal);
        var integer = dot < 0 ? text : text[..dot];
        var fraction = dot < 0 ? string.Empty : text[(dot + 1)..];
        if (integer.Length is < 1 or > MaxIntegerDigits
            || !integer.All(char.IsAsciiDigit)
            || (dot >= 0 && fraction.Length is < 1 or > MaxDecimals)
            || !fraction.All(char.IsAsciiDigit))
        {
            return false;
        }

        return decimal.TryParse(text, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out price) && price > 0;
    }
}
