using System.Text;
using Zaghlol.Application.Sync;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.Kms;

namespace Zaghlol.Infrastructure.Sync;

/// <summary>
/// <c>install_hash</c> = HMAC-SHA256(<c>InstallHashPepper</c>, <c>"zaghlol-install-hash-v1" ‖ 0x00 ‖ installId</c>), the install
/// ID in its lowercase "D" form, computed inside the KMS (backend-schema §3). The label separates it from the monthly log key,
/// which uses the same pepper with another label (<c>LogPseudonymizer</c>). The raw install ID is never written to the
/// contribution tables.
/// </summary>
internal sealed class KeyedInstallHasher(IKeyedHasher hasher) : IInstallHasher
{
    public const string Label = "zaghlol-install-hash-v1";

    public ValueTask<byte[]> HashAsync(InstallId installId, CancellationToken cancellationToken) =>
        hasher.HmacSha256Async(KeyedHashKey.InstallHashPepper, Input(installId), cancellationToken);

    internal static byte[] Input(InstallId installId) => Encoding.UTF8.GetBytes(Label + "\0" + installId);
}
