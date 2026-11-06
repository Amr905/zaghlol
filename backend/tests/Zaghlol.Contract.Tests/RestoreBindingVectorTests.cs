using System.Buffers.Text;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// Checks the shared vectors for the install-bound restore hash (backend-api.md section 4.3 step 1, ADR-012
/// Part B (d)): <c>SHA-256(prefix || 0x00 || installId || 0x00 || JCS(body without attestation))</c>. The Dart
/// app and the .NET API must both reproduce these vectors, so the file is the single reference for both.
/// </summary>
public class RestoreBindingVectorTests
{
    private static readonly JsonObject Vectors = LoadVectors();

    [Fact]
    public void ValidVectorsHashTheCanonicalBodyBoundToTheInstall()
    {
        var prefix = Vectors["prefix"]!.GetValue<string>();
        var valid = Vectors["valid"]!.AsArray();
        Assert.NotEmpty(valid);

        foreach (var vector in valid)
        {
            var name = vector!["name"]!.GetValue<string>();
            var installId = vector["installId"]!.GetValue<string>();
            var expectedJcs = vector["jcs"]!.GetValue<string>();

            var body = JsonNode.Parse(vector["body"]!.ToJsonString())!.AsObject();
            Assert.True(body.Remove("attestation"), $"{name}: body has no attestation member");

            var canonical = new StringBuilder();
            WriteCanonical(body, canonical);
            Assert.Equal(expectedJcs, canonical.ToString());

            byte[] message = [.. Encoding.UTF8.GetBytes(prefix), 0, .. Encoding.ASCII.GetBytes(installId), 0, .. Encoding.UTF8.GetBytes(expectedJcs)];
            var hash = SHA256.HashData(message);

            Assert.Equal(vector["bodyHashHex"]!.GetValue<string>(), Convert.ToHexStringLower(hash));
            Assert.Equal(vector["requestHashB64u"]!.GetValue<string>(), Base64Url.EncodeToString(hash));
        }
    }

    /// <summary>
    /// R4-1(3): on iOS the App Attest <c>clientDataHash</c> also covers the seat-key public keys, which stay outside
    /// <c>bodyHash</c>: <c>SHA-256(clientDataPrefix || 0x00 || bodyHash || SHA-256(pk_0 || ... || pk_n-1))</c>.
    /// </summary>
    [Fact]
    public void IosClientDataHashCoversTheSeatPublicKeysInOrder()
    {
        var clientDataPrefix = Vectors["clientDataPrefix"]!.GetValue<string>();
        var ios = Vectors["valid"]!.AsArray()
            .Where(v => v!["body"]!["platform"]!.GetValue<string>() == "ios")
            .ToList();
        Assert.True(ios.Count >= 3, "expected iOS vectors without, with one and with two seat keys");

        foreach (var vector in ios)
        {
            var name = vector!["name"]!.GetValue<string>();
            var keys = vector["body"]!["attestation"]!["seatKeys"]?.AsArray() ?? new JsonArray();
            var points = keys.SelectMany(k => Base64Url.DecodeFromChars(k!["publicKey"]!.GetValue<string>())).ToArray();
            Assert.True(65 * keys.Count == points.Length, $"{name}: seat keys are not 65-byte points");

            var digest = SHA256.HashData(points);
            Assert.Equal(vector["seatKeysDigestHex"]!.GetValue<string>(), Convert.ToHexStringLower(digest));

            byte[] clientData = [.. Encoding.ASCII.GetBytes(clientDataPrefix), 0, .. Convert.FromHexString(vector["bodyHashHex"]!.GetValue<string>()), .. digest];
            Assert.Equal(vector["clientDataHashHex"]!.GetValue<string>(), Convert.ToHexStringLower(SHA256.HashData(clientData)));

            if (keys.Count > 1)
            {
                // Reordering the keys must change the hash the assertion signs.
                var reversed = keys.Reverse().SelectMany(k => Base64Url.DecodeFromChars(k!["publicKey"]!.GetValue<string>())).ToArray();
                Assert.False(digest.AsSpan().SequenceEqual(SHA256.HashData(reversed)), $"{name}: key order not covered");
            }
        }
    }

