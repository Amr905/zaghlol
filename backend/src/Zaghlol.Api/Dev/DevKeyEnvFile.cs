using Microsoft.Extensions.Configuration;

namespace Zaghlol.Api.Dev;

/// <summary>
/// DEV ONLY. <c>Dev:KeyEnvFile</c> names a <c>KEY=value</c> file (the <c>kms.env</c> that <c>tools/dev-keys.sh</c> writes into a
/// docker volume) whose entries become configuration, so the phone-test compose stack needs no host-side key step. A <c>__</c>
/// in a key is a section separator, as in environment variables. Refused outside Development.
/// </summary>
internal static class DevKeyEnvFile
{
    public const string ConfigKey = "Dev:KeyEnvFile";

    public static void AddIfConfigured(ConfigurationManager configuration, IHostEnvironment environment)
    {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(environment);
        if (configuration[ConfigKey] is not { Length: > 0 } path)
        {
            return;
        }

        if (!environment.IsDevelopment())
        {
            throw new InvalidOperationException("Dev:KeyEnvFile is only allowed in the Development environment.");
        }

        configuration.AddInMemoryCollection(Parse(File.ReadAllLines(path)));
    }

    internal static Dictionary<string, string?> Parse(IEnumerable<string> lines)
    {
        var values = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
        foreach (var raw in lines)
        {
            var line = raw.Trim();
            var eq = line.IndexOf('=', StringComparison.Ordinal);
            if (line.Length == 0 || line[0] == '#' || eq <= 0)
            {
                continue;
            }

            values[line[..eq].Trim().Replace("__", ":", StringComparison.Ordinal)] = line[(eq + 1)..].Trim();
        }

        return values;
    }
}
