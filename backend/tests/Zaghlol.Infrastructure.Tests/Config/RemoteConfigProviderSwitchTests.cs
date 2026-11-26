using Microsoft.Extensions.Configuration;
using Zaghlol.Application.Config;
using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Llm;

namespace Zaghlol.Infrastructure.Tests.Config;

/// <summary>T-334: <c>llm.provider</c> in remote config picks the active provider on the next request, with no restart and no cache.</summary>
public class RemoteConfigProviderSwitchTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 26, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task ChangingLlmProviderSwitchesTheActiveProviderOnTheNextCall()
    {
        var reader = new Rows();
        var a = new FakeLlmProvider("prov-a", []);
        var b = new FakeLlmProvider("prov-b", []);
        var fallback = new ConfiguredActiveLlmProviderId(new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?> { ["Llm:ActiveProvider"] = "prov-a" }).Build());
        var registry = new LlmProviderRegistry([a, b], new RemoteConfigActiveLlmProviderId(new RemoteConfigService(reader), fallback));

        // Never set: the configured fallback applies.
        Assert.Same(a, await registry.ActiveAsync(default));

        reader.Set(RemoteConfigKeys.LlmProvider, "prov-b");
        Assert.Same(b, await registry.ActiveAsync(default));
        Assert.Equal("prov-b", await registry.ActiveIdAsync(default));

        reader.Set(RemoteConfigKeys.LlmProvider, "prov-a");
        Assert.Same(a, await registry.ActiveAsync(default));
    }

    [Fact]
    public async Task AnUnregisteredProviderIdFailsClosed()
    {
        var reader = new Rows();
        reader.Set(RemoteConfigKeys.LlmProvider, "not-registered");
        var fallback = new ConfiguredActiveLlmProviderId(new ConfigurationBuilder().Build());
        var registry = new LlmProviderRegistry([new FakeLlmProvider("prov-a", [])], new RemoteConfigActiveLlmProviderId(new RemoteConfigService(reader), fallback));

        await Assert.ThrowsAsync<LlmConfigurationException>(async () => await registry.ActiveAsync(default));
    }

    private sealed class Rows : IRemoteConfigReader
    {
        private readonly Dictionary<string, RemoteConfigRow> rows = [];

        public void Set(string key, string value) =>
            rows[key] = new RemoteConfigRow(key, value, (rows.TryGetValue(key, out var old) ? old.Version : 0) + 1, Now);

        public Task<IReadOnlyList<RemoteConfigRow>> ListAsync(CancellationToken cancellationToken) =>
            Task.FromResult<IReadOnlyList<RemoteConfigRow>>(rows.Values.ToList());
    }
}
