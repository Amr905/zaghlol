using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>
/// The development KMS (<c>Kms:Provider = Local</c>): keys are files in <c>Kms:Local:KeyDirectory</c> made by
/// <c>backend/tools/dev-keys.sh</c>. <c>local:&lt;name&gt;</c> is <c>&lt;name&gt;.pem</c> (a P-256 private key) or
/// <c>&lt;name&gt;.key</c> (32 random bytes, base64). Allowed only in Development and Testing (fail closed). Keys are read
/// per call and never cached.
/// </summary>
internal sealed partial class LocalKms(string keyDirectory) : ISigningKeyProvider, IHmacProvider, IDataKeyProvider
{
    public const string Prefix = "local:";

    private const string P256Oid = "1.2.840.10045.3.1.7";
    private const int WrappedSize = EnvelopeCipher.NonceSize + DataKey.Size + EnvelopeCipher.TagSize;

    public ValueTask<byte[]> SignDigestAsync(string keyRef, ReadOnlyMemory<byte> sha256, CancellationToken cancellationToken)
    {
        using var key = LoadEc(keyRef);
        return ValueTask.FromResult(key.SignHash(sha256.Span, DSASignatureFormat.IeeeP1363FixedFieldConcatenation));
    }

    public ValueTask<byte[]> GetPublicKeyAsync(string keyRef, CancellationToken cancellationToken)
    {
        using var key = LoadEc(keyRef);
        var q = key.ExportParameters(includePrivateParameters: false).Q;
        return ValueTask.FromResult<byte[]>([0x04, .. q.X!, .. q.Y!]);
    }

    public ValueTask<byte[]> HmacSha256Async(string keyRef, ReadOnlyMemory<byte> data, CancellationToken cancellationToken)
    {
        var secret = LoadSymmetric(keyRef);
        try
        {
            return ValueTask.FromResult(HMACSHA256.HashData(secret, data.Span));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(secret);
        }
    }

    public ValueTask<DataKey> GenerateDataKeyAsync(string keyRef, CancellationToken cancellationToken)
    {
        var kek = LoadSymmetric(keyRef);
        try
        {
            var plaintext = RandomNumberGenerator.GetBytes(DataKey.Size);
            var wrapped = new byte[WrappedSize];
            var nonce = wrapped.AsSpan(0, EnvelopeCipher.NonceSize);
            RandomNumberGenerator.Fill(nonce);
            using var aes = new AesGcm(kek, EnvelopeCipher.TagSize);
            aes.Encrypt(
                nonce,
                plaintext,
                wrapped.AsSpan(EnvelopeCipher.NonceSize, DataKey.Size),
                wrapped.AsSpan(EnvelopeCipher.NonceSize + DataKey.Size),
                WrapAad(keyRef));
            return ValueTask.FromResult(new DataKey(plaintext, wrapped));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(kek);
        }
    }

    public ValueTask<DataKey> DecryptDataKeyAsync(string keyRef, ReadOnlyMemory<byte> wrapped, CancellationToken cancellationToken)
    {
        if (wrapped.Length != WrappedSize)
        {
            throw new CryptographicException();
        }

        var kek = LoadSymmetric(keyRef);
        try
        {
            var span = wrapped.Span;
            var plaintext = new byte[DataKey.Size];
            using var aes = new AesGcm(kek, EnvelopeCipher.TagSize);
            aes.Decrypt(
                span[..EnvelopeCipher.NonceSize],
                span.Slice(EnvelopeCipher.NonceSize, DataKey.Size),
                span[(EnvelopeCipher.NonceSize + DataKey.Size)..],
                plaintext,
                WrapAad(keyRef));
            return ValueTask.FromResult(new DataKey(plaintext, wrapped.ToArray()));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(kek);
        }
    }

    [GeneratedRegex("^[a-z0-9][a-z0-9-]{0,62}\\z", RegexOptions.CultureInvariant)]
    private static partial Regex NamePattern();

    private static byte[] WrapAad(string keyRef) => [.. "zaghlol-local-wrap-v1"u8, 0x00, .. Encoding.ASCII.GetBytes(keyRef)];

    private string PathFor(string keyRef, string extension)
    {
        if (!keyRef.StartsWith(Prefix, StringComparison.Ordinal) || !NamePattern().IsMatch(keyRef[Prefix.Length..]))
        {
            throw new KmsConfigurationException("A Local KMS key reference must look like local:<name> (a-z, 0-9, '-').");
        }

        return Path.Combine(keyDirectory, keyRef[Prefix.Length..] + extension);
    }

    private ECDsa LoadEc(string keyRef)
    {
        var pem = Read(PathFor(keyRef, ".pem"));
        var key = ECDsa.Create();
        try
        {
            key.ImportFromPem(pem);
            if (!string.Equals(key.ExportParameters(includePrivateParameters: false).Curve.Oid.Value, P256Oid, StringComparison.Ordinal))
            {
                throw new KmsConfigurationException("A Local KMS signing key is not a P-256 key.");
            }

            return key;
        }
        catch (Exception ex) when (ex is ArgumentException or CryptographicException)
        {
            key.Dispose();
            throw new KmsConfigurationException("A Local KMS signing key file is not a PEM EC private key.");
        }
        catch
        {
            key.Dispose();
            throw;
        }
    }

    private byte[] LoadSymmetric(string keyRef)
    {
        byte[] secret;
        try
        {
            secret = Convert.FromBase64String(Read(PathFor(keyRef, ".key")).Trim());
        }
        catch (FormatException)
        {
            throw new KmsConfigurationException("A Local KMS symmetric key file is not base64.");
        }

        if (secret.Length != 32)
        {
            CryptographicOperations.ZeroMemory(secret);
            throw new KmsConfigurationException("A Local KMS symmetric key must be 32 bytes.");
        }

        return secret;
    }

    private static string Read(string path)
    {
        try
        {
            return File.ReadAllText(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // The message would carry the path, which names the key: keep it out of logs.
            throw new KmsConfigurationException("A Local KMS key file is missing or unreadable.");
        }
    }
}
