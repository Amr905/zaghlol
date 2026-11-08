using System.Security.Cryptography;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>
/// An envelope data key returned by <see cref="IDataKeyProvider"/>. The plaintext is held privately, used only by
/// <see cref="EnvelopeCipher"/> for one record, and zeroed on dispose; no member returns it.
/// </summary>
public sealed class DataKey : IDisposable
{
    public const int Size = 32;

    private readonly byte[] plaintext;
    private bool disposed;

    /// <param name="plaintext">The 256-bit key. The instance takes ownership and zeroes it on dispose.</param>
    /// <param name="wrapped">The key wrapped by the KMS key-encryption key.</param>
    public DataKey(byte[] plaintext, ReadOnlyMemory<byte> wrapped)
    {
        ArgumentNullException.ThrowIfNull(plaintext);
        if (plaintext.Length != Size)
        {
            throw new ArgumentException("A data key is 32 bytes.", nameof(plaintext));
        }

        if (wrapped.IsEmpty || wrapped.Length > ushort.MaxValue)
        {
            throw new ArgumentException("The wrapped data key must be 1 to 65535 bytes.", nameof(wrapped));
        }

        this.plaintext = plaintext;
        Wrapped = wrapped;
    }

    /// <summary>The wrapped (KMS-encrypted) form, stored in the envelope.</summary>
    public ReadOnlyMemory<byte> Wrapped { get; }

    public void Dispose()
    {
        if (!disposed)
        {
            CryptographicOperations.ZeroMemory(plaintext);
            disposed = true;
        }
    }

    internal AesGcm CreateAesGcm()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        return new AesGcm(plaintext, EnvelopeCipher.TagSize);
    }
}
