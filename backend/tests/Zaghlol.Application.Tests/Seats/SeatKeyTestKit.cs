using System.Collections.Concurrent;
using System.Security.Cryptography;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;

namespace Zaghlol.Application.Tests.Seats;

internal static class SeatKeyTestKit
{
    public static readonly InstallId Install = InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77");
    public static readonly InstallId OtherInstall = InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e78");
    public static readonly Guid Purchase = Guid.Parse("5f0c8a7e-2b1d-4e3f-9a6b-7c8d9e0f1a2b");

    public static SeatChallenge Restore(byte fill = 0x11) => SeatChallenge.ForRestore(Enumerable.Repeat(fill, 32).ToArray());

    public static SeatChallenge For(SeatOp op) => op switch
    {
        SeatOp.Verify => SeatChallenge.ForVerify("eyJhbGciOiJFUzI1NiJ9.eyJzeW50aGV0aWMiOnRydWV9.c2ln"),
        SeatOp.Restore => Restore(),
        SeatOp.SignIn => SeatChallenge.ForSignIn("synthetic-nonce-0001"),
        _ => throw new ArgumentOutOfRangeException(nameof(op)),
    };
}

/// <summary>Records every metric call.</summary>
internal sealed class RecordingSeatMetrics : ISeatKeyMetrics
{
    public List<(SeatOp Op, string Result)> Proofs { get; } = [];

    public List<(SeatOp Op, string Status)> ElementZeros { get; } = [];

    public void Proof(SeatOp op, SeatKeyRejection? rejection) => Proofs.Add((op, SeatKeyTags.Result(rejection)));

    public void ElementZero(SeatOp op, ElementZeroStatus status) => ElementZeros.Add((op, SeatKeyTags.Status(status)));
}

/// <summary>An HMAC-SHA256 "KMS" with a fixed key that counts calls, records input lengths and tracks concurrency.</summary>
internal sealed class CountingSeatMac(byte[]? key = null) : ISeatKeyMac
{
    private readonly byte[] key = key ?? [.. Enumerable.Range(0, 32).Select(i => (byte)i)];
    private int inFlight;
    private int calls;

    public ConcurrentBag<byte[]> Inputs { get; } = [];

    public int Calls => Volatile.Read(ref calls);

    public int MaxInFlight { get; private set; }

    public TimeSpan Delay { get; set; }

    public Exception? Fault { get; set; }

    public async ValueTask<byte[]> MacAsync(ReadOnlyMemory<byte> input, CancellationToken cancellationToken)
    {
        Interlocked.Increment(ref calls);
        var now = Interlocked.Increment(ref inFlight);
        lock (Inputs)
        {
            MaxInFlight = Math.Max(MaxInFlight, now);
        }

        try
        {
            if (Delay > TimeSpan.Zero)
            {
                await Task.Delay(Delay, cancellationToken);
            }

            if (Fault is not null)
            {
                throw Fault;
            }

            Inputs.Add(input.ToArray());
            return HMACSHA256.HashData(key, input.Span);
        }
        finally
        {
            Interlocked.Decrement(ref inFlight);
        }
    }
}
