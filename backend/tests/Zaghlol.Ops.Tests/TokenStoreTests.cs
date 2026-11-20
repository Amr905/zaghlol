using System.Diagnostics;
using Zaghlol.Ops.Auth;
using Zaghlol.Testing;

namespace Zaghlol.Ops.Tests;

/// <summary>Token storage (design note section 2): the secret goes through stdin only; no store writes a file; a broken store falls back to memory.</summary>
public class TokenStoreTests
{
    private const string Key = "0123456789abcdef01234567";

    private static string SampleToken() => "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ4In0.c2lnbmF0dXJlLXNlbnRpbmVsLXRva2Vu";

    [Fact]
    public async Task LinuxPassesTheSecretOnStdinAndNeverInTheArguments()
    {
        var runner = new RecordingRunner();
        var store = new ProcessTokenStore(runner, mac: false, "secret-tool");
        var token = SampleToken();

        Assert.True(await store.WriteAsync(Key, token, CancellationToken.None));

        var store1 = runner.Calls.First();
        Assert.Equal("secret-tool", store1.File);
        Assert.Equal(token, store1.Stdin);
        Assert.Equal(["store", "--label", "zaghlol-ops sign-in token", "service", "zaghlol-ops", "account", Key], store1.Args);
        Assert.All(runner.Calls, c => Assert.DoesNotContain(c.Args, a => a.Contains(token, StringComparison.Ordinal) || a.Contains(token[..30], StringComparison.Ordinal)));
        Assert.Equal(token, await store.ReadAsync(Key, CancellationToken.None));
        Assert.Equal("secret-service", store.Name);
    }

    [Fact]
    public async Task MacPassesTheAddCommandOnStdinThroughSecurityInteractiveMode()
    {
        var runner = new RecordingRunner();
        var store = new ProcessTokenStore(runner, mac: true);
        var token = SampleToken();

        Assert.True(await store.WriteAsync(Key, token, CancellationToken.None));

        var add = runner.Calls.First();
        Assert.Equal("/usr/bin/security", add.File);
        Assert.Equal(["-i"], add.Args);
        Assert.Contains("add-generic-password -U", add.Stdin, StringComparison.Ordinal);
        Assert.Contains(token, add.Stdin, StringComparison.Ordinal);
        Assert.All(runner.Calls, c => Assert.DoesNotContain(c.Args, a => a.Contains(token[..30], StringComparison.Ordinal)));
        Assert.Equal("keychain", store.Name);
    }

    [Theory]
    [InlineData("has space")]
    [InlineData("quote\"inside")]
    [InlineData("new\nline")]
    [InlineData("semi;colon")]
    [InlineData("")]
    public async Task AValueOutsideTheTokenCharacterSetIsNotStoredAndNoProcessStarts(string value)
    {
        var runner = new RecordingRunner();

        Assert.False(await new ProcessTokenStore(runner, mac: true).WriteAsync(Key, value, CancellationToken.None));
        Assert.False(await new ProcessTokenStore(runner, mac: false).WriteAsync(Key, value, CancellationToken.None));
        Assert.False(await new ProcessTokenStore(runner, mac: true).WriteAsync("bad key", SampleToken(), CancellationToken.None));
        Assert.Empty(runner.Calls);
    }

    [Fact]
    public async Task AMissingToolMeansNoStoreAndNotAnError()
    {
        var store = new ProcessTokenStore(new RecordingRunner { Missing = true }, mac: false);

        Assert.False(await store.WriteAsync(Key, SampleToken(), CancellationToken.None));
        Assert.Null(await store.ReadAsync(Key, CancellationToken.None));
        Assert.False(await store.DeleteAsync(Key, CancellationToken.None));
    }

    [Fact]
    public async Task AWriteThatCannotBeReadBackIsReportedAsFailed()
    {
        var store = new ProcessTokenStore(new RecordingRunner { DropWrites = true }, mac: false);

        Assert.False(await store.WriteAsync(Key, SampleToken(), CancellationToken.None));
    }

    [Fact]
    public async Task DeleteIsConfirmedByReadingBack()
    {
        var runner = new RecordingRunner();
        var store = new ProcessTokenStore(runner, mac: false);
        await store.WriteAsync(Key, SampleToken(), CancellationToken.None);

        Assert.True(await store.DeleteAsync(Key, CancellationToken.None));
        Assert.Null(await store.ReadAsync(Key, CancellationToken.None));

        runner.IgnoreDeletes = true;
        await store.WriteAsync(Key, SampleToken(), CancellationToken.None);
        Assert.False(await store.DeleteAsync(Key, CancellationToken.None));
    }

