using System.Text.Json.Nodes;
using Zaghlol.Ops.Auth;
using Zaghlol.Ops.Cli;

namespace Zaghlol.Ops.Commands;

/// <summary>Sign-in and local status. None of them calls an admin operation.</summary>
internal static class SessionCommands
{
    public static IReadOnlyList<CommandSpec> Specs { get; } =
    [
        new("login", "Sign in with the browser (authorization code + PKCE, loopback redirect) and keep the token in the OS credential store or memory.", "login", [], 0, 0, LoginAsync),
        new("logout", "Forget the stored token.", "logout", [], 0, 0, LogoutAsync),
        new("status", "Show the settings in use and whether a valid token is stored. Prints no token.", "status", [], 0, 0, StatusAsync),
    ];

    private static async Task<int> LoginAsync(CommandContext ctx)
    {
        try
        {
            var token = await ctx.Tokens.SignInAsync(openBrowser: !ctx.Args.Has("no-browser"), ctx.CancellationToken).ConfigureAwait(false);
            ctx.Printer.Err("Signed in. The token is valid until " + token.ExpiresAt.ToString("u", System.Globalization.CultureInfo.InvariantCulture) + " (kept in: " + ctx.Tokens.StoreName + ").");
            return ExitCode.Success;
        }
        catch (LoginException e)
        {
            ctx.Printer.Err("error: sign-in failed: " + e.Message);
            return ExitCode.Auth;
        }
    }

    private static async Task<int> LogoutAsync(CommandContext ctx)
    {
        var deleted = await ctx.Tokens.SignOutAsync(ctx.CancellationToken).ConfigureAwait(false);
        if (!deleted)
        {
            ctx.Printer.Err("error: the credential store did not confirm that the token was deleted; remove the 'zaghlol-ops' entry there by hand.");
            return ExitCode.ApiRefused;
        }

        ctx.Printer.Err("Signed out.");
        return ExitCode.Success;
    }

    private static async Task<int> StatusAsync(CommandContext ctx)
    {
        var config = ctx.Config;
        var cached = await ctx.Tokens.CachedAsync(ctx.CancellationToken).ConfigureAwait(false);
        var status = new JsonObject
        {
            ["apiUrl"] = config.ApiUrl.AbsoluteUri,
            ["issuer"] = config.Issuer.AbsoluteUri,
            ["clientId"] = config.ClientId,
            ["tokenUse"] = config.TokenUse == TokenUse.IdToken ? "id_token" : "access_token",
            ["tokenStore"] = ctx.Tokens.StoreName,
            ["signedIn"] = cached is not null,
        };
        if (cached is not null)
        {
            status["subject"] = cached.Subject;
            status["expiresAt"] = cached.ExpiresAt.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", System.Globalization.CultureInfo.InvariantCulture);
        }

        ctx.Printer.Json(status);
        return ExitCode.Success;
    }
}
