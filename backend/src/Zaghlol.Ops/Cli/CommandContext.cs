using System.Buffers;
using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using Zaghlol.Ops.Api;
using Zaghlol.Ops.Auth;

namespace Zaghlol.Ops.Cli;

/// <summary>Exit codes. 3 means "sign in again or ask for a role"; 4 means "try again later".</summary>
internal static class ExitCode
{
    public const int Success = 0;
    public const int ApiRefused = 1;
    public const int Usage = 2;
    public const int Auth = 3;
    public const int Unreachable = 4;
}

internal delegate void BodyWriter(Utf8JsonWriter writer, ReadOnlySpan<char> secret);

/// <summary>What one command run has: its arguments, output, and the lazily built settings, token and API client.</summary>
internal sealed class CommandContext
{
    private readonly OpsEnvironment environment;
    private OpsConfig? config;
    private TokenProvider? tokens;
    private AdminApiClient? api;

    public CommandContext(OpsEnvironment environment, ParsedArgs args, Printer printer, CancellationToken cancellationToken)
    {
        this.environment = environment;
        Args = args;
        Printer = printer;
        CancellationToken = cancellationToken;
    }

    public ParsedArgs Args { get; }

    public Printer Printer { get; }

    public CancellationToken CancellationToken { get; }

    public OpsEnvironment Environment => environment;

    public OpsConfig Config => config ??= OpsConfig.Load(environment.GetEnvironmentVariable, Args.Get("config"), environment.ReadFile, environment.DefaultConfigPath);

    public TokenProvider Tokens => tokens ??= CreateTokens();

    public AdminApiClient Api => api ??= CreateApi();

    /// <summary>A usage problem: prints the message and returns the usage exit code.</summary>
    public int Usage(string message)
    {
        Printer.Err("error: " + message);
        return ExitCode.Usage;
    }

    /// <summary>Signs in if needed. Null when it worked, else the exit code.</summary>
    public async Task<int?> SignInAsync()
    {
        try
        {
            await Api.EnsureTokenAsync(CancellationToken).ConfigureAwait(false);
            return null;
        }
        catch (LoginException e)
        {
            Printer.Err("error: sign-in failed: " + e.Message);
            return ExitCode.Auth;
        }
    }

    /// <summary>
    /// One API call: builds the JSON body (the secret, if any, is passed to <paramref name="body"/> as characters and the byte
    /// buffer is cleared afterwards), sends it, prints the answer and returns the exit code.
    /// </summary>
    public async Task<int> CallAsync(HttpMethod method, string path, BodyWriter? body = null, ReadOnlyMemory<char> secret = default, bool quiet = false)
    {
        byte[]? bytes = null;
        if (body is not null)
        {
            var buffer = new ArrayBufferWriter<byte>(512);
            using (var writer = new Utf8JsonWriter(buffer))
            {
                body(writer, secret.Span);
            }

            bytes = buffer.WrittenSpan.ToArray();
            buffer.Clear();
        }

        try
        {
            var response = await Api.SendAsync(method, path, bytes, CancellationToken).ConfigureAwait(false);
            return Report(response, quiet);
        }
        catch (LoginException e)
        {
            Printer.Err("error: sign-in failed: " + e.Message);
            return ExitCode.Auth;
        }
        catch (ApiUnreachableException e)
        {
            Printer.Err("error: " + e.Message);
            return ExitCode.Unreachable;
        }
        finally
        {
            if (bytes is not null)
            {
                CryptographicOperations.ZeroMemory(bytes);
            }
        }
    }

    /// <summary>Prints a success body or an error line and maps the status to an exit code.</summary>
    public int Report(ApiResponse response, bool quiet = false)
    {
        ArgumentNullException.ThrowIfNull(response);

        if (response.IsSuccess)
        {
            if (quiet)
            {
                return ExitCode.Success;
            }

            if (response.Body is not null)
            {
                Printer.Json(response.Body);
            }
            else
            {
                Printer.Err($"ok ({response.Status.ToString(System.Globalization.CultureInfo.InvariantCulture)})");
            }

            return ExitCode.Success;
        }

        var line = $"error: {response.Status.ToString(System.Globalization.CultureInfo.InvariantCulture)} {response.Code ?? "UNKNOWN"}";
        if (!string.IsNullOrEmpty(response.Title))
        {
            line += ": " + response.Title;
        }

        Printer.Err(line);
        if (!string.IsNullOrEmpty(response.Detail))
        {
            Printer.Err("  " + response.Detail);
        }

        if (response.RetryAfterSeconds is { } retry)
        {
            Printer.Err($"  retry after {retry.ToString(System.Globalization.CultureInfo.InvariantCulture)} s");
        }

        if (response.CorrelationId is not null)
        {
            Printer.Err("  correlation id " + response.CorrelationId);
        }

        return response.Status is 401 or 403 ? ExitCode.Auth : ExitCode.ApiRefused;
    }

    private TokenProvider CreateTokens()
    {
        var settings = Config;
        var login = new OidcLogin(settings, NewClient(environment.IdpHandler(), TimeSpan.FromSeconds(30)), environment.Browser, environment.Clock, Printer.ErrorWriter);
        return new TokenProvider(
            settings,
            environment.TokenStore(settings),
            new MemoryTokenStore(),
            (browser, ct) => login.LoginAsync(browser && !Args.Has("no-browser"), ct),
            environment.Clock,
            Printer.ErrorWriter);
    }

    private AdminApiClient CreateApi() =>
        new(Config, NewClient(environment.ApiHandler(), AdminApiClient.Timeout + TimeSpan.FromSeconds(5)), Tokens, openBrowser: true);

    private static HttpClient NewClient(HttpMessageHandler handler, TimeSpan timeout) => new(handler, disposeHandler: true) { Timeout = timeout };
}
