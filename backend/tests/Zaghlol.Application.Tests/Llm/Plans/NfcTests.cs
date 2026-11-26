using Zaghlol.Application.Llm.Plans;

namespace Zaghlol.Application.Tests.Llm.Plans;

/// <summary>T-330 design note: NFC detection must work with InvariantGlobalization (where string.IsNormalized is a no-op).</summary>
public class NfcTests
{
    [Theory]
    [InlineData("plain ascii {amount}")]
    [InlineData("صرفت {amount} على {target}.")]
    [InlineData("آمن")]
    [InlineData("بَّ")]
    [InlineData("café")]
    [InlineData("\U0001F389 done")]
    public void NormalisedTextPasses(string text) => Assert.True(Nfc.IsNfc(text));

    [Theory]
    [InlineData("café")]
    [InlineData("آ")]
    [InlineData("أَ")]
    [InlineData("بَّ")]
    [InlineData("Å")]
    [InlineData("가")]
    [InlineData("豈")]
    public void NotNormalisedTextFails(string text) => Assert.False(Nfc.IsNfc(text));

    [Fact]
    public void ALoneSurrogateFails() => Assert.False(Nfc.IsNfc("bad " + '\ud800' + " surrogate"));
}
