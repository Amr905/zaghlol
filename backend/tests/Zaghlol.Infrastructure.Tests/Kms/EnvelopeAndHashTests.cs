using System.Buffers.Binary;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.DependencyInjection;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Infrastructure.Tests.Kms;

/// <summary>T-123: envelope format v1 and the keyed hasher.</summary>
public class EnvelopeAndHashTests
{
    private const string Context = "idempotency_records:01JZAGHLOLTESTINSTALL00000:verifyPurchase:01JZAGHLOLTESTKEY000000000";
    private static readonly byte[] Plain = Encoding.UTF8.GetBytes("{\"entitlement\":\"synthetic test body\"}");

    [Fact]
    public async Task AnEnvelopeRoundTripsAndHasTheV1Layout()
    {
        using var kms = FakeKms.CreateDefault();
        await using var services = kms.BuildServices();
        var cipher = services.GetRequiredService<IEnvelopeCipher>();

        var blob = await cipher.EncryptAsync(Plain, Context, CancellationToken.None);

        Assert.Equal(Plain, await cipher.DecryptAsync(blob, Context, CancellationToken.None));
        Assert.Equal(0x01, blob[0]);
        var keyRefLength = blob[1];
        Assert.Equal(kms.EnvelopeKeyRef, Encoding.ASCII.GetString(blob, 2, keyRefLength));
        var wrappedLength = BinaryPrimitives.ReadUInt16BigEndian(blob.AsSpan(2 + keyRefLength, 2));
        Assert.Equal(2 + keyRefLength + 2 + wrappedLength + 12 + Plain.Length + 16, blob.Length);
        Assert.Equal(-1, blob.AsSpan().IndexOf(Plain));
    }

    [Fact]
    public async Task EachRecordGetsAFreshDataKeyAndNonce()
    {
        using var kms = FakeKms.CreateDefault();
        await using var services = kms.BuildServices();
        var cipher = services.GetRequiredService<IEnvelopeCipher>();

        var first = await cipher.EncryptAsync(Plain, Context, CancellationToken.None);
        var second = await cipher.EncryptAsync(Plain, Context, CancellationToken.None);

        Assert.NotEqual(first, second);
    }

    [Theory]
    [InlineData("idempotency_records:01JZAGHLOLTESTINSTALL00001:verifyPurchase:01JZAGHLOLTESTKEY000000000")]
    [InlineData("accounts:apple_refresh_token")]
    public async Task ACiphertextCopiedToAnotherRowDoesNotDecrypt(string otherContext)
    {
        using var kms = FakeKms.CreateDefault();
        await using var services = kms.BuildServices();
        var cipher = services.GetRequiredService<IEnvelopeCipher>();
        var blob = await cipher.EncryptAsync(Plain, Context, CancellationToken.None);

        var error = await Assert.ThrowsAsync<EnvelopeDecryptionException>(async () => await cipher.DecryptAsync(blob, otherContext, CancellationToken.None));
        Assert.Equal(EnvelopeDecryptionException.DefaultMessage, error.Message);
    }

    [Fact]
    public async Task EveryTamperedByteAndEveryTruncationIsRejected()
    {
        using var kms = FakeKms.CreateDefault();
        await using var services = kms.BuildServices();
        var cipher = services.GetRequiredService<IEnvelopeCipher>();
        var blob = await cipher.EncryptAsync(Plain, Context, CancellationToken.None);

        for (var i = 0; i < blob.Length; i++)
        {
            var tampered = blob.ToArray();
            tampered[i] ^= 0x01;
            await Assert.ThrowsAsync<EnvelopeDecryptionException>(async () => await cipher.DecryptAsync(tampered, Context, CancellationToken.None));
        }

        foreach (var length in new[] { 0, 1, 2, 10, blob.Length - 1 })
        {
            await Assert.ThrowsAsync<EnvelopeDecryptionException>(async () => await cipher.DecryptAsync(blob.AsMemory(0, length), Context, CancellationToken.None));
        }
    }

    [Fact]
    public async Task AfterKeyRotationOldEnvelopesStillDecryptAndUnlistedKeysDoNot()
    {
        using var kms = FakeKms.CreateDefault();
        byte[] old;
        await using (var services = kms.BuildServices())
        {
            old = await services.GetRequiredService<IEnvelopeCipher>().EncryptAsync(Plain, Context, CancellationToken.None);
        }

        kms.PreviousEnvelopeKeyRefs.Add(kms.EnvelopeKeyRef);
        kms.EnvelopeKeyRef = "fake:envelope-2";
        kms.AddSecret(kms.EnvelopeKeyRef, RandomNumberGenerator.GetBytes(32));
        await using (var services = kms.BuildServices())
        {
            var cipher = services.GetRequiredService<IEnvelopeCipher>();
            Assert.Equal(Plain, await cipher.DecryptAsync(old, Context, CancellationToken.None));
            var fresh = await cipher.EncryptAsync(Plain, Context, CancellationToken.None);
            Assert.Equal("fake:envelope-2", Encoding.ASCII.GetString(fresh, 2, fresh[1]));
        }

        // Once the old key is dropped from configuration, its envelopes are refused before any KMS call.
        kms.PreviousEnvelopeKeyRefs.Clear();
        await using (var services = kms.BuildServices())
        {
            var calls = kms.Calls;
            await Assert.ThrowsAsync<EnvelopeDecryptionException>(async () =>
                await services.GetRequiredService<IEnvelopeCipher>().DecryptAsync(old, Context, CancellationToken.None));
            Assert.Equal(calls, kms.Calls);
        }
    }

