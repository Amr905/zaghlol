using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Zaghlol.Application.Seats.SeatKeys;
using Zaghlol.Domain;

namespace Zaghlol.Application.Purchases.Restore;

/// <summary>
/// Strict parse, single binding and the install-bound hash of a restore body (backend-api §4.3 step 1, R2-1, R2-6, R3-8; T-185
/// design note §1). The body is parsed <b>once</b> into a <see cref="JsonDocument"/> with duplicate member names refused at every
/// depth (<see cref="JsonDocumentOptions.AllowDuplicateProperties"/> = false) and every string and member name checked for lone
/// surrogates. The request model is bound from that same element tree, and <c>JCS</c> (RFC 8785) is written from it too, so the
/// hashed and the processed body can't differ. Problems never echo the input. No cryptography is written here: the hash is
/// SHA-256 over the documented message.
/// </summary>
public static partial class RestoreRequestParser
{
    public const string BodyHashPrefix = "zaghlol-restore-v1";
    public const string ClientDataPrefix = "zaghlol-restore-attest-v1";
    public const int MaxItems = 20;
    private const int MaxDepth = 32;

    public static RestoreParseResult Parse(ReadOnlyMemory<byte> utf8, InstallId installId)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(utf8, new JsonDocumentOptions { AllowDuplicateProperties = false, MaxDepth = MaxDepth });
        }
        catch (JsonException)
        {
            return Fail(RestoreParseFailure.ValidationFailed);
        }

        using (document)
        {
            var root = document.RootElement;
            try
            {
                if (HasLoneSurrogate(root))
                {
                    return Fail(RestoreParseFailure.ValidationFailed);
                }

                if (root.ValueKind != JsonValueKind.Object)
                {
                    return Fail(RestoreParseFailure.ValidationFailed);
                }

                var platform = root.TryGetProperty("platform", out var p) && p.ValueKind == JsonValueKind.String ? p.GetString() : null;
                if (platform is not (RestorePlatforms.Android or RestorePlatforms.Ios))
                {
                    return Fail(RestoreParseFailure.ValidationFailed);
                }

                var android = platform == RestorePlatforms.Android;
                if (HasUnknownMember(root, android))
                {
                    return Fail(RestoreParseFailure.UnknownField);
                }

                return android ? BindAndroid(root, installId) : BindIos(root, installId);
            }
            catch (InvalidOperationException)
            {
                // A string the reader can't turn into UTF-16 (a lone surrogate escape): refuse, never echo.
                return Fail(RestoreParseFailure.ValidationFailed);
            }
        }
    }

    /// <summary><c>SHA-256(clientDataPrefix ‖ 0x00 ‖ bodyHash ‖ seatKeysDigest)</c> (R4-1(3)), the App Attest <c>clientDataHash</c>.</summary>
    public static byte[] ClientDataHash(ReadOnlySpan<byte> bodyHash, ReadOnlySpan<byte> seatKeysDigest)
    {
        using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        sha.AppendData(Encoding.ASCII.GetBytes(ClientDataPrefix));
        sha.AppendData([0]);
        sha.AppendData(bodyHash);
        sha.AppendData(seatKeysDigest);
        return sha.GetHashAndReset();
    }

    private static RestoreParseResult BindAndroid(JsonElement root, InstallId installId)
    {
        if (!root.TryGetProperty("purchases", out var purchases)
            || !root.TryGetProperty("attestation", out var attestation)
            || purchases.ValueKind != JsonValueKind.Array
            || attestation.ValueKind != JsonValueKind.Object
            || purchases.GetArrayLength() is < 1 or > MaxItems)
        {
            return Fail(RestoreParseFailure.ValidationFailed);
        }

        var items = new List<PlayPurchaseRef>();
        foreach (var item in purchases.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.Object
                || String(item, "productId") is not { } productId || !ProductId().IsMatch(productId)
                || String(item, "purchaseToken") is not { Length: > 0 and <= 512 } token)
            {
                return Fail(RestoreParseFailure.ValidationFailed);
            }

            items.Add(new PlayPurchaseRef(productId, new Sensitive<string>(token)));
        }

        if (String(attestation, "type") != "play_integrity"
            || attestation.TryGetProperty("seatKeys", out _)
            || String(attestation, "token") is not { } integrity || !IntegrityToken().IsMatch(integrity))
        {
            return Fail(RestoreParseFailure.ValidationFailed);
        }

        if (Hash(root, installId) is not { } bodyHash)
        {
            return Fail(RestoreParseFailure.ValidationFailed);
        }

        return new RestoreParseResult(
            new AndroidRestoreRequest { Purchases = items, IntegrityToken = new Sensitive<string>(integrity), BodyHash = bodyHash },
            null);
    }

    private static RestoreParseResult BindIos(JsonElement root, InstallId installId)
    {
        if (!root.TryGetProperty("signedTransactions", out var transactions)
            || !root.TryGetProperty("attestation", out var attestation)
            || transactions.ValueKind != JsonValueKind.Array
            || attestation.ValueKind != JsonValueKind.Object
            || transactions.GetArrayLength() is < 1 or > MaxItems)
        {
            return Fail(RestoreParseFailure.ValidationFailed);
        }

        var signed = new List<Sensitive<string>>();
        foreach (var item in transactions.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.String || item.GetString() is not { Length: > 0 } jws)
            {
                return Fail(RestoreParseFailure.ValidationFailed);
            }

            signed.Add(new Sensitive<string>(jws));
        }

        if (String(attestation, "type") != "app_attest"
            || String(attestation, "keyId") is not { } keyText || !KeyId().IsMatch(keyText) || Decode(keyText) is not { Length: 32 } keyId
            || String(attestation, "assertion") is not { } assertionText || !Assertion().IsMatch(assertionText) || Decode(assertionText) is not { } assertion)
        {
            return Fail(RestoreParseFailure.ValidationFailed);
        }

        byte[]? attestationObject = null;
        if (attestation.TryGetProperty("attestationObject", out var objectElement))
        {
            if (objectElement.ValueKind != JsonValueKind.String
                || objectElement.GetString() is not { } objectText || !AttestationObject().IsMatch(objectText)
                || Decode(objectText) is not { } decoded)
            {
                return Fail(RestoreParseFailure.ValidationFailed);
            }

            attestationObject = decoded;
        }

        List<SeatKeyProofInput>? seatKeys = null;
        if (attestation.TryGetProperty("seatKeys", out var keys))
        {
            if (keys.ValueKind != JsonValueKind.Array)
            {
                return Fail(RestoreParseFailure.ValidationFailed);
            }

            seatKeys = [];
            foreach (var key in keys.EnumerateArray())
            {
                if (key.ValueKind != JsonValueKind.Object || String(key, "publicKey") is not { } publicKey || String(key, "signature") is not { } signature)
                {
                    return Fail(RestoreParseFailure.ValidationFailed);
                }

                seatKeys.Add(new SeatKeyProofInput(publicKey, signature));
            }
        }

        if (Hash(root, installId) is not { } bodyHash)
        {
            return Fail(RestoreParseFailure.ValidationFailed);
        }

        return new RestoreParseResult(
            new IosRestoreRequest
            {
                SignedTransactions = signed,
                KeyId = keyId,
                Assertion = assertion,
                AttestationObject = attestationObject,
                SeatKeys = seatKeys,
                BodyHash = bodyHash,
            },
            null);
    }

    /// <summary>The install-bound hash over the JCS of the already-bound tree minus the top-level <c>attestation</c>.</summary>
    private static byte[]? Hash(JsonElement root, InstallId installId)
    {
        var jcs = new StringBuilder();
        if (!WriteCanonical(root, jcs, skipAttestation: true))
        {
            return null;
        }

        using var sha = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        sha.AppendData(Encoding.ASCII.GetBytes(BodyHashPrefix));
        sha.AppendData([0]);
        sha.AppendData(Encoding.ASCII.GetBytes(installId.Value.ToString("D")));
        sha.AppendData([0]);
        sha.AppendData(Encoding.UTF8.GetBytes(jcs.ToString()));
        return sha.GetHashAndReset();
    }

    /// <summary>
    /// RFC 8785 for the kinds a valid restore body holds: objects (members in UTF-16 code-unit order), arrays and strings. A
    /// number, boolean or null never survives binding, so meeting one means the body isn't a restore body.
    /// </summary>
    private static bool WriteCanonical(JsonElement element, StringBuilder output, bool skipAttestation)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Object:
                output.Append('{');
                var first = true;
                foreach (var member in element.EnumerateObject().Where(m => !(skipAttestation && m.Name == "attestation")).OrderBy(m => m.Name, StringComparer.Ordinal))
                {
                    if (!first)
                    {
                        output.Append(',');
                    }

                    first = false;
                    WriteString(member.Name, output);
                    output.Append(':');
                    if (!WriteCanonical(member.Value, output, skipAttestation: false))
                    {
                        return false;
                    }
                }

                output.Append('}');
                return true;

            case JsonValueKind.Array:
                output.Append('[');
                var index = 0;
                foreach (var item in element.EnumerateArray())
                {
                    if (index++ > 0)
                    {
                        output.Append(',');
                    }

                    if (!WriteCanonical(item, output, skipAttestation: false))
                    {
                        return false;
                    }
                }

                output.Append(']');
                return true;

            case JsonValueKind.String:
                WriteString(element.GetString()!, output);
                return true;

            default:
                return false;
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
                        output.Append("\\u").Append(((int)c).ToString("x4", System.Globalization.CultureInfo.InvariantCulture));
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

    private static bool HasLoneSurrogate(JsonElement element)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.String:
                return HasLoneSurrogate(element.GetString()!);
            case JsonValueKind.Array:
                return element.EnumerateArray().Any(HasLoneSurrogate);
            case JsonValueKind.Object:
                return element.EnumerateObject().Any(m => HasLoneSurrogate(m.Name) || HasLoneSurrogate(m.Value));
            default:
                return false;
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

    /// <summary>True when any object at any depth has a member the platform's schema doesn't declare.</summary>
    private static bool HasUnknownMember(JsonElement root, bool android)
    {
        if (Unknown(root, android ? ["platform", "purchases", "attestation"] : ["platform", "signedTransactions", "attestation"]))
        {
            return true;
        }

        if (android && root.TryGetProperty("purchases", out var list) && list.ValueKind == JsonValueKind.Array
            && list.EnumerateArray().Any(i => Unknown(i, ["productId", "purchaseToken"])))
        {
            return true;
        }

        if (root.TryGetProperty("attestation", out var attestation))
        {
            // Android's `seatKeys` is a validation failure of its own (iOS installs only), not an unknown member.
            if (Unknown(attestation, android ? ["type", "token", "seatKeys"] : ["type", "keyId", "assertion", "attestationObject", "seatKeys"]))
            {
                return true;
            }

            if (!android && attestation.ValueKind == JsonValueKind.Object && attestation.TryGetProperty("seatKeys", out var keys)
                && keys.ValueKind == JsonValueKind.Array && keys.EnumerateArray().Any(k => Unknown(k, ["publicKey", "signature"])))
            {
                return true;
            }
        }

        return false;
    }

    private static bool Unknown(JsonElement element, string[] known) =>
        element.ValueKind == JsonValueKind.Object && element.EnumerateObject().Any(m => !known.Contains(m.Name, StringComparer.Ordinal));

    private static string? String(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static byte[]? Decode(string base64)
    {
        var buffer = new byte[(base64.Length / 4 * 3) + 3];
        return Convert.TryFromBase64String(base64, buffer, out var written) ? buffer[..written] : null;
    }

    private static RestoreParseResult Fail(RestoreParseFailure failure) => new(null, failure);

    [GeneratedRegex(@"^[a-z0-9_.]{3,100}\z", RegexOptions.CultureInvariant)]
    private static partial Regex ProductId();

    [GeneratedRegex(@"^[A-Za-z0-9_.-]{16,16384}\z", RegexOptions.CultureInvariant)]
    private static partial Regex IntegrityToken();

    [GeneratedRegex(@"^[A-Za-z0-9+/]{43}=\z", RegexOptions.CultureInvariant)]
    private static partial Regex KeyId();

    [GeneratedRegex(@"^[A-Za-z0-9+/]{16,8192}={0,2}\z", RegexOptions.CultureInvariant)]
    private static partial Regex Assertion();

    [GeneratedRegex(@"^[A-Za-z0-9+/]{16,16384}={0,2}\z", RegexOptions.CultureInvariant)]
    private static partial Regex AttestationObject();
}
