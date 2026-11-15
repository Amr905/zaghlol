using Microsoft.AspNetCore.Http;
using Zaghlol.Api.Endpoints.V1;

namespace Zaghlol.Api.Tests.Sync;

/// <summary>FU-116: the sync endpoint passes <c>Zaghlol-Account</c> on only when it is exactly one non-empty value.</summary>
[Collection(ApiHostGroup.Name)]
public class SyncAccountHeaderTests
{
    private static Zaghlol.Domain.Sensitive<string>? Read(params string[] values)
    {
        var context = new DefaultHttpContext();
        if (values.Length > 0)
        {
            context.Request.Headers[PurchaseEndpoints.AccountHeader] = values;
        }

        return SyncEndpoints.AccountHeader(context);
    }

    [Fact]
    public void OneNonEmptyValueIsPassedOn() => Assert.Equal("token-1", Read("token-1")!.Value.Reveal());

    [Fact]
    public void AbsentEmptyOrRepeatedHeadersAreTreatedAsAbsent()
    {
        Assert.Null(Read());
        Assert.Null(Read(string.Empty));
        Assert.Null(Read("a", "b"));
    }
}
