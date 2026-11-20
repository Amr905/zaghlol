using Zaghlol.Ops.Cli;

namespace Zaghlol.Ops.Commands;

/// <summary>Price override (role <c>prices_admin</c>). The price is a decimal string end to end, never a number type.</summary>
internal static class PriceCommands
{
    public static IReadOnlyList<CommandSpec> Specs { get; } =
    [
        new("prices override", "Override a price when the feed is wrong (adminOverridePrice).",
            "prices override --symbol XAU21_G --currency EGP --price 4217.50 --reason TEXT [--expires-at 2026-11-20T10:00:00Z]",
            [new("symbol"), new("currency"), new("price"), new("reason"), new("expires-at")], 0, 0, OverrideAsync, "adminOverridePrice"),
    ];

    private static async Task<int> OverrideAsync(CommandContext ctx)
    {
        var symbol = ctx.Args.Get("symbol");
        var currency = ctx.Args.Get("currency");
        var price = ctx.Args.Get("price");
        var reason = ctx.Args.Get("reason");
        var expires = ctx.Args.Get("expires-at");
        if (!Validate.Match(Validate.PriceSymbol(), symbol) || !Validate.Match(Validate.Currency(), currency)
            || !Validate.Match(Validate.Decimal(), price) || reason is null || reason.Length is < 3 or > 200 || reason.Any(char.IsControl)
            || (expires is not null && !Validate.Match(Validate.UtcTimestamp(), expires)))
        {
            return ctx.Usage("--symbol (A-Z, 0-9, _), --currency (ISO code), --price (a decimal like 4217.50) and --reason (3-200 characters) are required; --expires-at is a UTC time ending in Z.");
        }

        return await ctx.CallAsync(HttpMethod.Put, "/admin/v1/prices/override", (w, _) =>
        {
            w.WriteStartObject();
            w.WriteString("symbol", symbol);
            w.WriteString("currency", currency);
            w.WriteString("price", price);
            w.WriteString("reason", reason);
            if (expires is not null)
            {
                w.WriteString("expiresAt", expires);
            }

            w.WriteEndObject();
        }).ConfigureAwait(false);
    }
}
