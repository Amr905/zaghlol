using Zaghlol.Ops.Cli;

namespace Zaghlol.Ops.Commands;

/// <summary>Read-only reports.</summary>
internal static class ReportCommands
{
    public static IReadOnlyList<CommandSpec> Specs { get; } =
    [
        new("bank-requests list", "Ranked list of 'request my bank' submissions (adminListBankRequests, role catalog_editor).", "bank-requests list", [], 0, 0,
            ctx => ctx.CallAsync(HttpMethod.Get, "/admin/v1/bank-requests"), "adminListBankRequests"),
        new("metrics daily-active", "Daily active install counters (adminDailyActive, any operator role).", "metrics daily-active [--days 1-90]", [new("days")], 0, 0, DailyActiveAsync, "adminDailyActive"),
    ];

    private static async Task<int> DailyActiveAsync(CommandContext ctx)
    {
        var days = 14;
        if (ctx.Args.Get("days") is { } raw && !Validate.PositiveInt(raw, 90, out days))
        {
            return ctx.Usage("--days must be a whole number from 1 to 90.");
        }

        return await ctx.CallAsync(HttpMethod.Get, "/admin/v1/metrics/daily-active?days=" + days.ToString(System.Globalization.CultureInfo.InvariantCulture)).ConfigureAwait(false);
    }
}
