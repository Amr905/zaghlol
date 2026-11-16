using Zaghlol.Api.Endpoints.Admin;
using Zaghlol.Application.Support;
using Zaghlol.Domain;

namespace Zaghlol.Api.Tests.Operators;

/// <summary>T-186: the strict bodies of the three support writes. No problem or exception ever carries a member value.</summary>
[Collection(ApiHostGroup.Name)]
public class SupportWriteBodiesTests
{
    private const string Install = "0193f2c4-7a10-4c52-9d3e-5b1f8a2c6e77";
    private const string Purchase = "0193f2c4-7a10-7c52-9d3e-5b1f8a2c6e01";
    private static readonly Guid Operator = Guid.NewGuid();

    private static ReadOnlyMemory<byte> Bytes(string json) => System.Text.Encoding.UTF8.GetBytes(json);

    private static string Move(string? extra = null, string reason = "lost_or_broken_phone", string ticket = "ZG-10422", string order = "GPA.3312-5208-4571-04923") =>
        $$"""{"purchaseId":"{{Purchase}}","toInstallId":"{{Install}}","reasonCode":"{{reason}}","ticketRef":"{{ticket}}","ownershipCheck":"{{order}}"{{extra}}}""";

    [Fact]
    public void AValidMoveParsesAndKeepsTheOrderIdSensitive()
    {
        var (command, error) = SupportWriteBodies.ParseMove(Bytes(Move(",\"attachToAccount\":true")), Operator);

        Assert.Null(error);
        Assert.Equal((Operator, SupportReason.LostOrBrokenPhone, true), (command!.OperatorId, command.Reason, command.Attach));
        Assert.Equal("GPA.3312-5208-4571-04923", command.OrderId.Reveal());
        Assert.DoesNotContain("GPA", command.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void ACorrectionNeedsItsAuditIdAndNoOtherReasonMayHaveOne()
    {
        Assert.Equal(ErrorCodes.ValidationFailed, SupportWriteBodies.ParseMove(Bytes(Move(reason: "correction")), Operator).Error);
        Assert.Equal(ErrorCodes.ValidationFailed, SupportWriteBodies.ParseMove(Bytes(Move(",\"correctsAuditId\":4")), Operator).Error);
        Assert.Equal(ErrorCodes.ValidationFailed, SupportWriteBodies.ParseMove(Bytes(Move(",\"correctsAuditId\":4,\"attachToAccount\":true", "correction")), Operator).Error);
        var (command, error) = SupportWriteBodies.ParseMove(Bytes(Move(",\"correctsAuditId\":4", "correction")), Operator);
        Assert.Null(error);
        Assert.Equal(4, command!.CorrectsAuditId);
    }

    [Theory]
    [InlineData("""{"purchaseId":"x"}""")]
    [InlineData("[]")]
    [InlineData("not json")]
    [InlineData("""{"purchaseId":"0193f2c4-7a10-7c52-9d3e-5b1f8a2c6e01","purchaseId":"0193f2c4-7a10-7c52-9d3e-5b1f8a2c6e01"}""")]
    public void AMalformedMoveIsValidationFailed(string body) =>
        Assert.Equal(ErrorCodes.ValidationFailed, SupportWriteBodies.ParseMove(Bytes(body), Operator).Error);

    [Theory]
    [InlineData(",\"extra\":1")]
    [InlineData(",\"orderId\":\"GPA.1234-5678\"")]
    public void AnUnknownMemberIsUnknownField(string extra) =>
        Assert.Equal(ErrorCodes.UnknownField, SupportWriteBodies.ParseMove(Bytes(Move(extra)), Operator).Error);

    [Theory]
    [InlineData("ZG 1", "GPA.3312-5208-4571-04923")]
    [InlineData("a@b.example", "GPA.3312-5208-4571-04923")]
    [InlineData("ZG-1", "short")]
    [InlineData("ZG-1", "has space in it")]
    [InlineData("ZG-1", "a@b.example")]
    public void ATicketOrOrderIdOutsideItsPatternIsRejected(string ticket, string order) =>
        Assert.Equal(ErrorCodes.ValidationFailed, SupportWriteBodies.ParseMove(Bytes(Move(ticket: ticket, order: order)), Operator).Error);

    [Fact]
    public void AnInstallIdThatIsNotALowercaseV4IsRejected()
    {
        var body = Move().Replace(Install, Install.ToUpperInvariant(), StringComparison.Ordinal);

        Assert.Equal(ErrorCodes.ValidationFailed, SupportWriteBodies.ParseMove(Bytes(body), Operator).Error);
    }

    [Fact]
    public void DetachNeedsTheCorrectionReasonAndAnAuditId()
    {
        var ok = $$"""{"purchaseId":"{{Purchase}}","reasonCode":"correction","ticketRef":"ZG-1","ownershipCheck":"GPA.1234-5678","correctsAuditId":7}""";

        Assert.Equal(7, SupportWriteBodies.ParseDetach(Bytes(ok), Operator).Command!.CorrectsAuditId);
        Assert.Equal(ErrorCodes.ValidationFailed, SupportWriteBodies.ParseDetach(Bytes(ok.Replace("correction", "other", StringComparison.Ordinal)), Operator).Error);
        Assert.Equal(ErrorCodes.ValidationFailed, SupportWriteBodies.ParseDetach(Bytes(ok.Replace(",\"correctsAuditId\":7", string.Empty, StringComparison.Ordinal)), Operator).Error);
        Assert.Equal(ErrorCodes.ValidationFailed, SupportWriteBodies.ParseDetach(Bytes(ok.Replace("7", "0", StringComparison.Ordinal)), Operator).Error);
    }

    [Fact]
    public void UnfreezeTakesOnlyThreeMembers()
    {
        var ok = $$"""{"purchaseId":"{{Purchase}}","ticketRef":"ZG-1","ownershipCheck":"GPA.1234-5678"}""";

        Assert.Equal(Guid.Parse(Purchase), SupportWriteBodies.ParseUnfreeze(Bytes(ok), Operator).Command!.PurchaseId);
        Assert.Equal(ErrorCodes.UnknownField, SupportWriteBodies.ParseUnfreeze(Bytes(ok.Replace("}", ",\"reasonCode\":\"other\"}", StringComparison.Ordinal)), Operator).Error);
        Assert.Equal(ErrorCodes.ValidationFailed, SupportWriteBodies.ParseUnfreeze(Bytes($$"""{"purchaseId":"{{Purchase}}"}"""), Operator).Error);
    }
}
