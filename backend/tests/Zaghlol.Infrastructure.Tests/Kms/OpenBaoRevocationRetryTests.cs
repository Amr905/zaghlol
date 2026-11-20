using System.Runtime.Versioning;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Application.Accounts;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Accounts;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Kms;

/// <summary>
/// T-201 review S1 through the T-135 retry job: an Apple revocation sealed under the T-200 File key must never be dropped just
/// because the switch to OpenBao forgot <c>Kms:Envelope:PreviousKeyRefs:0=file:envelope</c>. The job stops on
/// <see cref="KmsUnavailableException"/> and the row stays; with the reference configured it opens and is revoked.
/// </summary>
[SupportedOSPlatform("linux")]
public sealed class OpenBaoRevocationRetryTests : IAsyncLifetime
{
    private OpenBaoTestBed bed = null!;
    private byte[] sealedBlob = [];

    public async Task InitializeAsync()
    {
        bed = await OpenBaoTestBed.CreateAsync();
        await using var file = FileKmsHost.Services("Production", bed.FileKeys.Settings());
        await FileKmsHost.StartAsync(file);
        var vault = new AppleTokenVault(file.GetRequiredService<IEnvelopeCipher>());
        sealedBlob = await vault.SealAsync(PendingAppleRevocationPolicy.VaultSubject, new AppleRefreshToken("app.zaghlol.signin", new Sensitive<string>("rt-sentinel-41")), CancellationToken.None);
    }

    public async Task DisposeAsync() => await bed.DisposeAsync();

    [LinuxFact]
    public async Task AForgottenPreviousKeyRefKeepsThePendingRevocation()
    {
        var settings = bed.Settings(worker: true);
        Assert.NotNull(settings.Remove("Kms:Envelope:PreviousKeyRefs:0") ? "removed" : null);
        await using var worker = OpenBaoHost.Services("Production", settings);
        await FileKmsHost.StartAsync(worker);
        var (job, store, apple) = Job(worker);

        await Assert.ThrowsAsync<KmsUnavailableException>(() => job.RunOnceAsync(CancellationToken.None));

        Assert.Empty(store.Deleted);
        Assert.Equal(0, apple.Revokes);
    }

    [LinuxFact]
    public async Task WithThePreviousKeyRefTheRevocationIsRetriedAndDone()
    {
        await using var worker = OpenBaoHost.Services("Production", bed.Settings(worker: true));
        await FileKmsHost.StartAsync(worker);
        var (job, store, apple) = Job(worker);

        var run = await job.RunOnceAsync(CancellationToken.None);

        Assert.Equal(1, run.Revoked);
        Assert.Equal(1, apple.Revokes);
        Assert.Single(store.Deleted);
    }

    private (AppleRevocationRetryJob Job, Store Store, Apple Apple) Job(IServiceProvider services)
    {
        var store = new Store(new PendingAppleRevocation(Guid.NewGuid(), sealedBlob, 0));
        var apple = new Apple();
        var job = new AppleRevocationRetryJob(store, new AppleTokenVault(services.GetRequiredService<IEnvelopeCipher>()), apple, TimeProvider.System);
        return (job, store, apple);
    }

    private sealed class Store(PendingAppleRevocation row) : IPendingAppleRevocationStore
    {
        public List<Guid> Deleted { get; } = [];

        public Task<int> DeleteExpiredAsync(DateTimeOffset now, CancellationToken cancellationToken) => Task.FromResult(0);

        public Task<IReadOnlyList<PendingAppleRevocation>> ListDueAsync(DateTimeOffset now, int limit, CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<PendingAppleRevocation>>([row]);

        public Task DeleteAsync(Guid id, CancellationToken cancellationToken)
        {
            Deleted.Add(id);
            return Task.CompletedTask;
        }

        public Task DeferAsync(Guid id, int attempts, DateTimeOffset nextAttemptAt, CancellationToken cancellationToken) => Task.CompletedTask;
    }

    private sealed class Apple : IAppleAccountClient
    {
        public int Revokes { get; private set; }

        public Task<AppleRefreshToken?> ExchangeCodeAsync(Sensitive<string> code, string clientId, string expectedSubject, CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task<AppleRevokeOutcome> RevokeAsync(AppleRefreshToken token, CancellationToken cancellationToken)
        {
            Assert.Equal("rt-sentinel-41", token.Token.Reveal());
            Revokes++;
            return Task.FromResult(AppleRevokeOutcome.Revoked);
        }
    }
}
