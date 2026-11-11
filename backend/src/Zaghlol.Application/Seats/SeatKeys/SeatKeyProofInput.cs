namespace Zaghlol.Application.Seats.SeatKeys;

/// <summary>
/// One <c>seatKeys</c> element as received: <paramref name="PublicKey"/> and <paramref name="Signature"/> are the base64url
/// texts from the body. The Api maps its <c>Sensitive&lt;…&gt;</c> DTO to this only at the point of use. <see cref="ToString"/>
/// is <c>***</c>, so record formatting and log destructuring never show the values.
/// </summary>
public sealed record SeatKeyProofInput(string PublicKey, string Signature)
{
    public override string ToString() => "***";
}