    [Fact]
    public async Task TheRealProcessRunnerTalksToASecretToolStandIn()
    {
        if (!OperatingSystem.IsLinux())
        {
            return;
        }

        var dir = Path.Combine(Path.GetTempPath(), "zaghlol-ops-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            var script = Path.Combine(dir, "secret-tool");
            var vault = Path.Combine(dir, "vault");
            var argvLog = Path.Combine(dir, "argv.log");
            File.WriteAllText(
                script,
                "#!/bin/sh\n" +
                $"echo \"$@\" >> '{argvLog}'\n" +
                "case \"$1\" in\n" +
                $"  store) cat > '{vault}' ;;\n" +
                $"  lookup) [ -f '{vault}' ] && cat '{vault}' || exit 1 ;;\n" +
                $"  clear) rm -f '{vault}' ;;\n" +
                "esac\n");
            File.SetUnixFileMode(script, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
            var store = new ProcessTokenStore(new ProcessRunner(), mac: false, script);
            var token = SampleToken();

            Assert.True(await store.WriteAsync(Key, token, CancellationToken.None));
            Assert.Equal(token, await store.ReadAsync(Key, CancellationToken.None));
            Assert.DoesNotContain(token[..30], File.ReadAllText(argvLog), StringComparison.Ordinal);
            Assert.True(await store.DeleteAsync(Key, CancellationToken.None));
            Assert.Null(await store.ReadAsync(Key, CancellationToken.None));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public async Task ARunnerWithAMissingProgramReturnsNullInsteadOfThrowing()
    {
        var result = await new ProcessRunner().RunAsync("/nonexistent/zaghlol-ops-tool", ["x"], null, TimeSpan.FromSeconds(5), CancellationToken.None);

        Assert.Null(result);
    }

    [Fact]
    public async Task ARunnerTimeoutKillsTheChildAndReturnsNull()
    {
        if (!OperatingSystem.IsLinux())
        {
            return;
        }

        var watch = Stopwatch.StartNew();
        var result = await new ProcessRunner().RunAsync("/bin/sleep", ["30"], null, TimeSpan.FromMilliseconds(300), CancellationToken.None);

        Assert.Null(result);
        Assert.True(watch.Elapsed < TimeSpan.FromSeconds(10));
    }

    [Fact]
    public void TokenSetRoundTripsAndRefusesMalformedValues()
    {
        var token = SampleToken();
        var set = new TokenSet(token, DateTimeOffset.FromUnixTimeSeconds(1_900_000_000), "x");

        var back = TokenSet.TryParse(set.Serialize());

        Assert.Equal(token, back!.Token);
        Assert.Equal(1_900_000_000, back.ExpiresAt.ToUnixTimeSeconds());
        Assert.Matches("^[A-Za-z0-9._-]+$", set.Serialize());
        Assert.Null(TokenSet.TryParse(null));
        Assert.Null(TokenSet.TryParse("v2.1." + token));
        Assert.Null(TokenSet.TryParse("v1.x." + token));
        Assert.Null(TokenSet.TryParse("v1.1900000000.not-a-jwt"));
        Assert.Null(TokenSet.TryParse("v1.-5." + token));
        Assert.False(TokenSet.IsTokenShaped("a.b.c"));
        Assert.False(TokenSet.IsTokenShaped(token + "\n"));
        Assert.False(TokenSet.IsTokenShaped(token + " x"));
    }

    [Fact]
    public async Task AStoreThatCannotWriteFallsBackToMemoryOnceAndSaysSoWithoutAFile()
    {
        var config = Config("os");
        var memory = new MemoryTokenStore();
        using var error = new StringWriter();
        var logins = 0;
        var provider = new TokenProvider(config, new RefusingStore(), memory, (_, _) => Task.FromResult(NewToken(++logins)), TimeProvider.System, error);

        var first = await provider.SignInAsync(true, CancellationToken.None);
        var second = await provider.SignInAsync(true, CancellationToken.None);

        Assert.NotEqual(first.Token, second.Token);
        Assert.Equal(1, error.ToString().Split("memory for this run only", StringSplitOptions.None).Length - 1);
        Assert.Equal(second.Token, (await provider.GetAsync(true, CancellationToken.None)).Token);
        Assert.Equal(2, logins);
    }

    [Fact]
    public async Task MemoryModeNeverTouchesTheCredentialStore()
    {
        var tracking = new CountingStore();
        using var error = new StringWriter();
        var provider = new TokenProvider(Config("memory"), tracking, new MemoryTokenStore(), (_, _) => Task.FromResult(NewToken(1)), TimeProvider.System, error);

        await provider.SignInAsync(true, CancellationToken.None);
        await provider.GetAsync(true, CancellationToken.None);
        await provider.SignOutAsync(CancellationToken.None);

        Assert.Equal(0, tracking.Calls);
        Assert.Equal("memory", provider.StoreName);
    }

    [Fact]
    public async Task ARefusedTokenIsForgottenEverywhere()
    {
        var store = new MemoryTokenStore();
        using var error = new StringWriter();
        var config = Config("os");
        var provider = new TokenProvider(config, store, new MemoryTokenStore(), (_, _) => Task.FromResult(NewToken(1)), TimeProvider.System, error);
        await provider.SignInAsync(true, CancellationToken.None);
        Assert.NotNull(await store.ReadAsync(config.CacheKey(), CancellationToken.None));

        await provider.ForgetAsync(CancellationToken.None);

        Assert.Null(await store.ReadAsync(config.CacheKey(), CancellationToken.None));
        Assert.Null(await provider.CachedAsync(CancellationToken.None));
    }

    [Fact]
    public void TheCacheKeyIsPublicHexAndDependsOnIssuerClientAndApi()
    {
        var a = Config("os");
        var b = a with { ClientId = "other-client" };
        var c = a with { ApiUrl = new Uri("https://other.example") };

        Assert.Matches("^[0-9a-f]{24}$", a.CacheKey());
        Assert.NotEqual(a.CacheKey(), b.CacheKey());
        Assert.NotEqual(a.CacheKey(), c.CacheKey());
    }

    [Fact]
    public void TheWindowsStoreChunksWithinTheCredentialBlobLimit()
    {
        // CRED_MAX_CREDENTIAL_BLOB_SIZE is 2560 bytes; a chunk stays under it and 4 chunks carry a 16 KiB-capped token only up to 8000 bytes.
        Assert.True(CredentialBlobLimits.ChunkBytes < 2560);
        Assert.True(CredentialBlobLimits.ChunkBytes * CredentialBlobLimits.MaxChunks >= 6000);
    }

    private static OpsConfig Config(string cache) => OpsConfig.Load(
        name => name switch
        {
            "ZAGHLOL_OPS_API_URL" => "https://api.zaghlol.test",
            "ZAGHLOL_OPS_ISSUER" => "https://login.zaghlol.test/t/v2.0",
            "ZAGHLOL_OPS_CLIENT_ID" => "zaghlol-ops",
            "ZAGHLOL_OPS_TOKEN_CACHE" => cache,
            _ => null,
        },
        null,
        _ => null,
        null);

    private static TokenSet NewToken(int n)
    {
        using var issuer = new FakeOidcIssuer();
        var jwt = issuer.Mint(new OperatorTokenSpec { Subject = "sub-" + n }, DateTimeOffset.UtcNow);
        return new TokenSet(jwt, DateTimeOffset.UtcNow.AddMinutes(50), "sub-" + n);
    }

    private sealed class RefusingStore : ITokenStore
    {
        public string Name => "refusing";

        public Task<string?> ReadAsync(string key, CancellationToken cancellationToken) => Task.FromResult<string?>(null);

        public Task<bool> WriteAsync(string key, string value, CancellationToken cancellationToken) => Task.FromResult(false);

        public Task<bool> DeleteAsync(string key, CancellationToken cancellationToken) => Task.FromResult(false);
    }

    private sealed class CountingStore : ITokenStore
    {
        public int Calls { get; private set; }

        public string Name => "counting";

        public Task<string?> ReadAsync(string key, CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult<string?>(null);
        }

        public Task<bool> WriteAsync(string key, string value, CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(true);
        }

        public Task<bool> DeleteAsync(string key, CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(true);
        }
    }

    /// <summary>A pretend <c>secret-tool</c> and <c>security</c>: records every call and keeps the stored value in memory.</summary>
    private sealed class RecordingRunner : IProcessRunner
    {
        private string? vault;

        public List<(string File, IReadOnlyList<string> Args, string? Stdin)> Calls { get; } = [];

        public bool Missing { get; set; }

        public bool DropWrites { get; set; }

        public bool IgnoreDeletes { get; set; }

        public Task<ProcessResult?> RunAsync(string fileName, IReadOnlyList<string> arguments, string? standardInput, TimeSpan timeout, CancellationToken cancellationToken)
        {
            Calls.Add((fileName, arguments, standardInput));
            if (Missing)
            {
                return Task.FromResult<ProcessResult?>(null);
            }

            var verb = arguments[0];
            if (verb == "store" && !DropWrites)
            {
                vault = standardInput;
            }
            else if (verb == "-i" && !DropWrites)
            {
                var commands = standardInput!;
                vault = commands[(commands.IndexOf("-w \"", StringComparison.Ordinal) + 4)..].TrimEnd('\n').TrimEnd('"');
            }
            else if (verb is "clear" or "delete-generic-password" && !IgnoreDeletes)
            {
                vault = null;
            }
            else if (verb is "lookup" or "find-generic-password")
            {
                return Task.FromResult<ProcessResult?>(vault is null ? new ProcessResult(1, string.Empty) : new ProcessResult(0, vault + "\n"));
            }

            return Task.FromResult<ProcessResult?>(new ProcessResult(0, string.Empty));
        }
    }
}
