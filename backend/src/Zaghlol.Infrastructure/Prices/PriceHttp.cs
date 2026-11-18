using System.Globalization;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Zaghlol.Application.Prices;

namespace Zaghlol.Infrastructure.Prices;

/// <summary>Shared plumbing of the HTTP adapters: bounded GET and JSON, decimal-only number reads, bounds from configuration.</summary>
internal static class PriceHttp
{
    public const int MaxResponseBytes = 64 * 1024;

    /// <summary>
    /// GETs <paramref name="request"/> and returns the parsed JSON object. Any transport failure becomes a
    /// <see cref="PriceProviderException"/> with a fixed message and no inner exception: a URL can hold the API key (MetalpriceAPI
    /// takes it as a query parameter), so nothing from the transport is allowed to reach a log.
    /// </summary>
    public static async Task<JsonDocument> GetJsonAsync(HttpClient client, HttpRequestMessage request, CancellationToken cancellationToken)
    {
        try
        {
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                throw new PriceProviderException($"The price provider answered HTTP {(int)response.StatusCode}.");
            }

            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
            using var buffer = new MemoryStream();
            var chunk = new byte[4096];
            int read;
            while ((read = await stream.ReadAsync(chunk, cancellationToken).ConfigureAwait(false)) > 0)
            {
                if (buffer.Length + read > MaxResponseBytes)
                {
                    throw new PriceProviderException("The price provider response is too large.");
                }

                buffer.Write(chunk, 0, read);
            }

            buffer.Position = 0;
            return await JsonDocument.ParseAsync(buffer, cancellationToken: cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is HttpRequestException or JsonException or TaskCanceledException && !cancellationToken.IsCancellationRequested)
        {
            throw new PriceProviderException("The price provider request failed.");
        }
    }

    /// <summary>A JSON number as <see cref="decimal"/> (parsed from the text, never through a double); <c>null</c> if absent or not a number.</summary>
    public static decimal? Decimal(JsonElement obj, string name) =>
        obj.ValueKind == JsonValueKind.Object
        && obj.TryGetProperty(name, out var value)
        && value.ValueKind == JsonValueKind.Number
        && value.TryGetDecimal(out var number)
            ? number
            : null;

    public static decimal Require(JsonElement obj, string name) =>
        Decimal(obj, name) is { } value && value > 0 ? value : throw new PriceProviderException("The price provider response lacks a valid price.");

    public static DateTimeOffset UnixSeconds(JsonElement obj, string name, DateTimeOffset fallback) =>
        obj.ValueKind == JsonValueKind.Object
        && obj.TryGetProperty(name, out var value)
        && value.ValueKind == JsonValueKind.Number
        && value.TryGetInt64(out var seconds)
        && seconds is > 946_684_800 and < 4_102_444_800
            ? DateTimeOffset.FromUnixTimeSeconds(seconds)
            : fallback;

    public static string ApiKey(IConfiguration configuration, string key) =>
        configuration[key] is { Length: > 0 } value ? value : throw new InvalidOperationException($"{key} is not set (it comes from the secrets manager).");

    public static PriceBounds Bounds(IConfiguration configuration)
    {
        var section = configuration.GetSection("Prices:Bounds");
        var d = PriceBounds.Default;
        return new PriceBounds(
            Read(section["MinUsdPerOunce"], d.MinUsdPerOunce),
            Read(section["MaxUsdPerOunce"], d.MaxUsdPerOunce),
            Read(section["MinEgpPerUsd"], d.MinEgpPerUsd),
            Read(section["MaxEgpPerUsd"], d.MaxEgpPerUsd));
    }

    private static decimal Read(string? text, decimal fallback) =>
        decimal.TryParse(text, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var value) && value > 0 ? value : fallback;
}
