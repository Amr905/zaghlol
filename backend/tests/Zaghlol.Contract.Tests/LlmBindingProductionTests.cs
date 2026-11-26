using System.Text;
using System.Text.Json;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Attestation;
using Zaghlol.Domain;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// T-336 AC1: the production <see cref="LlmBinding"/> reproduces every ask and cat vector byte for byte, from the full request
/// body (with its <c>attestation</c> member, which the binding drops) and from the vector's JCS text.
/// </summary>
public class LlmBindingProductionTests
{
    public static TheoryData<string, LlmFeature> Files => new()
    {
        { "ask-binding-v1.json", LlmFeature.Ask },
        { "cat-binding-v1.json", LlmFeature.Categorise },
    };

    [Theory]
    [MemberData(nameof(Files))]
    public void TheProductionBindingReproducesEveryVector(string file, LlmFeature feature)
    {
        var vectors = LlmContractFiles.Vectors(file);
        Assert.Equal(vectors["prefix"]!.GetValue<string>(), LlmBinding.Prefix(feature));
        Assert.Equal(vectors["clientDataPrefix"]!.GetValue<string>(), LlmBinding.ClientDataPrefix(feature));

        foreach (var vector in vectors["valid"]!.AsArray())
        {
            var install = InstallId.Parse(vector!["installId"]!.GetValue<string>());
            using var body = JsonDocument.Parse(vector["body"]!.ToJsonString());

            var jcs = LlmBinding.Canonical(body.RootElement);
            Assert.NotNull(jcs);
            Assert.Equal(vector["jcsHex"]!.GetValue<string>(), Convert.ToHexStringLower(jcs));

            var hash = LlmBinding.BodyHash(feature, install, body.RootElement);
            Assert.NotNull(hash);
            Assert.Equal(vector["bodyHashHex"]!.GetValue<string>(), Convert.ToHexStringLower(hash));
            Assert.Equal(vector["bodyHashHex"]!.GetValue<string>(), Convert.ToHexStringLower(LlmBinding.BodyHash(feature, install, Encoding.UTF8.GetBytes(vector["jcs"]!.GetValue<string>()))));
            Assert.Equal(vector["clientDataHashHex"]!.GetValue<string>(), Convert.ToHexStringLower(LlmBinding.ClientDataHash(feature, hash)));
        }
    }

    [Fact]
    public void MemberOrderWhitespaceAndIntegerSpellingDoNotChangeTheHash()
    {
        var install = InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e00");
        using var a = JsonDocument.Parse("""{"planVersion":1,"lang":"en","q":"x","attestation":{"type":"dev","proof":"aaaaaaaa"}}""");
        using var b = JsonDocument.Parse("""{ "q" : "x", "lang":"en", "planVersion": 1.0 }""");

        Assert.Equal(LlmBinding.BodyHash(LlmFeature.Ask, install, a.RootElement), LlmBinding.BodyHash(LlmFeature.Ask, install, b.RootElement));
    }

    [Theory]
    [InlineData("""{"planVersion":1.5}""")]
    [InlineData("""{"planVersion":1e300}""")]
    [InlineData("""{"q":"\ud800"}""")]
    [InlineData("""[1]""")]
    public void BodiesWithoutAnExactCanonicalFormHaveNoHash(string json)
    {
        using var body = JsonDocument.Parse(json);
        Assert.Null(LlmBinding.BodyHash(LlmFeature.Ask, InstallId.Parse("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e00"), body.RootElement));
    }
}
