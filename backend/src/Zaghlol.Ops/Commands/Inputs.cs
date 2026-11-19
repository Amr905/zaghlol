using System.Text.Json;
using Zaghlol.Ops.Cli;

namespace Zaghlol.Ops.Commands;

/// <summary>Reads JSON the operator supplies in a file (or standard input for <c>-</c>), with a size cap and a type check.</summary>
internal static class Inputs
{
    public const int MaxBodyBytes = 64 * 1024;

    public static JsonDocument? ReadObject(CommandContext ctx, string path, int maxBytes, out string? error)
    {
        string? text;
        if (path == "-")
        {
            text = ReadCapped(ctx.Environment.Input(), maxBytes);
        }
        else
        {
            text = ctx.Environment.ReadFile(path);
        }

        if (text is null || text.Length > maxBytes)
        {
            error = "The input file is missing, unreadable or larger than " + (maxBytes / 1024).ToString(System.Globalization.CultureInfo.InvariantCulture) + " KiB.";
            return null;
        }

        try
        {
            var document = JsonDocument.Parse(text, new JsonDocumentOptions { MaxDepth = 16 });
            if (document.RootElement.ValueKind == JsonValueKind.Object)
            {
                error = null;
                return document;
            }

            document.Dispose();
        }
        catch (JsonException)
        {
            // Reported below without the parser's message (it can quote input).
        }

        error = "The input is not a JSON object.";
        return null;
    }

    private static string? ReadCapped(TextReader reader, int maxBytes)
    {
        var buffer = new char[maxBytes + 1];
        var read = reader.ReadBlock(buffer, 0, buffer.Length);
        return read > maxBytes ? null : new string(buffer, 0, read);
    }
}
