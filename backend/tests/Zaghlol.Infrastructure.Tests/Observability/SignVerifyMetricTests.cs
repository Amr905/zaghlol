using System.Collections.Concurrent;
using System.Diagnostics.Metrics;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Observability;

/// <summary>
/// T-123 code review nit 9 (owner T-138): a signature that fails verify-before-return (a wrong key reference, a config fault)
/// has its own metric tag, so the alert can tell it from a transient outage.
/// </summary>
[Collection(Zaghlol.Infrastructure.Tests.Kms.SignerMetricsCollection.Name)]
public sealed class SignVerifyMetricTests
{
    private static readonly byte[] Body = "{\"x\":1}"u8.ToArray();

    [Fact]
    public async Task AWrongKeyIsCountedAsSignVerifyNotAsAnOutage()
    {
        var operations = await OperationsAfterFailureAsync(FakeKmsFault.WrongKey);

        Assert.Contains(KmsMetrics.SignVerifyOperation, operations);
        Assert.DoesNotContain("sign", operations);
    }

    [Fact]
    public async Task AnUnreachableKmsIsStillCountedAsSign()
    {
        var operations = await OperationsAfterFailureAsync(FakeKmsFault.Throw);

        Assert.Contains("sign", operations);
        Assert.DoesNotContain(KmsMetrics.SignVerifyOperation, operations);
    }

    [Fact]
    public void TheTagValueIsStable()
    {
        // Alert rules match this literal (deploy/observability/alerts/purchases.yaml).
        Assert.Equal("sign_verify", KmsMetrics.SignVerifyOperation);
    }

    private static async Task<IReadOnlyCollection<string>> OperationsAfterFailureAsync(FakeKmsFault fault)
    {
        using var kms = FakeKms.CreateDefault();
        await using var services = kms.BuildServices(configure: s => s.AddSingleton(new KmsCallPolicy { Timeout = TimeSpan.FromMilliseconds(200) }));
        var signer = services.GetRequiredService<ISigner>();
        var operations = new ConcurrentQueue<string>();
        using var listener = new MeterListener();
        listener.InstrumentPublished = (instrument, l) =>
        {
            if (instrument.Meter.Name == KmsMetrics.MeterName && instrument.Name == "zaghlol.kms.unavailable")
            {
                l.EnableMeasurementEvents(instrument);
            }
        };
        listener.SetMeasurementEventCallback<long>((_, _, tags, _) =>
        {
            foreach (var tag in tags)
            {
                if (tag.Key == "operation" && tag.Value is string operation)
                {
                    operations.Enqueue(operation);
                }
            }
        });
        listener.Start();
        kms.Fault = fault;

        await Assert.ThrowsAsync<KmsUnavailableException>(async () => await signer.SignAsync(SigningPurpose.Sync, Body, CancellationToken.None));

        return operations.ToArray();
    }
}
