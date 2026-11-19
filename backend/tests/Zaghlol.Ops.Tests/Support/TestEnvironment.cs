using System.Text;
using Zaghlol.Ops.Auth;
using Zaghlol.Ops.Cli;

namespace Zaghlol.Ops.Tests.Support;

/// <summary>A scripted order-ID prompt: returns the given text through the real <see cref="SecretPrompt"/> logic, or refuses.</summary>
internal sealed class ScriptedKeys(string? typed, bool interactive = true) : IKeySource
{
    private readonly Queue<ConsoleKeyInfo> keys = typed is null ? new() : new(Keys(typed));

    /// <summary>Queues what the operator types at the next prompt.</summary>
    public void Enqueue(string text)
    {
        foreach (var key in Keys(text))
        {
            keys.Enqueue(key);
        }
    }

    public bool IsInteractive => interactive;

    public ConsoleKeyInfo ReadKey() => keys.Count > 0 ? keys.Dequeue() : throw new InvalidOperationException("The test script ran out of keys.");

    internal static IEnumerable<ConsoleKeyInfo> Keys(string? text)
    {
        foreach (var c in text ?? string.Empty)
        {
            yield return c == '\b'
                ? new ConsoleKeyInfo('\b', ConsoleKey.Backspace, false, false, false)
                : new ConsoleKeyInfo(c, c is >= 'a' and <= 'z' ? ConsoleKey.A : ConsoleKey.D0, char.IsUpper(c), false, false);
        }

        yield return new ConsoleKeyInfo('\r', ConsoleKey.Enter, false, false, false);
    }
}

/// <summary>An <see cref="OpsEnvironment"/> for tests with captured output, an in-memory credential store and scripted inputs.</summary>
internal sealed class TestEnvironment : IDisposable
{
    public const string ApiBase = "https://api.zaghlol.test";

    public TestEnvironment(HttpMessageHandler? api, CliTestIdp? idp, string? typedOrderId = null, bool interactive = true, bool ownsIdp = true)
    {
        Idp = idp;
        this.ownsIdp = ownsIdp;
        PromptText = new StringWriter();
        Variables = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["ZAGHLOL_OPS_API_URL"] = ApiBase,
            ["ZAGHLOL_OPS_ISSUER"] = idp?.Issuer.Issuer ?? "https://login.zaghlol.test/tenant/v2.0",
            ["ZAGHLOL_OPS_CLIENT_ID"] = CliTestIdp.ClientId,
        };
        Keys = new ScriptedKeys(typedOrderId, interactive);
        Prompt = new SecretPrompt(Keys, PromptText);
        Api = api;
    }

    private readonly bool ownsIdp;

    public CliTestIdp? Idp { get; }

    public StringWriter Output { get; } = new();

    public StringWriter Error { get; } = new();

    public StringWriter PromptText { get; }

    public Dictionary<string, string> Variables { get; }

    public Dictionary<string, string> Files { get; } = new(StringComparer.Ordinal);

    public string StandardInput { get; set; } = string.Empty;

    public ScriptedKeys Keys { get; }

    public SecretPrompt Prompt { get; }

    public HttpMessageHandler? Api { get; }

    public MemoryTokenStore Store { get; } = new();

    /// <summary>Queues the next order ID the operator "types".</summary>
    public void Type(string text) => Keys.Enqueue(text);

    public void ClearOutput()
    {
        Output.GetStringBuilder().Clear();
        Error.GetStringBuilder().Clear();
        PromptText.GetStringBuilder().Clear();
    }

    public string AllOutput => Output + "\n" + Error + "\n" + PromptText;

    public OpsEnvironment Build() => new()
    {
        Output = Output,
        Error = Error,
        Input = () => new StringReader(StandardInput),
        GetEnvironmentVariable = name => Variables.GetValueOrDefault(name),
        ReadFile = path => Files.GetValueOrDefault(path),
        DefaultConfigPath = null,
        ApiHandler = () => Api ?? new StubHandler((_, _) => throw new InvalidOperationException("This test must not call the API.")),
        IdpHandler = () => Idp?.CreateHandler() ?? new StubHandler((_, _) => throw new InvalidOperationException("This test must not call the IdP.")),
        Browser = (IBrowserLauncher?)Idp?.Browser ?? new RefusingBrowser(),
        Prompt = Prompt,
        TokenStore = _ => Store,
        Clock = TimeProvider.System,
    };

    public async Task<int> RunAsync(params string[] args)
    {
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(60));
        return await OpsCli.RunAsync(args, Build(), cancellation.Token);
    }

    public void Dispose()
    {
        if (ownsIdp)
        {
            Idp?.Dispose();
        }
    }

    private sealed class RefusingBrowser : IBrowserLauncher
    {
        public bool TryOpen(Uri url) => throw new InvalidOperationException("This test must not open a browser.");
    }
}
