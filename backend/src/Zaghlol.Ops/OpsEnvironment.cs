using Zaghlol.Ops.Auth;
using Zaghlol.Ops.Cli;

namespace Zaghlol.Ops;

/// <summary>Everything the CLI touches outside itself, so tests can stand in for the terminal, the browser, the IdP and the API.</summary>
internal sealed class OpsEnvironment
{
    public required TextWriter Output { get; init; }

    public required TextWriter Error { get; init; }

    /// <summary>Standard input as text, for <c>--file -</c> (never for the order ID, which only the prompt reads).</summary>
    public required Func<TextReader> Input { get; init; }

    public required Func<string, string?> GetEnvironmentVariable { get; init; }

    /// <summary>The file's text, or <c>null</c> when it does not exist or cannot be read.</summary>
    public required Func<string, string?> ReadFile { get; init; }

    public string? DefaultConfigPath { get; init; }

    public required Func<HttpMessageHandler> ApiHandler { get; init; }

    public required Func<HttpMessageHandler> IdpHandler { get; init; }

    public required IBrowserLauncher Browser { get; init; }

    public required ISecretPrompt Prompt { get; init; }

    public required Func<OpsConfig, ITokenStore> TokenStore { get; init; }

    public required TimeProvider Clock { get; init; }

    /// <summary>The real terminal, browser, network and credential store.</summary>
    public static OpsEnvironment ForProcess() => new()
    {
        Output = Console.Out,
        Error = Console.Error,
        Input = () => Console.In,
        GetEnvironmentVariable = name => OpsConfig.EnvironmentVariables.Contains(name, StringComparer.Ordinal) ? Environment.GetEnvironmentVariable(name) : null,
        ReadFile = path =>
        {
            try
            {
                var info = new FileInfo(path);
                return info.Exists && info.Length <= MaxFileBytes ? File.ReadAllText(path) : null;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                return null;
            }
        },
        DefaultConfigPath = DefaultConfigFile(),
        ApiHandler = Handler,
        IdpHandler = Handler,
        Browser = new SystemBrowserLauncher(),
        Prompt = new SecretPrompt(new ConsoleKeySource(), Console.Error),
        TokenStore = StoreFor,
        Clock = TimeProvider.System,
    };

    public const int MaxFileBytes = 1024 * 1024;

    private static SocketsHttpHandler Handler() => new()
    {
        // A redirect would carry the bearer token to another host; none is followed.
        AllowAutoRedirect = false,
        ConnectTimeout = TimeSpan.FromSeconds(15),
        PooledConnectionLifetime = TimeSpan.FromMinutes(2),
    };

    private static ITokenStore StoreFor(OpsConfig config)
    {
        if (config.TokenCache == TokenCacheMode.Memory)
        {
            return new MemoryTokenStore();
        }

        if (OperatingSystem.IsWindows())
        {
            return new WindowsCredentialStore();
        }

        return new ProcessTokenStore(new ProcessRunner(), mac: OperatingSystem.IsMacOS());
    }

    private static string? DefaultConfigFile()
    {
        var root = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        if (string.IsNullOrEmpty(root))
        {
            root = OperatingSystem.IsWindows()
                ? Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData)
                : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".config");
        }

        return string.IsNullOrEmpty(root) ? null : Path.Combine(root, "zaghlol-ops", "config.json");
    }
}
