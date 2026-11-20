using Zaghlol.Ops.Cli;

namespace Zaghlol.Ops.Commands;

/// <summary>Merchant contribution review (role <c>catalog_editor</c>); aggregates only, the server never lists installs.</summary>
internal static class ContributionCommands
{
    public static IReadOnlyList<CommandSpec> Specs { get; } =
    [
        new("contributions list", "List the review queue (adminListContributions).", "contributions list [--status ready_for_review|promoted|rejected]",
            [new("status")], 0, 0, ListAsync, "adminListContributions"),
        new("contributions promote", "Promote a contribution into the draft catalog (adminPromoteContribution).",
            "contributions promote --merchant-norm TEXT --institution CODE [--merchant-id N] [--category CODE]",
            [new("merchant-norm"), new("institution"), new("merchant-id"), new("category")], 0, 0, PromoteAsync, "adminPromoteContribution"),
        new("contributions reject", "Reject a contribution (adminRejectContribution).", "contributions reject --merchant-norm TEXT --institution CODE",
            [new("merchant-norm"), new("institution")], 0, 0, RejectAsync, "adminRejectContribution"),
    ];

    private static async Task<int> ListAsync(CommandContext ctx)
    {
        var status = ctx.Args.Get("status");
        if (status is not (null or "ready_for_review" or "promoted" or "rejected"))
        {
            return ctx.Usage("--status must be ready_for_review, promoted or rejected.");
        }

        return await ctx.CallAsync(HttpMethod.Get, "/admin/v1/contributions" + (status is null ? string.Empty : "?status=" + status)).ConfigureAwait(false);
    }

    private static async Task<int> PromoteAsync(CommandContext ctx)
    {
        var norm = ctx.Args.Get("merchant-norm");
        var institution = ctx.Args.Get("institution");
        var category = ctx.Args.Get("category");
        var merchantId = 0;
        if (norm is not { Length: >= 2 and <= 80 } || norm.Any(char.IsControl) || !Validate.Match(Validate.InstitutionCode(), institution)
            || (category is not null && !Validate.Match(Validate.CategoryCode(), category))
            || (ctx.Args.Get("merchant-id") is { } rawId && !Validate.PositiveInt(rawId, int.MaxValue, out merchantId)))
        {
            return ctx.Usage("--merchant-norm (2-80 characters) and --institution (an institution code) are required; --merchant-id is a whole number and --category a category code.");
        }

        return await ctx.CallAsync(HttpMethod.Post, "/admin/v1/contributions:promote", (w, _) =>
        {
            w.WriteStartObject();
            w.WriteString("merchantNorm", norm);
            w.WriteString("institutionCode", institution);
            if (merchantId > 0)
            {
                w.WriteNumber("merchantId", merchantId);
            }

            if (category is not null)
            {
                w.WriteString("categoryCode", category);
            }

            w.WriteEndObject();
        }).ConfigureAwait(false);
    }

    private static async Task<int> RejectAsync(CommandContext ctx)
    {
        var norm = ctx.Args.Get("merchant-norm");
        var institution = ctx.Args.Get("institution");
        if (norm is not { Length: >= 2 and <= 80 } || norm.Any(char.IsControl) || !Validate.Match(Validate.InstitutionCode(), institution))
        {
            return ctx.Usage("--merchant-norm (2-80 characters) and --institution (an institution code) are required.");
        }

        return await ctx.CallAsync(HttpMethod.Post, "/admin/v1/contributions:reject", (w, _) =>
        {
            w.WriteStartObject();
            w.WriteString("merchantNorm", norm);
            w.WriteString("institutionCode", institution);
            w.WriteEndObject();
        }).ConfigureAwait(false);
    }
}
