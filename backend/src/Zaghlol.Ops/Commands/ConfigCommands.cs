using Zaghlol.Ops.Cli;

namespace Zaghlol.Ops.Commands;

/// <summary>Remote config of the closed key set (role <c>flags_admin</c>; ask-llm.md section 4.5).</summary>
internal static class ConfigCommands
{
    private const string BadKey = "The config key must be lower-case letters, digits, underscores and dots, starting with a letter.";

    public static IReadOnlyList<CommandSpec> Specs { get; } =
    [
        new("config list", "List every config key with its effective value (adminListConfig).", "config list", [], 0, 0, ListAsync, "adminListConfig"),
        new("config get", "Show one config key (adminGetConfig).", "config get <key>", [], 1, 1, GetAsync, "adminGetConfig"),
        new("config set", "Change one config key; the value is checked against the key's type and range by the server (adminPutConfig).",
            "config set <key> --value <text>", [new("value")], 1, 1, SetAsync, "adminPutConfig"),
    ];

    private static async Task<int> ListAsync(CommandContext ctx) =>
        await ctx.CallAsync(HttpMethod.Get, "/admin/v1/config").ConfigureAwait(false);

    private static async Task<int> GetAsync(CommandContext ctx)
    {
        var key = ctx.Args.Positionals[0];
        return IsKey(key)
            ? await ctx.CallAsync(HttpMethod.Get, "/admin/v1/config/" + key).ConfigureAwait(false)
            : ctx.Usage(BadKey);
    }

    private static async Task<int> SetAsync(CommandContext ctx)
    {
        var key = ctx.Args.Positionals[0];
        if (!IsKey(key))
        {
            return ctx.Usage(BadKey);
        }

        if (ctx.Args.Get("value") is not { Length: > 0 and <= 64 } value)
        {
            return ctx.Usage("--value is required (1 to 64 characters).");
        }

        return await ctx.CallAsync(HttpMethod.Put, "/admin/v1/config/" + key, (w, _) =>
        {
            w.WriteStartObject();
            w.WriteString("value", value);
            w.WriteEndObject();
        }).ConfigureAwait(false);
    }

    private static bool IsKey(string key) =>
        key.Length is >= 2 and <= 64 && key[0] is >= 'a' and <= 'z' && key.All(c => c is (>= 'a' and <= 'z') or (>= '0' and <= '9') or '_' or '.');
}
