using Zaghlol.Application.Llm.Attestation;

namespace Zaghlol.Application.Tests.Llm.Attestation;

/// <summary>B93-M1: the dev proof vector shared with app/test/core/llm/llm_attestation_test.dart.</summary>
public sealed class LlmDevProofVectorTests
{
    [Fact]
    public void DevProofMatchesTheSharedVector()
    {
        var keyBase64 = Convert.ToBase64String(Enumerable.Repeat((byte)1, 32).ToArray());
        var settings = LlmAttestationSettings.Resolve("Fake", keyBase64, "Development");
        var key = Enumerable.Repeat((byte)1, 32).ToArray();
        var bodyHash = Enumerable.Repeat((byte)2, 32).ToArray();

        Assert.NotNull(settings);
        Assert.Equal("cyFAbgyID9kll4mL6zk68q6-1Rq1zfHVLlmR-a-t0t4", LlmAttestationVerifier.DevProof(key, bodyHash));
    }
}