    [Fact]
    public async Task AnEmptyContextIsRefused()
    {
        using var kms = FakeKms.CreateDefault();
        await using var services = kms.BuildServices();

        await Assert.ThrowsAsync<ArgumentException>(async () =>
            await services.GetRequiredService<IEnvelopeCipher>().EncryptAsync(Plain, string.Empty, CancellationToken.None));
    }

    [Fact]
    public async Task EachKeyedHashKeyUsesItsOwnKmsKey()
    {
        using var kms = FakeKms.CreateDefault();
        await using var services = kms.BuildServices();
        var hasher = services.GetRequiredService<IKeyedHasher>();
        var data = "install\0synthetic"u8.ToArray();

        var macs = new List<byte[]>();
        foreach (var key in Enum.GetValues<KeyedHashKey>())
        {
            macs.Add(await hasher.HmacSha256Async(key, data, CancellationToken.None));
        }

        Assert.All(macs, m => Assert.Equal(32, m.Length));
        Assert.Equal(macs.Count, macs.Select(m => Convert.ToHexString(m)).Distinct(StringComparer.Ordinal).Count());
    }

    [Fact]
    public async Task AnUnreachableKmsMakesTheHasherFailClosed()
    {
        using var kms = FakeKms.CreateDefault();
        await using var services = kms.BuildServices();
        kms.Fault = FakeKmsFault.Throw;

        await Assert.ThrowsAsync<KmsUnavailableException>(async () =>
            await services.GetRequiredService<IKeyedHasher>().HmacSha256Async(KeyedHashKey.Seat, Plain, CancellationToken.None));
        Assert.Equal(2, kms.Calls);
    }
}

/// <summary>
/// T-123 acceptance: no API of the KMS abstraction, including the Local provider, returns private, HMAC or data-key
/// material or exposes a key export.
/// </summary>
public class KmsSurfaceTests
{
    private static readonly Type[] ForbiddenTypes =
    [
        typeof(ECParameters), typeof(ECDsa), typeof(AsymmetricAlgorithm), typeof(KeyedHashAlgorithm), typeof(HashAlgorithm),
        typeof(SymmetricAlgorithm), typeof(AesGcm), typeof(RSAParameters),
    ];

    private static readonly Type[] ByteTypes = [typeof(byte[]), typeof(ReadOnlyMemory<byte>), typeof(Memory<byte>)];

    [Fact]
    public void NoKmsMemberReturnsKeyMaterial()
    {
        var types = typeof(ISigner).Assembly.GetTypes()
            .Where(t => string.Equals(t.Namespace, typeof(ISigner).Namespace, StringComparison.Ordinal))
            .Where(t => !t.IsDefined(typeof(System.Runtime.CompilerServices.CompilerGeneratedAttribute), inherit: false) && !t.Name.StartsWith('<'))
            .ToList();
        Assert.Contains(types, t => t.Name == "LocalKms");

        var offenders = new List<string>();
        foreach (var type in types)
        {
            const BindingFlags Flags = BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly;
            foreach (var method in type.GetMethods(Flags).Where(m => !m.IsSpecialName))
            {
                Check(type, method.Name, method.ReturnType, offenders);
                if (method.Name.StartsWith("Export", StringComparison.Ordinal))
                {
                    offenders.Add($"{type.Name}.{method.Name}: key export");
                }
            }

            foreach (var property in type.GetProperties(Flags))
            {
                Check(type, property.Name, property.PropertyType, offenders);
            }

            foreach (var field in type.GetFields(Flags).Where(f => !f.IsLiteral))
            {
                Check(type, field.Name, field.FieldType, offenders);
            }
        }

        Assert.Empty(offenders);
    }

    private static void Check(Type owner, string name, Type type, List<string> offenders)
    {
        var unwrapped = Unwrap(type);
        if (ForbiddenTypes.Any(f => f.IsAssignableFrom(unwrapped)))
        {
            offenders.Add($"{owner.Name}.{name}: returns {unwrapped.Name}");
        }

        var namesAKey = name.Contains("Key", StringComparison.Ordinal) && !name.Contains("PublicKey", StringComparison.Ordinal);
        if (namesAKey && ByteTypes.Contains(unwrapped))
        {
            offenders.Add($"{owner.Name}.{name}: returns bytes named *Key*");
        }
    }

    private static Type Unwrap(Type type)
    {
        while (type.IsGenericType && (type.GetGenericTypeDefinition() == typeof(Task<>) || type.GetGenericTypeDefinition() == typeof(ValueTask<>)))
        {
            type = type.GetGenericArguments()[0];
        }

        return type;
    }
}
