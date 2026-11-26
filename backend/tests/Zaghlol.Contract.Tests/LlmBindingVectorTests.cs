using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// T-272 AC3: recomputes every binding vector of <c>ask-binding-v1.json</c> and <c>cat-binding-v1.json</c> byte for byte
/// (ask-llm.md section 5): <c>SHA-256(prefix || 0x00 || installId || 0x00 || JCS(body without attestation))</c>, the Play
/// <c>requestHash</c> and the App Attest <c>clientDataHash</c>. The Dart app reads the same files (T-290).
/// </summary>
public class LlmBindingVectorTests
{
    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    public static TheoryData<string, string> Files => new()
    {
        { "ask-binding-v1.json", "AskPlanRequest" },
        { "cat-binding-v1.json", "CategoriseRequest" },
    };

    [Theory]
    [MemberData(nameof(Files))]
    public void EveryVectorIsReproducedByteForByte(string file, string requestSchema)
    {
        var vectors = LlmContractFiles.Vectors(file);
        var prefix = vectors["prefix"]!.GetValue<string>();
        var clientDataPrefix = vectors["clientDataPrefix"]!.GetValue<string>();
        var valid = vectors["valid"]!.AsArray();
        Assert.True(valid.Count >= 5, "expected several vectors");

        foreach (var vector in valid)
        {
            var name = vector!["name"]!.GetValue<string>();
            var installId = vector["installId"]!.GetValue<string>();
            var body = JsonNode.Parse(vector["body"]!.ToJsonString())!.AsObject();

            Assert.Null(Spec.Validate(JsonNode.Parse($$"""{"$ref":"#/components/schemas/{{requestSchema}}"}""")!, body));
            Assert.True(body.Remove("attestation"), $"{name}: body has no attestation member");

            var canonical = new StringBuilder();
            WriteCanonical(body, canonical);
            Assert.Equal(vector["jcs"]!.GetValue<string>(), canonical.ToString());

            var jcsBytes = Encoding.UTF8.GetBytes(canonical.ToString());
            Assert.Equal(vector["jcsHex"]!.GetValue<string>(), Convert.ToHexStringLower(jcsBytes));

            var hash = BodyHash(prefix, installId, jcsBytes);
            Assert.Equal(vector["bodyHashHex"]!.GetValue<string>(), Convert.ToHexStringLower(hash));
            Assert.Equal(vector["requestHashB64u"]!.GetValue<string>(), Base64Url.EncodeToString(hash));

            byte[] clientData = [.. Encoding.ASCII.GetBytes(clientDataPrefix), 0, .. hash];
            Assert.Equal(vector["clientDataHashHex"]!.GetValue<string>(), Convert.ToHexStringLower(SHA256.HashData(clientData)));
        }
    }

    [Theory]
    [MemberData(nameof(Files))]
    public void TheHashIsBoundToTheInstallThePrefixAndTheBody(string file, string requestSchema)
    {
        Assert.NotEmpty(requestSchema);
        var vectors = LlmContractFiles.Vectors(file);
        var vector = vectors["valid"]!.AsArray()[0]!;
        var jcs = Encoding.UTF8.GetBytes(vector["jcs"]!.GetValue<string>());
        var expected = vector["bodyHashHex"]!.GetValue<string>();
        var prefix = vectors["prefix"]!.GetValue<string>();

        Assert.NotEqual(expected, Convert.ToHexStringLower(BodyHash(prefix, "0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e00", jcs)));
        Assert.NotEqual(expected, Convert.ToHexStringLower(BodyHash(prefix == "zaghlol-ask-v1" ? "zaghlol-cat-v1" : "zaghlol-ask-v1", vector["installId"]!.GetValue<string>(), jcs)));
        Assert.NotEqual(expected, Convert.ToHexStringLower(BodyHash(prefix, vector["installId"]!.GetValue<string>(), [.. jcs, (byte)' '])));
        Assert.NotEqual(expected, vector["clientDataHashHex"]!.GetValue<string>());
    }

    [Fact]
    public void TheAttestationBlockIsOutsideTheHash()
    {
        var vectors = LlmContractFiles.Vectors("ask-binding-v1.json");
        var first = vectors["valid"]!.AsArray()[1]!;
        var second = vectors["valid"]!.AsArray()[2]!;

        // Same question and request id, different install and a first-use attestationObject: the JCS is identical.
        Assert.Equal(first["jcs"]!.GetValue<string>(), second["jcs"]!.GetValue<string>());
        Assert.NotEqual(first["bodyHashHex"]!.GetValue<string>(), second["bodyHashHex"]!.GetValue<string>());
        Assert.NotNull(first["body"]!["attestation"]!["attestationObject"]);
        Assert.Null(second["body"]!["attestation"]!["attestationObject"]);
    }

    /// <summary>RFC 8785 for the value kinds the vectors use (objects, arrays, strings, booleans, null, integers).</summary>
    private static void WriteCanonical(JsonNode? node, StringBuilder output)
    {
        switch (node)
        {
            case null:
                output.Append("null");
                break;
            case JsonObject members:
                output.Append('{');
                var first = true;
                foreach (var member in members.OrderBy(m => m.Key, StringComparer.Ordinal))
                {
                    if (!first)
                    {
                        output.Append(',');
                    }

                    first = false;
                    WriteString(member.Key, output);
                    output.Append(':');
                    WriteCanonical(member.Value, output);
                }

                output.Append('}');
                break;
            case JsonArray items:
                output.Append('[');
                for (var i = 0; i < items.Count; i++)
                {
                    if (i > 0)
                    {
                        output.Append(',');
                    }

                    WriteCanonical(items[i], output);
                }

                output.Append(']');
                break;
            case JsonValue value when value.TryGetValue<string>(out var text):
                WriteString(text, output);
                break;
            case JsonValue value when value.TryGetValue<bool>(out var flag):
                output.Append(flag ? "true" : "false");
                break;
            case JsonValue value when value.TryGetValue<long>(out var number):
                output.Append(number.ToString(System.Globalization.CultureInfo.InvariantCulture));
                break;
            default:
                throw new InvalidOperationException("The LLM binding vectors use only strings, booleans and integers.");
        }
    }

    private static void WriteString(string text, StringBuilder output)
    {
        output.Append('"');
        foreach (var c in text)
        {
            switch (c)
            {
                case '"':
                    output.Append("\\\"");
                    break;
                case '\\':
                    output.Append("\\\\");
                    break;
                case '\b':
                    output.Append("\\b");
                    break;
                case '\f':
                    output.Append("\\f");
                    break;
                case '\n':
                    output.Append("\\n");
                    break;
                case '\r':
                    output.Append("\\r");
                    break;
                case '\t':
                    output.Append("\\t");
                    break;
                case < ' ':
                    output.Append("\\u").Append(((int)c).ToString("x4", System.Globalization.CultureInfo.InvariantCulture));
                    break;
                default:
                    output.Append(c);
                    break;
            }
        }

        output.Append('"');
    }

    private static byte[] BodyHash(string prefix, string installId, byte[] jcs) =>
        SHA256.HashData([.. Encoding.UTF8.GetBytes(prefix), 0, .. Encoding.ASCII.GetBytes(installId), 0, .. jcs]);
}
