using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.Kms;

// Exception messages are constants: they never include a key reference, data or a nonce (T-123 design note).

/// <summary>The KMS could not sign, hash or unwrap in time (after one retry). Mapped to <c>503 UPSTREAM_UNAVAILABLE</c>.</summary>
public sealed class KmsUnavailableException : SafeException
{
    public const string DefaultMessage = "The key management service is unavailable.";

    public KmsUnavailableException()
        : base(DefaultMessage)
    {
    }

    public KmsUnavailableException(string message)
        : base(message)
    {
    }

    public KmsUnavailableException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>The KMS provider or key ring is misconfigured; the process refuses to start.</summary>
public sealed class KmsConfigurationException : SafeException
{
    public const string DefaultMessage = "The KMS configuration is invalid.";

    public KmsConfigurationException()
        : base(DefaultMessage)
    {
    }

    public KmsConfigurationException(string message)
        : base(message)
    {
    }

    public KmsConfigurationException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>An envelope blob is malformed, tampered with, or bound to another context.</summary>
public sealed class EnvelopeDecryptionException : SafeException
{
    public const string DefaultMessage = "The envelope could not be decrypted.";

    public EnvelopeDecryptionException()
        : base(DefaultMessage)
    {
    }

    public EnvelopeDecryptionException(string message)
        : base(message)
    {
    }

    public EnvelopeDecryptionException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
