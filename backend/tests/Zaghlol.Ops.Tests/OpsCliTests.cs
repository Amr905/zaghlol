using Zaghlol.Ops.Tests.Support;

namespace Zaghlol.Ops.Tests;

public class OpsCliTests
{
    [Fact]
    public async Task NoArgsPrintsUsageAndSucceeds()
    {
        using var env = new TestEnvironment(null, null);

        var code = await env.RunAsync();

        Assert.Equal(OpsCli.Success, code);
        Assert.Contains("Usage", env.Output.ToString(), StringComparison.Ordinal);
        Assert.Contains("support unfreeze", env.Output.ToString(), StringComparison.Ordinal);
        Assert.Equal(string.Empty, env.Error.ToString());
    }

    [Fact]
    public async Task UnknownCommandIsUsageErrorAndIsNotEchoed()
    {
        using var env = new TestEnvironment(null, null);

        var code = await env.RunAsync("nope-SENTINEL");

        Assert.Equal(OpsCli.UsageError, code);
        Assert.NotEqual(string.Empty, env.Error.ToString());
        Assert.DoesNotContain("SENTINEL", env.AllOutput, StringComparison.Ordinal);
    }

    [Fact]
    public async Task VersionPrintsAVersion()
    {
        using var env = new TestEnvironment(null, null);

        Assert.Equal(OpsCli.Success, await env.RunAsync("--version"));
        Assert.Matches(@"^\d+\.\d+", env.Output.ToString());
    }

    [Fact]
    public async Task CommandHelpShowsUsage()
    {
        using var env = new TestEnvironment(null, null);

        Assert.Equal(OpsCli.Success, await env.RunAsync("support", "move", "--help"));
        Assert.Contains("support move --purchase", env.Output.ToString(), StringComparison.Ordinal);
        Assert.Contains("no echo", env.Output.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task MissingSettingsAreUsageErrorsThatNameTheSettingOnly()
    {
        using var env = new TestEnvironment(null, null);
        env.Variables.Remove("ZAGHLOL_OPS_ISSUER");
        env.Variables["ZAGHLOL_OPS_CLIENT_ID"] = "client-VALUE-123";

        var code = await env.RunAsync("status");

        Assert.Equal(OpsCli.UsageError, code);
        Assert.Contains("issuer", env.Error.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("VALUE-123", env.AllOutput, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData("ZAGHLOL_OPS_ISSUER", "http://login.zaghlol.test/")]
    [InlineData("ZAGHLOL_OPS_API_URL", "http://api.example.com")]
    [InlineData("ZAGHLOL_OPS_API_URL", "https://user:pw@api.example.com")]
    [InlineData("ZAGHLOL_OPS_REDIRECT_HOST", "evil.example.com")]
    [InlineData("ZAGHLOL_OPS_TOKEN_USE", "refresh_token")]
    [InlineData("ZAGHLOL_OPS_TOKEN_CACHE", "file")]
    [InlineData("ZAGHLOL_OPS_SCOPES", "email")]
    public async Task UnsafeSettingsAreRefusedWithoutEchoingTheValue(string name, string value)
    {
        using var env = new TestEnvironment(null, null);
        env.Variables[name] = value;

        var code = await env.RunAsync("status");

        Assert.Equal(OpsCli.UsageError, code);
        Assert.DoesNotContain(value, env.AllOutput, StringComparison.Ordinal);
    }

    [Fact]
    public async Task ASettingsFileIsReadButNeverCarriesTheClientSecretOrUnknownMembers()
    {
        using var env = new TestEnvironment(null, null);
        env.Variables.Clear();
        env.Variables["ZAGHLOL_OPS_CONFIG"] = "ops.json";
        env.Files["ops.json"] = "{\"apiUrl\":\"https://api.zaghlol.test\",\"issuer\":\"https://login.zaghlol.test/t/v2.0\",\"clientId\":\"zaghlol-ops\"}";
        Assert.Equal(OpsCli.Success, await env.RunAsync("status"));
        Assert.Contains("\"clientId\": \"zaghlol-ops\"", env.Output.ToString(), StringComparison.Ordinal);

        env.Files["ops.json"] = "{\"apiUrl\":\"https://api.zaghlol.test\",\"issuer\":\"https://login.zaghlol.test/t/v2.0\",\"clientId\":\"zaghlol-ops\",\"clientSecret\":\"SECRET-IN-FILE\"}";
        using var again = new StringWriter();
        Assert.Equal(OpsCli.UsageError, await env.RunAsync("status"));
        Assert.DoesNotContain("SECRET-IN-FILE", env.AllOutput, StringComparison.Ordinal);
    }
}
