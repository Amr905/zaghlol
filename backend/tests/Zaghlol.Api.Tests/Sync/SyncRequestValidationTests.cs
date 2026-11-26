using System.Text.Json;
using Zaghlol.Api.Endpoints.V1;
using Zaghlol.Api.Json;

namespace Zaghlol.Api.Tests.Sync;

/// <summary>T-334: the two new BR-SYNC-03 members of <c>SyncRequest</c> (<c>configVersion</c>, <c>llmCatFeedback</c>) and the config block's wire form.</summary>
public class SyncRequestValidationTests
{
    private const string Item = """{"merchantNorm":"zawya coffee","verdict":"wrong","aiCategory":"dining","userCategory":"custom","source":"llm"}""";

    private static SyncRequest Parse(string json) =>
        JsonSerializer.Deserialize(json, StrictJson.Options.GetTypeInfo(typeof(SyncRequest))) as SyncRequest ?? throw new InvalidOperationException();

    [Fact]
    public void ConfigVersionAndFeedbackAreAcceptedMembers()
    {
        var request = Parse($$"""{"catalogVersion":1,"flagsVersion":1,"configVersion":3,"llmCatFeedback":[{{Item}}]}""");

        Assert.True(SyncEndpoints.TryValidate(request));
        Assert.Equal(3, request.ConfigVersion);
        Assert.Single(request.LlmCatFeedback!);
    }

    [Fact]
    public void AnUnknownFeedbackMemberIsStillRejected()
    {
        var bad = Item.Replace("\"source\":\"llm\"", "\"source\":\"llm\",\"amount\":\"10.00\"", StringComparison.Ordinal);

        Assert.ThrowsAny<JsonException>(() => Parse($$"""{"catalogVersion":1,"flagsVersion":1,"llmCatFeedback":[{{bad}}]}"""));
    }

    [Theory]
    [InlineData("\"configVersion\":-1")]
    [InlineData("\"llmCatFeedback\":[{\"merchantNorm\":\"x\",\"verdict\":\"right\",\"aiCategory\":\"dining\",\"userCategory\":\"dining\",\"source\":\"llm\"}]")]
    [InlineData("\"llmCatFeedback\":[{\"merchantNorm\":\"zawya coffee\",\"verdict\":\"maybe\",\"aiCategory\":\"dining\",\"userCategory\":\"dining\",\"source\":\"llm\"}]")]
    [InlineData("\"llmCatFeedback\":[{\"merchantNorm\":\"zawya coffee\",\"verdict\":\"right\",\"aiCategory\":\"Dining\",\"userCategory\":\"dining\",\"source\":\"llm\"}]")]
    [InlineData("\"llmCatFeedback\":[{\"merchantNorm\":\"zawya coffee\",\"verdict\":\"right\",\"aiCategory\":\"dining\",\"userCategory\":\"dining\",\"source\":\"web\"}]")]
    public void AnInvalidValueIsRejected(string member) =>
        Assert.False(SyncEndpoints.TryValidate(Parse("{\"catalogVersion\":1,\"flagsVersion\":1," + member + "}")));

    [Fact]
    public void MoreThanFiftyFeedbackItemsAreRejectedAsAWhole()
    {
        var items = string.Join(',', Enumerable.Repeat(Item, SyncRequest.MaxLlmCatFeedback + 1));

        Assert.False(SyncEndpoints.TryValidate(Parse($$"""{"catalogVersion":1,"flagsVersion":1,"llmCatFeedback":[{{items}}]}""")));
    }

    [Fact]
    public void TheConfigBlockWritesEveryValueAsAStringAndOmitsAbsentProviderNames()
    {
        var dto = new SyncConfigDto
        {
            Version = 2,
            Values = new Dictionary<string, string> { ["ask.quota_free"] = "7", ["ask.invest_min_egp"] = "100.00" },
        };

        using var json = JsonDocument.Parse(JsonSerializer.Serialize(dto, ApiJsonContext.Default.SyncConfigDto));

        Assert.All(json.RootElement.GetProperty("values").EnumerateObject(), p => Assert.Equal(JsonValueKind.String, p.Value.ValueKind));
        Assert.False(json.RootElement.TryGetProperty("providerName", out _));
    }
}
