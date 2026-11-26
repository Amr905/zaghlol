using Zaghlol.Domain;

namespace Zaghlol.Application.Llm.Spend;

/// <summary>USD per million tokens, as configured per provider (ask-llm.md section 3). All <see cref="decimal"/>.</summary>
public sealed record LlmPrices(decimal InPerMTok, decimal CachedPerMTok, decimal OutPerMTok);

/// <summary>The model id and prices the ledger uses for one provider id.</summary>
public sealed record LlmPriceEntry(string Model, LlmPrices Prices);

/// <summary>Where the guard finds the configured model and prices of a provider. An unknown provider id fails closed (paused).</summary>
public interface ILlmPriceList
{
    bool TryGet(string providerId, out LlmPriceEntry entry);
}

/// <summary>Cost math in <see cref="decimal"/>; cached input tokens are priced separately from the rest of the input.</summary>
public static class LlmCostCalculator
{
    public const decimal TokensPerPriceUnit = 1_000_000m;

    /// <summary>The ledger column scale (<c>numeric(14,6)</c>).</summary>
    public const int Scale = 6;

    /// <summary>
    /// <c>((input - cached) * in + cached * cachedPrice + output * out) / 1e6</c>, rounded <b>up</b> to a micro-dollar so the ledger
    /// can never under-count. <c>cached</c> is clamped to <c>[0, input]</c>; negative counts are treated as 0.
    /// </summary>
    public static decimal Cost(LlmUsage usage, LlmPrices prices)
    {
        ArgumentNullException.ThrowIfNull(usage);
        ArgumentNullException.ThrowIfNull(prices);

        var input = Math.Max(0, usage.InputTokens);
        var cached = Math.Clamp(usage.CachedTokens, 0, input);
        var output = Math.Max(0, usage.OutputTokens);
        var raw = (((input - cached) * prices.InPerMTok) + (cached * prices.CachedPerMTok) + (output * prices.OutPerMTok)) / TokensPerPriceUnit;
        return RoundUp(raw);
    }

    /// <summary>The most one call can cost: every input token at the dearer of the two input prices, every output token used.</summary>
    public static decimal WorstCase(LlmPrices prices, int maxInputTokens, int maxOutputTokens)
    {
        ArgumentNullException.ThrowIfNull(prices);
        var raw = ((Math.Max(0, maxInputTokens) * Math.Max(prices.InPerMTok, prices.CachedPerMTok)) + (Math.Max(0, maxOutputTokens) * prices.OutPerMTok)) / TokensPerPriceUnit;
        return RoundUp(raw);
    }

    private static decimal RoundUp(decimal value)
    {
        var factor = 1_000_000m;
        return Math.Ceiling(value * factor) / factor;
    }
}
