using System.Globalization;
using System.Text.Json;
using Serilog;
using Zaghlol.Infrastructure.Logging;

namespace Zaghlol.Infrastructure.Tests.Observability;

/// <summary>Runs code against the real production logger configuration and returns the final output bytes as text.</summary>
internal static class LogCapture
{
    public static string Run(Action<ILogger> log, string service = "test")
    {
        using var writer = new StringWriter(CultureInfo.InvariantCulture);
        using (var logger = new LoggerConfiguration().ConfigureZaghlol(service, writer).CreateLogger())
        {
            log(logger);
        }

        return writer.ToString();
    }

    public static JsonElement Single(string output)
    {
        var lines = output.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        Assert.Single(lines);
        return JsonDocument.Parse(lines[0]).RootElement.Clone();
    }

    public static string[] Keys(JsonElement element) => [.. element.EnumerateObject().Select(p => p.Name)];
}
