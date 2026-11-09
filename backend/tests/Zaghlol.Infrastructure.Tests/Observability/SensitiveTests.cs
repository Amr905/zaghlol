using System.Text.Json;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Infrastructure.Tests.Observability;

public sealed class SensitiveTests
{
    private const string Secret = "ZgHlSentinelQ7x2Vn9w";

    private static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);

    private sealed record Body(Sensitive<string> OrderId, Sensitive<string[]> SeatKeys, string Plain);

    [Fact]
    public void ToStringAndInterpolationNeverShowTheValue()
    {
        var value = new Sensitive<string>(Secret);

        Assert.Equal("***", value.ToString());
        Assert.Equal("***", $"{value}");
        Assert.Equal(Secret, value.Reveal());
    }

    [Fact]
    public void ARecordThatHoldsSensitiveMembersPrintsStars()
    {
        var body = new Body(new Sensitive<string>(Secret), new Sensitive<string[]>([Secret]), "visible");

        var text = body.ToString();

        Assert.DoesNotContain(Secret, text, StringComparison.Ordinal);
        Assert.Contains("***", text, StringComparison.Ordinal);
        Assert.Contains("visible", text, StringComparison.Ordinal);
    }

    [Fact]
    public void JsonReadsTheBareValue()
    {
        var body = JsonSerializer.Deserialize<Body>(
            "{\"orderId\":\"" + Secret + "\",\"seatKeys\":[\"" + Secret + "\",\"b\"],\"plain\":\"p\"}",
            Web)!;

        Assert.Equal(Secret, body.OrderId.Reveal());
        Assert.Equal([Secret, "b"], body.SeatKeys.Reveal());
        Assert.Equal("p", body.Plain);
        Assert.DoesNotContain(Secret, body.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void ErrorsThatCarryOnlyConstantMessagesAreSafeExceptions()
    {
        Assert.IsAssignableFrom<SafeException>(new KmsUnavailableException());
        Assert.IsAssignableFrom<SafeException>(new KmsConfigurationException());
        Assert.IsAssignableFrom<SafeException>(new EnvelopeDecryptionException());
    }
}
