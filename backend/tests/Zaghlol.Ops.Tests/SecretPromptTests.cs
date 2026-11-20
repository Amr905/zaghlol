using Zaghlol.Ops.Cli;
using Zaghlol.Ops.Tests.Support;

namespace Zaghlol.Ops.Tests;

/// <summary>D-57: the order-ID prompt prints nothing for typed characters, refuses redirected input and keeps the value out of strings.</summary>
public class SecretPromptTests
{
    private const string Label = "Store order ID (typed text is not shown): ";

    [Fact]
    public void TheTypedValueIsReturnedAsCharactersAndNothingOfItIsEchoed()
    {
        using var output = new StringWriter();
        var prompt = new SecretPrompt(new ScriptedKeys("GPA.3312-5208-4571-04923"), output);

        var input = prompt.ReadOrderId();

        Assert.Equal(PromptStatus.Ok, input.Status);
        Assert.Equal("GPA.3312-5208-4571-04923", new string(input.Value));
        Assert.Equal(Label + Environment.NewLine, output.ToString());
        Assert.DoesNotContain("*", output.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void BackspaceEditsWithoutEcho()
    {
        using var output = new StringWriter();
        var prompt = new SecretPrompt(new ScriptedKeys("GPAX\b.3312-5208-4571-04923"), output);

        var input = prompt.ReadOrderId();

        Assert.Equal("GPA.3312-5208-4571-04923", new string(input.Value));
        Assert.Equal(Label + Environment.NewLine, output.ToString());
    }

    [Fact]
    public void RedirectedInputIsRefusedAndNoKeyIsRead()
    {
        using var output = new StringWriter();
        var keys = new ScriptedKeys("GPA.3312-5208-4571-04923", interactive: false);
        var prompt = new SecretPrompt(keys, output);

        var input = prompt.ReadOrderId();

        Assert.Equal(PromptStatus.NotInteractive, input.Status);
        Assert.Null(input.Value);
        Assert.False(prompt.IsInteractive);
        Assert.Equal(string.Empty, output.ToString());
        Assert.Equal('G', keys.ReadKey().KeyChar);
    }

    [Theory]
    [InlineData("ABC12")]
    [InlineData("GPA_3312_5208")]
    [InlineData("GPA 3312 5208")]
    [InlineData("")]
    public void ABadShapeIsRefusedAndTheValueIsNotShown(string typed)
    {
        using var output = new StringWriter();

        var input = new SecretPrompt(new ScriptedKeys(typed), output).ReadOrderId();

        Assert.Equal(PromptStatus.BadFormat, input.Status);
        Assert.Null(input.Value);
        Assert.Equal(Label + Environment.NewLine, output.ToString());
    }

    [Fact]
    public void MoreThanSixtyFourCharactersIsRefusedNotTruncated()
    {
        using var output = new StringWriter();

        var input = new SecretPrompt(new ScriptedKeys(new string('A', 65)), output).ReadOrderId();

        Assert.Equal(PromptStatus.BadFormat, input.Status);
        Assert.Null(input.Value);
    }

    [Fact]
    public void ExactlyTheLimitsAreAccepted()
    {
        using var output = new StringWriter();

        Assert.Equal(PromptStatus.Ok, new SecretPrompt(new ScriptedKeys("ABCDEF"), output).ReadOrderId().Status);
        Assert.Equal(PromptStatus.Ok, new SecretPrompt(new ScriptedKeys(new string('A', 64)), output).ReadOrderId().Status);
    }

    [Fact]
    public void EscapeCancelsAndReturnsNothing()
    {
        using var output = new StringWriter();
        var keys = new Queue<ConsoleKeyInfo>(
        [
            new ConsoleKeyInfo('G', ConsoleKey.G, true, false, false),
            new ConsoleKeyInfo('\u001b', ConsoleKey.Escape, false, false, false),
        ]);

        var input = new SecretPrompt(new QueueKeys(keys), output).ReadOrderId();

        Assert.Equal(PromptStatus.Cancelled, input.Status);
        Assert.Null(input.Value);
    }

    [Fact]
    public void ControlCCancelsTheOrderIdPrompt()
    {
        using var output = new StringWriter();
        var keys = new Queue<ConsoleKeyInfo>(
        [
            new ConsoleKeyInfo('G', ConsoleKey.G, true, false, false),
            new ConsoleKeyInfo('\u0003', ConsoleKey.C, false, false, true),
        ]);

        var input = new SecretPrompt(new QueueKeys(keys), output).ReadOrderId();

        Assert.Equal(PromptStatus.Cancelled, input.Status);
        Assert.Null(input.Value);
    }

    [Fact]
    public void TheEmailPromptShowsWhatIsTypedAndReturnsIt()
    {
        using var output = new StringWriter();

        var input = new SecretPrompt(new ScriptedKeys("a@b.eg"), output).ReadEmail();

        Assert.Equal(PromptStatus.Ok, input.Status);
        Assert.Equal("a@b.eg", input.Value);
    }

    [Fact]
    public void TheEmailPromptRefusesRedirectedInputAndCancelsOnEscape()
    {
        using var output = new StringWriter();
        Assert.Equal(PromptStatus.NotInteractive, new SecretPrompt(new ScriptedKeys("a@b.eg", interactive: false), output).ReadEmail().Status);

        var keys = new Queue<ConsoleKeyInfo>([new ConsoleKeyInfo('\u001b', ConsoleKey.Escape, false, false, false)]);
        Assert.Equal(PromptStatus.Cancelled, new SecretPrompt(new QueueKeys(keys), output).ReadEmail().Status);
    }

    private sealed class QueueKeys(Queue<ConsoleKeyInfo> keys) : IKeySource
    {
        public bool IsInteractive => true;

        public ConsoleKeyInfo ReadKey() => keys.Dequeue();
    }
}
