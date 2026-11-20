namespace Zaghlol.Api.Tests;

/// <summary>T-201 review I-9: the refusal helper retries only the <c>DeferredHost</c> disposal race, never anything else.</summary>
[Collection(ApiHostGroup.Name)]
public sealed class ApiStartRefusalTests
{
    [Fact]
    public void OtherDisposedErrorsAndRealRefusalsAreNotTheRace()
    {
        Assert.False(ApiStartRefusal.IsDeferredHostDisposalRace(Thrown(new ObjectDisposedException("IServiceProvider"))));
        Assert.False(ApiStartRefusal.IsDeferredHostDisposalRace(Thrown(new ObjectDisposedException("Other"))));
        Assert.False(ApiStartRefusal.IsDeferredHostDisposalRace(new Zaghlol.Infrastructure.Kms.KmsConfigurationException()));
    }

    private static Exception Thrown(Exception error)
    {
        try
        {
            throw error;
        }
        catch (Exception caught)
        {
            return caught;
        }
    }
}
