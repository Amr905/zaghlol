using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>
/// Envelope format v1 (T-123 design note; <c>security-model.md</c> §6):
/// <code>0x01 ‖ u8 len(keyRef) ‖ keyRef (ASCII) ‖ u16be len(wrappedDek) ‖ wrappedDek ‖ nonce(12) ‖ ciphertext ‖ tag(16)</code>
/// AES-256-GCM with a fresh data key per record; associated data <c>"zaghlol-env-v1" ‖ 0x00 ‖ UTF-8(context)</c>.
/// </summary>
internal sealed class EnvelopeCipher(KmsSettings settings, IDataKeyProvider provider, KmsCallPolicy policy, TimeProvider clock) : IEnvelopeCipher
{
    public const byte Version = 0x01;
    public const int NonceSize = 12;
    public const int TagSize = 16;

    private static readonly byte[] AadPrefix = [.. "zaghlol-env-v1"u8, 0x00];

    public async ValueTask<byte[]> EncryptAsync(ReadOnlyMemory<byte> plain, string context, CancellationToken cancellationToken)
    {
        var aad = AssociatedData(context);
        var keyRef = settings.EnvelopeKeyRef;
        DataKey generated;
        try
        {
            generated = await DataKeyAsync(ct => provider.GenerateDataKeyAsync(keyRef, ct), cancellationToken);
        }
        catch (CryptographicException)
        {
            // A provider's crypto exception text can name the key (T-123 code review #2): constant message, no inner exception.
            KmsMetrics.KmsUnavailable("data_key");
            throw new KmsUnavailableException();
        }

        using var dataKey = generated;

        var keyRefBytes = Encoding.ASCII.GetBytes(keyRef);
        var wrapped = dataKey.Wrapped.Span;
        var headerLength = 1 + 1 + keyRefBytes.Length + 2 + wrapped.Length;
        var blob = new byte[headerLength + NonceSize + plain.Length + TagSize];

        var offset = 0;
        blob[offset++] = Version;
        blob[offset++] = (byte)keyRefBytes.Length;
        keyRefBytes.CopyTo(blob, offset);
        offset += keyRefBytes.Length;
        BinaryPrimitives.WriteUInt16BigEndian(blob.AsSpan(offset, 2), (ushort)wrapped.Length);
        offset += 2;
        wrapped.CopyTo(blob.AsSpan(offset));
        offset += wrapped.Length;

        var nonce = blob.AsSpan(offset, NonceSize);
        RandomNumberGenerator.Fill(nonce);
        offset += NonceSize;

        using var aes = dataKey.CreateAesGcm();
        aes.Encrypt(nonce, plain.Span, blob.AsSpan(offset, plain.Length), blob.AsSpan(offset + plain.Length, TagSize), aad);
        return blob;
    }

    public async ValueTask<byte[]> DecryptAsync(ReadOnlyMemory<byte> blob, string context, CancellationToken cancellationToken)
    {
        var aad = AssociatedData(context);
        if (!TryParse(blob, out var keyRef, out var wrapped, out var nonceOffset)
            || !settings.EnvelopeDecryptKeyRefs.Contains(keyRef, StringComparer.Ordinal))
        {
            throw new EnvelopeDecryptionException();
        }

        DataKey dataKey;
        try
        {
            dataKey = await DataKeyAsync(ct => provider.DecryptDataKeyAsync(keyRef, wrapped, ct), cancellationToken);
        }
        catch (CryptographicException)
        {
            throw new EnvelopeDecryptionException();
        }

        using (dataKey)
        {
            var span = blob.Span;
            var nonce = span.Slice(nonceOffset, NonceSize);
            var cipherLength = span.Length - nonceOffset - NonceSize - TagSize;
            var cipherText = span.Slice(nonceOffset + NonceSize, cipherLength);
            var tag = span.Slice(nonceOffset + NonceSize + cipherLength, TagSize);
            var plain = new byte[cipherLength];
            try
            {
                using var aes = dataKey.CreateAesGcm();
                aes.Decrypt(nonce, cipherText, tag, plain, aad);
            }
            catch (CryptographicException)
            {
                throw new EnvelopeDecryptionException();
            }

            return plain;
        }
    }

    private static byte[] AssociatedData(string context)
    {
        ArgumentException.ThrowIfNullOrEmpty(context);
        return [.. AadPrefix, .. Encoding.UTF8.GetBytes(context)];
    }

    private static bool TryParse(ReadOnlyMemory<byte> blob, out string keyRef, out ReadOnlyMemory<byte> wrapped, out int nonceOffset)
    {
        keyRef = string.Empty;
        wrapped = ReadOnlyMemory<byte>.Empty;
        nonceOffset = 0;
        var span = blob.Span;
        if (span.Length < 2 || span[0] != Version)
        {
            return false;
        }

        var keyRefLength = span[1];
        var offset = 2;
        if (keyRefLength == 0 || span.Length < offset + keyRefLength + 2)
        {
            return false;
        }

        keyRef = Encoding.ASCII.GetString(span.Slice(offset, keyRefLength));
        offset += keyRefLength;
        var wrappedLength = BinaryPrimitives.ReadUInt16BigEndian(span.Slice(offset, 2));
        offset += 2;
        if (wrappedLength == 0 || span.Length < offset + wrappedLength + NonceSize + TagSize)
        {
            return false;
        }

        wrapped = blob.Slice(offset, wrappedLength);
        nonceOffset = offset + wrappedLength;
        return true;
    }

    private async ValueTask<DataKey> DataKeyAsync(Func<CancellationToken, ValueTask<DataKey>> call, CancellationToken cancellationToken) =>
        await KmsCall.RunAsync(policy, clock, "data_key", call, cancellationToken);
}
