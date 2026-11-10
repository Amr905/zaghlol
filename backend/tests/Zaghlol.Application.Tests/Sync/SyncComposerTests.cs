using Zaghlol.Application.Flags;
using Zaghlol.Application.Prices;
using Zaghlol.Application.Sync;

namespace Zaghlol.Application.Tests.Sync;

/// <summary>The pure block rules of the sync (T-128 design note §1, §2).</summary>
public class SyncComposerTests
{
    private static readonly DateTimeOffset T0 = new(2026, 11, 10, 9, 0, 0, TimeSpan.Zero);

    [Theory]
    [InlineData(0, 0, CatalogModes.None)] // nothing published
    [InlineData(5, 0, CatalogModes.None)] // nothing published, whatever the client says
    [InlineData(41, 41, CatalogModes.None)] // up to date
    [InlineData(0, 41, CatalogModes.Full)] // first sync
    [InlineData(40, 41, CatalogModes.Delta)] // behind 1
    [InlineData(21, 41, CatalogModes.Delta)] // behind 20
    [InlineData(20, 41, CatalogModes.Full)] // behind 21
    [InlineData(42, 41, CatalogModes.Full)] // ahead of this server
    public void CatalogModeFollowsTheTable(int client, int latest, string mode)
    {
        Assert.Equal(mode, SyncComposer.CatalogMode(client, latest));
    }

    [Fact]
    public void ADeltaOverTheOpCapBecomesFull()
    {
        Assert.False(SyncComposer.DeltaTooLarge(2000, 2000));
        Assert.True(SyncComposer.DeltaTooLarge(2001, 2000));
    }

    [Fact]
    public void FlagsAreSentOnAVersionChangeOrAnAppVersionChangeOnly()
    {
        var snapshot = new FlagSnapshot(8, new Dictionary<string, bool>());

        Assert.False(SyncComposer.SendFlags(snapshot, 8, "1.0.0", "1.0.0"));
        Assert.True(SyncComposer.SendFlags(snapshot, 7, "1.0.0", "1.0.0"));
        Assert.True(SyncComposer.SendFlags(snapshot, 8, "1.1.0", "1.0.0"));
    }

    [Fact]
    public void PricesAreSentIffThereIsABlockAndItsAsOfDiffersAtWholeSeconds()
    {
        var block = new PricesBlock(T0.AddTicks(1234), false, [], "USD", []);

        Assert.False(SyncComposer.SendPrices(null, null));
        Assert.False(SyncComposer.SendPrices(null, T0));
        Assert.True(SyncComposer.SendPrices(block, null));
        Assert.False(SyncComposer.SendPrices(block, T0));
        Assert.True(SyncComposer.SendPrices(block, T0.AddSeconds(-1)));
    }

    [Fact]
    public void TheThrottleUsesTheServerClockAndTheWindow()
    {
        var window = TimeSpan.FromHours(24);

        Assert.True(SyncComposer.ThrottleAllows(null, T0, window));
        Assert.False(SyncComposer.ThrottleAllows(T0, T0.AddHours(23).AddMinutes(59), window));
        Assert.True(SyncComposer.ThrottleAllows(T0, T0.AddHours(24), window));
    }

    [Fact]
    public void WholeSecondTruncatesToUtc()
    {
        var local = new DateTimeOffset(2026, 11, 10, 11, 0, 0, 999, TimeSpan.FromHours(2));

        Assert.Equal(T0, SyncComposer.WholeSecond(local));
        Assert.Equal(TimeSpan.Zero, SyncComposer.WholeSecond(local).Offset);
    }
}
