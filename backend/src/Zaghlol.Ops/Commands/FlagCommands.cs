using Zaghlol.Ops.Cli;

namespace Zaghlol.Ops.Commands;

/// <summary>Feature flags (role <c>flags_admin</c>).</summary>
internal static class FlagCommands
{
    public static IReadOnlyList<CommandSpec> Specs { get; } =
    [
        new("flags get", "Show a feature flag (adminGetFlag).", "flags get <key>", [], 1, 1, GetAsync, "adminGetFlag"),
        new("flags set", "Change a feature flag; targeting rules are replaced as a whole when any rule option is given (adminPutFlag).",
            "flags set <key> --value true|false [--platforms android,ios] [--min-app-version 1.4.0] [--rollout-percent 0-100] [--clear-rules]",
            [new("value"), new("platforms"), new("min-app-version"), new("rollout-percent"), new("clear-rules", IsFlag: true)], 1, 1, SetAsync, "adminPutFlag"),
    ];

    private static async Task<int> GetAsync(CommandContext ctx)
    {
        var key = ctx.Args.Positionals[0];
        return Validate.Match(Validate.FlagKey(), key)
            ? await ctx.CallAsync(HttpMethod.Get, "/admin/v1/flags/" + key).ConfigureAwait(false)
            : ctx.Usage("The flag key must be lower-case letters, digits and underscores, starting with a letter.");
    }

    private static async Task<int> SetAsync(CommandContext ctx)
    {
        var key = ctx.Args.Positionals[0];
        if (!Validate.Match(Validate.FlagKey(), key))
        {
            return ctx.Usage("The flag key must be lower-case letters, digits and underscores, starting with a letter.");
        }

        bool value;
        switch (ctx.Args.Get("value"))
        {
            case "true":
                value = true;
                break;
            case "false":
                value = false;
                break;
            default:
                return ctx.Usage("--value must be true or false.");
        }

        string[]? platforms = null;
        if (ctx.Args.Get("platforms") is { } rawPlatforms)
        {
            platforms = rawPlatforms.Split(',');
            if (platforms.Length is 0 or > 2 || platforms.Any(p => p is not ("android" or "ios")) || platforms.Distinct(StringComparer.Ordinal).Count() != platforms.Length)
            {
                return ctx.Usage("--platforms must list android and/or ios once each.");
            }
        }

        var minVersion = ctx.Args.Get("min-app-version");
        if (minVersion is not null && !Validate.Match(Validate.AppVersion(), minVersion))
        {
            return ctx.Usage("--min-app-version must look like 1.4.0.");
        }

        var rollout = -1;
        if (ctx.Args.Get("rollout-percent") is { } rawRollout && !Validate.NonNegativeInt(rawRollout, 100, out rollout))
        {
            return ctx.Usage("--rollout-percent must be a whole number from 0 to 100.");
        }

        var anyRule = platforms is not null || minVersion is not null || rollout >= 0;
        if (anyRule && ctx.Args.Has("clear-rules"))
        {
            return ctx.Usage("--clear-rules cannot be combined with rule options.");
        }

        return await ctx.CallAsync(HttpMethod.Put, "/admin/v1/flags/" + key, (w, _) =>
        {
            w.WriteStartObject();
            w.WriteBoolean("value", value);
            if (anyRule || ctx.Args.Has("clear-rules"))
            {
                w.WriteStartObject("rules");
                if (platforms is not null)
                {
                    w.WriteStartArray("platforms");
                    foreach (var platform in platforms)
                    {
                        w.WriteStringValue(platform);
                    }

                    w.WriteEndArray();
                }

                if (minVersion is not null)
                {
                    w.WriteString("minAppVersion", minVersion);
                }

                if (rollout >= 0)
                {
                    w.WriteNumber("rolloutPercent", rollout);
                }

                w.WriteEndObject();
            }

            w.WriteEndObject();
        }).ConfigureAwait(false);
    }
}
