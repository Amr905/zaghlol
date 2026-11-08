using System.Diagnostics;
using System.Diagnostics.Metrics;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>
/// Counters for the signing path (alerts in T-138). Tags carry fixed operation names only, never key references,
/// kids of unknown origin, data or nonces.
/// </summary>
public static class KmsMetrics
{
    public const string MeterName = "Zaghlol.Kms";

    private static readonly Meter Meter = new(MeterName);

    private static readonly Counter<long> Unavailable =
        Meter.CreateCounter<long>("zaghlol.kms.unavailable", description: "KMS calls that failed after the retry.");

    private static readonly Counter<long> TooLarge =
        Meter.CreateCounter<long>("zaghlol.signing.response_too_large", description: "Signed responses over the 1 MiB buffer cap.");

    private static readonly Counter<long> NonceMismatch =
        Meter.CreateCounter<long>("zaghlol.time_nonce.echo_mismatch", description: "Anchored responses whose timeNonce differed from the request.");

    /// <summary><paramref name="operation"/> is one of <c>sign</c>, <c>hmac</c>, <c>data_key</c>, <c>public_key</c>.</summary>
    public static void KmsUnavailable(string operation) =>
        Unavailable.Add(1, new TagList { { "operation", operation } });

    public static void ResponseTooLargeToSign() => TooLarge.Add(1);

    public static void TimeNonceEchoMismatch() => NonceMismatch.Add(1);
}
