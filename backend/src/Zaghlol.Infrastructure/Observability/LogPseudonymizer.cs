using System.Security.Cryptography;
using System.Text;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Infrastructure.Observability;

/// <summary>Supplies the log key for a month (<c>yyyy-MM</c>). It is derived in memory, never stored and never logged.</summary>
public interface ILogKeySource
{
    ValueTask<byte[]> GetKeyAsync(string month, CancellationToken cancellationToken);
}

/// <summary>
/// <c>installHash</c> for logs: the first 8 bytes (hex) of HMAC-SHA256 of the install ID under a log key that changes every
/// month, so a log line can't be joined to <c>merchant_contributions.install_hash</c> or to another month's lines
/// (error-handling-and-observability.md section 3.2). The install auth handler (T-124) calls it once per request and puts the
/// result in <c>HttpContext.Items[RequestLogItems.InstallHash]</c>. It takes only an <see cref="InstallId"/> (a validated UUID
/// v4), never free-form text (T-124 F6).
/// </summary>
public interface ILogPseudonymizer
{
    ValueTask<string> InstallHashAsync(InstallId installId, CancellationToken cancellationToken);
}

/// <summary>
/// The log key is <c>HMAC(InstallHashPepper, "zaghlol-log-v1" ‖ 0x00 ‖ yyyy-MM)</c> through the KMS (T-123): one KMS call a
/// month per process, none per log line.
/// </summary>
public sealed class KmsLogKeySource(IKeyedHasher hasher) : ILogKeySource
{
    public const string Label = "zaghlol-log-v1";

    public ValueTask<byte[]> GetKeyAsync(string month, CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(month);
        return hasher.HmacSha256Async(KeyedHashKey.InstallHashPepper, Encoding.UTF8.GetBytes(Label + "\0" + month), cancellationToken);
    }
}

/// <summary>A random in-memory key per process, for Development and Testing hosts that have no KMS.</summary>
public sealed class EphemeralLogKeySource : ILogKeySource
{
    private readonly byte[] key = RandomNumberGenerator.GetBytes(32);

    public ValueTask<byte[]> GetKeyAsync(string month, CancellationToken cancellationToken) => ValueTask.FromResult(key);
}

public sealed class LogPseudonymizer(ILogKeySource keys, TimeProvider clock) : ILogPseudonymizer
{
    private sealed record MonthKey(string Month, byte[] Key);

    private MonthKey? current;

    public async ValueTask<string> InstallHashAsync(InstallId installId, CancellationToken cancellationToken)
    {
        var month = clock.GetUtcNow().ToString("yyyy-MM", System.Globalization.CultureInfo.InvariantCulture);
        var held = Volatile.Read(ref current);
        if (held is null || !string.Equals(held.Month, month, StringComparison.Ordinal))
        {
            held = new MonthKey(month, await keys.GetKeyAsync(month, cancellationToken));
            Volatile.Write(ref current, held);
        }

        var mac = HMACSHA256.HashData(held.Key, Encoding.UTF8.GetBytes(installId.ToString()));
        return Convert.ToHexStringLower(mac.AsSpan(0, 8));
    }
}
