using System.Text.Json;
using Zaghlol.Ops.Cli;

namespace Zaghlol.Ops.Commands;

/// <summary>
/// Support lookup and the interim support writes (T-186, D-57). <c>move</c>, <c>detach</c> and <c>unfreeze</c> read the store
/// order ID only from the no-echo prompt: they have no option and no environment variable for it, and it is never printed.
/// </summary>
internal static class SupportCommands
{
    public static readonly IReadOnlyList<string> MoveReasons = ["lost_or_broken_phone", "reinstall", "buying_phone_gone", "correction", "other"];

    public static IReadOnlyList<CommandSpec> Specs { get; } =
    [
        new("support lookup", "Entitlement and seat status for one install ID or one account e-mail (adminLookupEntitlement, role support_viewer). --email asks for the address at a prompt, so it is not left in shell history.",
            "support lookup (--install UUID | --email)", [new("install"), new("email", IsFlag: true)], 0, 0, LookupAsync, "adminLookupEntitlement"),
        new("support move", "Move a purchase's Gold seat past the cooldown, optionally linking it to an account (adminMoveSeat, role support_agent). Asks for the order ID with no echo.",
            "support move --purchase UUID --to INSTALL_UUID --reason CODE --ticket REF [--attach] [--corrects AUDIT_ID]",
            [new("purchase"), new("to"), new("reason"), new("ticket"), new("attach", IsFlag: true), new("corrects")], 0, 0, MoveAsync, "adminMoveSeat"),
        new("support detach", "Reverse a support link of a purchase to an account (adminDetachPurchase, role support_agent). Asks for the order ID with no echo.",
            "support detach --purchase UUID --ticket REF --corrects AUDIT_ID", [new("purchase"), new("ticket"), new("corrects")], 0, 0, DetachAsync, "adminDetachPurchase"),
        new("support unfreeze", "End a purchase's dispute freeze early (adminUnfreezePurchase, role support_lead). Asks for the order ID with no echo.",
            "support unfreeze --purchase UUID --ticket REF", [new("purchase"), new("ticket")], 0, 0, UnfreezeAsync, "adminUnfreezePurchase"),
    ];

    private static async Task<int> LookupAsync(CommandContext ctx)
    {
        var install = ctx.Args.Get("install");
        var byEmail = ctx.Args.Has("email");
        if ((install is null) == !byEmail)
        {
            return ctx.Usage("Give exactly one of --install and --email.");
        }

        if (install is not null && !Validate.Uuid(install, out _))
        {
            return ctx.Usage("--install must be an install ID (a UUID).");
        }

        string? email = null;
        if (byEmail)
        {
            // FU-264 F4: the address is typed at a prompt (after sign-in, like the order ID), never taken from the command line.
            var prompt = ctx.Environment.Prompt;
            if (!prompt.IsInteractive)
            {
                return ctx.Usage("--email asks for the address at the terminal. Run this command in an interactive terminal, or use --install.");
            }

            if (await ctx.SignInAsync().ConfigureAwait(false) is { } failed)
            {
                return failed;
            }

            var input = prompt.ReadEmail();
            if (input.Status == PromptStatus.Cancelled)
            {
                return ctx.Usage("Cancelled; nothing was sent.");
            }

            if (input.Status != PromptStatus.Ok || !Validate.Match(Validate.Email(), input.Value))
            {
                return ctx.Usage("That is not an e-mail address; nothing was sent.");
            }

            email = input.Value;
        }

        return await ctx.CallAsync(HttpMethod.Post, "/admin/v1/support/entitlement:lookup", (w, _) =>
        {
            w.WriteStartObject();
            if (install is not null)
            {
                w.WriteString("installId", install);
            }
            else
            {
                w.WriteString("email", email);
            }

            w.WriteEndObject();
        }).ConfigureAwait(false);
    }

