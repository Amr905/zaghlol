using Zaghlol.Application.Llm;
using Zaghlol.Infrastructure.Llm;

namespace Zaghlol.Testing;

/// <summary>
/// Stands in for Google's OAuth exchange in tests (test support only). The token is built at run time, so no secret-looking
/// literal sits in the source; <see cref="Calls"/> and <see cref="LastKeyLength"/> let a test prove the key reached the source
/// and only the source. <see cref="Fail"/> makes the exchange throw.
/// </summary>
public sealed class FakeVertexTokenSource : IVertexAccessTokenSource
{
    private int calls;

    public string Token { get; } = "tok-" + Guid.NewGuid().ToString("N");

    public bool Fail { get; set; }

    public int Calls => Volatile.Read(ref calls);

    public int LastKeyLength { get; private set; }

    public ValueTask<LlmSensitive<string>> GetTokenAsync(LlmSensitive<string> serviceAccountJson, CancellationToken cancellationToken)
    {
        Interlocked.Increment(ref calls);
        LastKeyLength = serviceAccountJson.Reveal().Length;
        return Fail
            ? throw new InvalidOperationException("token exchange failed")
            : ValueTask.FromResult(new LlmSensitive<string>(Token));
    }
}
