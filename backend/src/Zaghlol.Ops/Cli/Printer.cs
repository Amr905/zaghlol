using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Unicode;

namespace Zaghlol.Ops.Cli;

/// <summary>
/// All CLI output goes through here. A value registered with <see cref="Protect"/> (the order ID) is replaced by
/// <c>[redacted]</c> in anything printed, as a second line of defence behind the rule that no code path prints it.
/// JSON is written with an encoder that escapes everything outside Basic Latin and Arabic, so server text can't carry terminal
/// control sequences or bidirectional overrides to the operator's screen.
/// </summary>
internal sealed class Printer(TextWriter output, TextWriter error)
{
    private static readonly JsonSerializerOptions Pretty = new()
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.Create(UnicodeRanges.BasicLatin, UnicodeRanges.Arabic),
    };

    private readonly List<char[]> protectedValues = [];

    /// <summary>The raw error writer, for the sign-in messages (they never contain protected values).</summary>
    public TextWriter ErrorWriter => error;

    public void Protect(char[] value) => protectedValues.Add(value);

    public void Unprotect() => protectedValues.Clear();

    public void Out(string text) => output.WriteLine(Redact(text));

    public void Err(string text) => error.WriteLine(Redact(text));

    public void Json(JsonNode? node) => Out(node is null ? "null" : node.ToJsonString(Pretty));

    /// <summary>Printable ASCII only, capped: how server text is shown.</summary>
    public static string Plain(string? text, int max = 200)
    {
        if (text is null)
        {
            return string.Empty;
        }

        var cleaned = new string([.. text.Select(c => c is >= ' ' and <= '~' ? c : '?')]);
        return cleaned.Length <= max ? cleaned : cleaned[..max];
    }

    internal string Redact(string text)
    {
        var result = text;
        foreach (var value in protectedValues)
        {
            if (value.Length == 0)
            {
                continue;
            }

            var index = result.AsSpan().IndexOf(value);
            while (index >= 0)
            {
                result = string.Concat(result.AsSpan(0, index), "[redacted]", result.AsSpan(index + value.Length));
                index = result.AsSpan().IndexOf(value);
            }
        }

        return result;
    }
}