    private static async Task<int> MoveAsync(CommandContext ctx)
    {
        var purchase = ctx.Args.Get("purchase");
        var to = ctx.Args.Get("to");
        var reason = ctx.Args.Get("reason");
        var ticket = ctx.Args.Get("ticket");
        var attach = ctx.Args.Has("attach");
        var corrects = 0L;
        var hasCorrects = ctx.Args.Has("corrects");
        if (!Validate.Uuid(purchase, out _) || !Validate.Uuid(to, out _) || reason is null || !MoveReasons.Contains(reason, StringComparer.Ordinal)
            || !Validate.Match(Validate.TicketRef(), ticket) || (hasCorrects && !Validate.Long(ctx.Args.Get("corrects"), out corrects)))
        {
            return ctx.Usage("--purchase and --to (UUIDs), --reason (" + string.Join(", ", MoveReasons) + ") and --ticket (the ticket number) are required; --corrects is an audit ID.");
        }

        var isCorrection = reason == "correction";
        if (isCorrection != hasCorrects)
        {
            return ctx.Usage("--corrects (the audit ID of the move being reversed) goes with --reason correction, and only with it.");
        }

        if (isCorrection && attach)
        {
            return ctx.Usage("A correction cannot link an account (--attach).");
        }

        return await WithOrderIdAsync(ctx, "/admin/v1/support/seat:move", (w, secret) =>
        {
            w.WriteStartObject();
            w.WriteString("purchaseId", purchase);
            w.WriteString("toInstallId", to);
            w.WriteString("reasonCode", reason);
            w.WriteString("ticketRef", ticket);
            w.WriteString("ownershipCheck", secret);
            if (attach)
            {
                w.WriteBoolean("attachToAccount", true);
            }

            if (isCorrection)
            {
                w.WriteNumber("correctsAuditId", corrects);
            }

            w.WriteEndObject();
        }).ConfigureAwait(false);
    }

    private static async Task<int> DetachAsync(CommandContext ctx)
    {
        var purchase = ctx.Args.Get("purchase");
        var ticket = ctx.Args.Get("ticket");
        if (!Validate.Uuid(purchase, out _) || !Validate.Match(Validate.TicketRef(), ticket) || !Validate.Long(ctx.Args.Get("corrects"), out var corrects))
        {
            return ctx.Usage("--purchase (a UUID), --ticket (the ticket number) and --corrects (the audit ID of the support link) are required.");
        }

        return await WithOrderIdAsync(ctx, "/admin/v1/support/purchase:detach", (w, secret) =>
        {
            w.WriteStartObject();
            w.WriteString("purchaseId", purchase);
            w.WriteString("reasonCode", "correction");
            w.WriteString("ticketRef", ticket);
            w.WriteString("ownershipCheck", secret);
            w.WriteNumber("correctsAuditId", corrects);
            w.WriteEndObject();
        }).ConfigureAwait(false);
    }

    private static async Task<int> UnfreezeAsync(CommandContext ctx)
    {
        var purchase = ctx.Args.Get("purchase");
        var ticket = ctx.Args.Get("ticket");
        if (!Validate.Uuid(purchase, out _) || !Validate.Match(Validate.TicketRef(), ticket))
        {
            return ctx.Usage("--purchase (a UUID) and --ticket (the ticket number) are required.");
        }

        return await WithOrderIdAsync(ctx, "/admin/v1/support/purchase:unfreeze", (w, secret) =>
        {
            w.WriteStartObject();
            w.WriteString("purchaseId", purchase);
            w.WriteString("ticketRef", ticket);
            w.WriteString("ownershipCheck", secret);
            w.WriteEndObject();
        }).ConfigureAwait(false);
    }

    /// <summary>
    /// Signs in first (the browser step can take a minute and a security-key touch), then asks for the order ID, sends it in the one
    /// request body and clears it. A refusal of the prompt happens before anything is sent.
    /// </summary>
    private static async Task<int> WithOrderIdAsync(CommandContext ctx, string path, BodyWriter body)
    {
        var prompt = ctx.Environment.Prompt;
        if (!prompt.IsInteractive)
        {
            return ctx.Usage("The order ID is read from the terminal with no echo. Run this command in an interactive terminal; do not pipe or redirect its input.");
        }

        if (await ctx.SignInAsync().ConfigureAwait(false) is { } failed)
        {
            return failed;
        }

        var input = prompt.ReadOrderId();
        switch (input.Status)
        {
            case PromptStatus.Ok:
                break;
            case PromptStatus.Cancelled:
                return ctx.Usage("Cancelled; nothing was sent.");
            case PromptStatus.BadFormat:
                return ctx.Usage("That is not an order ID (6 to 64 letters, digits, dots or dashes); nothing was sent.");
            default:
                return ctx.Usage("The order ID could not be read from the terminal; nothing was sent.");
        }

        var order = input.Value!;
        ctx.Printer.Protect(order);
        try
        {
            return await ctx.CallAsync(HttpMethod.Post, path, body, order).ConfigureAwait(false);
        }
        finally
        {
            Array.Clear(order);
            ctx.Printer.Unprotect();
        }
    }
}
