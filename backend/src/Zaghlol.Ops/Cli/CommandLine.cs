namespace Zaghlol.Ops.Cli;

/// <summary>An option a command accepts. Flags take no value.</summary>
internal sealed record Opt(string Name, bool IsFlag = false);

/// <summary>One command: its words, the options and positionals it accepts, and what it does.</summary>
internal sealed record CommandSpec(
    string Path,
    string Summary,
    string Usage,
    IReadOnlyList<Opt> Options,
    int MinPositionals,
    int MaxPositionals,
    Func<CommandContext, Task<int>> Run,
    string? OperationId = null);

/// <summary>The words after the command path, sorted into options and positionals.</summary>
internal sealed class ParsedArgs
{
    private readonly Dictionary<string, string> options = new(StringComparer.Ordinal);

    public List<string> Positionals { get; } = [];

    public bool Has(string name) => options.ContainsKey(name);

    public string? Get(string name) => options.GetValueOrDefault(name);

    internal void Set(string name, string value) => options[name] = value;
}

internal sealed record ParseOutcome(CommandSpec? Spec, ParsedArgs? Args, string? Error, bool Help);

/// <summary>
/// A strict parser. Only the options in a command's list (plus <c>--config</c>, <c>--no-browser</c>, <c>--help</c>) exist; any
/// other option is a usage error that names at most the option itself, never an argument value, so a mistyped
/// <c>--order-id=...</c> cannot echo what the operator should not have typed.
/// </summary>
internal static class CommandLine
{
    public static readonly IReadOnlyList<Opt> GlobalOptions = [new("config"), new("no-browser", IsFlag: true), new("help", IsFlag: true)];

    public static ParseOutcome Parse(IReadOnlyList<string> args, IReadOnlyList<CommandSpec> specs)
    {
        ArgumentNullException.ThrowIfNull(args);
        ArgumentNullException.ThrowIfNull(specs);

        var words = args.TakeWhile(a => !a.StartsWith('-')).Take(3).ToList();
        CommandSpec? spec = null;
        var consumed = 0;
        for (var take = words.Count; take >= 1 && spec is null; take--)
        {
            var path = string.Join(' ', words.Take(take));
            spec = specs.FirstOrDefault(s => string.Equals(s.Path, path, StringComparison.Ordinal));
            consumed = take;
        }

        if (args.Count == 0 || args[0] is "-h" or "--help")
        {
            return new ParseOutcome(null, null, null, Help: true);
        }

        if (spec is null)
        {
            return new ParseOutcome(null, null, "Unknown command. Run 'zaghlol-ops --help'.", false);
        }

        var allowed = spec.Options.Concat(GlobalOptions).ToDictionary(o => o.Name, StringComparer.Ordinal);
        var parsed = new ParsedArgs();
        for (var i = consumed; i < args.Count; i++)
        {
            var token = args[i];
            if (token == "-h")
            {
                token = "--help";
            }

            if (token.StartsWith("--", StringComparison.Ordinal))
            {
                var eq = token.IndexOf('=', StringComparison.Ordinal);
                var name = eq < 0 ? token[2..] : token[2..eq];
                if (!allowed.TryGetValue(name, out var option))
                {
                    return Fail(spec, UnknownOption(name));
                }

                if (parsed.Has(name))
                {
                    return Fail(spec, $"Option --{name} is given twice.");
                }

                if (option.IsFlag)
                {
                    if (eq >= 0)
                    {
                        return Fail(spec, $"Option --{name} takes no value.");
                    }

                    parsed.Set(name, "true");
                }
                else if (eq >= 0)
                {
                    parsed.Set(name, token[(eq + 1)..]);
                }
                else if (i + 1 < args.Count)
                {
                    parsed.Set(name, args[++i]);
                }
                else
                {
                    return Fail(spec, $"Option --{name} needs a value.");
                }
            }
            else if (token.Length > 1 && token[0] == '-' && !(token.Length > 1 && char.IsDigit(token[1])))
            {
                return Fail(spec, "Unknown option.");
            }
            else
            {
                parsed.Positionals.Add(token);
            }
        }

        if (parsed.Has("help"))
        {
            return new ParseOutcome(spec, parsed, null, Help: true);
        }

        if (parsed.Positionals.Count < spec.MinPositionals || parsed.Positionals.Count > spec.MaxPositionals)
        {
            return Fail(spec, "Wrong number of arguments.");
        }

        return new ParseOutcome(spec, parsed, null, false);
    }

    private static ParseOutcome Fail(CommandSpec spec, string message) => new(spec, null, message, false);

    /// <summary>Never echoes the argument. An order-ID-looking option gets the reason instead.</summary>
    private static string UnknownOption(string name) =>
        name.Contains("order", StringComparison.OrdinalIgnoreCase) || name.Contains("owner", StringComparison.OrdinalIgnoreCase)
            ? "The order ID is not an option: the command asks for it with no echo."
            : "Unknown option. Run the command with --help for its options.";
}