    [Fact]
    public void TheSameBodyGivesADifferentHashOnAnotherInstall()
    {
        var prefix = Vectors["prefix"]!.GetValue<string>();
        var vector = Vectors["valid"]!.AsArray()[0]!;
        var jcs = vector["jcs"]!.GetValue<string>();

        byte[] other = [.. Encoding.UTF8.GetBytes(prefix), 0, .. Encoding.ASCII.GetBytes("0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e78"), 0, .. Encoding.UTF8.GetBytes(jcs)];

        Assert.NotEqual(vector["bodyHashHex"]!.GetValue<string>(), Convert.ToHexStringLower(SHA256.HashData(other)));
    }

    [Fact]
    public void InvalidVectorsAreRejectedByAStrictParse()
    {
        var invalid = Vectors["invalid"]!.AsArray();
        Assert.NotEmpty(invalid);

        foreach (var vector in invalid)
        {
            var raw = vector!["raw"]!.GetValue<string>();
            Assert.True(IsRejectedByStrictParse(raw), $"{vector["name"]!.GetValue<string>()}: accepted by the strict parse");
        }
    }

    /// <summary>
    /// R3-8: production rejection of duplicate member names must be explicit, because System.Text.Json accepts them by
    /// default (last one wins). .NET 10's <c>AllowDuplicateProperties = false</c> must reject every duplicate vector,
    /// at any depth, including inside <c>attestation</c>, which is excluded from the hash but bound to the DTO.
    /// </summary>
    [Fact]
    public void DuplicateVectorsAreRejectedByTheFrameworkStrictOption()
    {
        var duplicates = Vectors["invalid"]!.AsArray()
            .Where(v => v!["name"]!.GetValue<string>().StartsWith("duplicate-", StringComparison.Ordinal))
            .ToList();
        Assert.True(duplicates.Count >= 3, "expected top-level and nested duplicate vectors");

        var options = new JsonDocumentOptions { AllowDuplicateProperties = false };
        foreach (var vector in duplicates)
        {
            var raw = vector!["raw"]!.GetValue<string>();
            Assert.ThrowsAny<JsonException>(() => JsonDocument.Parse(raw, options).Dispose());
        }
    }

    /// <summary>RFC 8785 for the value kinds the vectors use (objects, arrays, strings, booleans, null).</summary>
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
            default:
                throw new InvalidOperationException("The restore vectors use no numbers.");
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
                default:
                    if (c < ' ')
                    {
                        output.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                    }
                    else
                    {
                        output.Append(c);
                    }

                    break;
            }
        }

        output.Append('"');
    }

    /// <summary>Duplicate member names and lone UTF-16 surrogates must fail (backend-api.md section 4.3 step 1).</summary>
    private static bool IsRejectedByStrictParse(string raw)
    {
        try
        {
            var reader = new Utf8JsonReader(Encoding.UTF8.GetBytes(raw));
            var names = new Stack<HashSet<string>>();
            while (reader.Read())
            {
                switch (reader.TokenType)
                {
                    case JsonTokenType.StartObject:
                        names.Push(new HashSet<string>(StringComparer.Ordinal));
                        break;
                    case JsonTokenType.EndObject:
                        names.Pop();
                        break;
                    case JsonTokenType.PropertyName:
                        var name = reader.GetString()!;
                        if (HasLoneSurrogate(name) || !names.Peek().Add(name))
                        {
                            return true;
                        }

                        break;
                    case JsonTokenType.String:
                        if (HasLoneSurrogate(reader.GetString()!))
                        {
                            return true;
                        }

                        break;
                    default:
                        break;
                }
            }

            return false;
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException)
        {
            return true;
        }
    }

    private static bool HasLoneSurrogate(string text)
    {
        for (var i = 0; i < text.Length; i++)
        {
            if (char.IsHighSurrogate(text[i]) && i + 1 < text.Length && char.IsLowSurrogate(text[i + 1]))
            {
                i++;
            }
            else if (char.IsSurrogate(text[i]))
            {
                return true;
            }
        }

        return false;
    }

    private static JsonObject LoadVectors()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "vectors", "restore-binding-v1.json");
        return JsonNode.Parse(File.ReadAllText(path))!.AsObject();
    }
}
