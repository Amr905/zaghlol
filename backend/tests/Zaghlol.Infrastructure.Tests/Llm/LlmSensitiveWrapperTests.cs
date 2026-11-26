using System.Text;
using System.Text.Json;
using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Llm;
using Zaghlol.Infrastructure.Tests.Observability;

namespace Zaghlol.Infrastructure.Tests.Llm;

/// <summary>M2 / AC4: LlmSensitive never reveals through ToString, interpolation, System.Text.Json (bare, nested, in a collection), the structured logger or an exception message.</summary>
public sealed class LlmSensitiveWrapperTests
{
    private const string Marker = LlmFixtures.Marker;

    private sealed record Dto(LlmSensitive<string> Q, string Plain);

    [Fact]
    public void ToStringAndInterpolationShowStars()
    {
        var value = new LlmSensitive<string>(Marker);

        Assert.Equal("***", value.ToString());
        Assert.Equal("***", $"{value}");
        Assert.Equal(Marker, value.Reveal());
    }

    [Fact]
    public void SystemTextJsonRedactsDirectlyNestedAndInACollection()
    {
        var value = new LlmSensitive<string>(Marker);
        var json = JsonSerializer.Serialize(value)
            + JsonSerializer.Serialize(new Dto(value, "visible"))
            + JsonSerializer.Serialize(new[] { value, value })
            + JsonSerializer.Serialize(new Dictionary<string, LlmSensitive<string>> { ["k"] = value })
            + JsonSerializer.Serialize(new { Anonymous = value })
            + JsonSerializer.Serialize(new LlmSensitive<byte[]>(Encoding.UTF8.GetBytes(Marker)));

        Assert.DoesNotContain(Marker, json, StringComparison.Ordinal);
        Assert.DoesNotContain(Convert.ToBase64String(Encoding.UTF8.GetBytes(Marker)), json, StringComparison.Ordinal);
        Assert.Contains("\"Q\":\"***\"", json, StringComparison.Ordinal);
        Assert.Contains("visible", json, StringComparison.Ordinal);
    }

    [Fact]
    public void ItStillReadsTheBareValue()
    {
        var dto = JsonSerializer.Deserialize<Dto>("{\"Q\":\"hello\",\"Plain\":\"p\"}")!;

        Assert.Equal("hello", dto.Q.Reveal());
    }

    [Fact]
    public void TheStructuredLoggerAndExceptionMessagesNeverShowTheValue()
    {
        var value = new LlmSensitive<string>(Marker);
        var dto = new Dto(value, "visible");

        var output = LogCapture.Run(log => log.Information("v {@Value} {Value} {@Dto}", value, value, dto));
        var e = new InvalidOperationException($"failed for {value} {dto}");

        Assert.DoesNotContain(Marker, output, StringComparison.Ordinal);
        Assert.DoesNotContain(Marker, e.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void AReplyWithDuplicatePropertiesIsInvalid()
    {
        const string text = "{\\\"a\\\":1,\\\"a\\\":2}";
        var body = "{\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"" + text + "\"}]}]}";

        var result = OpenAiResponsesProvider.Parse(Encoding.UTF8.GetBytes(body));

        Assert.Equal(LlmOutcome.Invalid, result.Outcome);
    }
}
