namespace Zaghlol.Ops.Cli;

/// <summary>Where keystrokes come from. The real source is the terminal, read with the terminal's echo off.</summary>
internal interface IKeySource
{
    /// <summary>False when standard input is redirected (a pipe or a file) rather than a terminal.</summary>
    bool IsInteractive { get; }

    /// <summary>The next key, never echoed.</summary>
    ConsoleKeyInfo ReadKey();
}

internal sealed class ConsoleKeySource : IKeySource
{
    public bool IsInteractive => !Console.IsInputRedirected;

    public ConsoleKeyInfo ReadKey() => Console.ReadKey(intercept: true);
}

internal enum PromptStatus
{
    Ok,
    NotInteractive,
    Cancelled,
    BadFormat,
}

/// <summary>What the order-ID prompt produced. <see cref="Value"/> is the caller's to clear; it is never a string.</summary>
internal sealed record OrderIdInput(PromptStatus Status, char[]? Value);

/// <summary>Reads the store order ID (D-57). There is no other way to give it to the CLI.</summary>
internal interface ISecretPrompt
{
    /// <summary>False when input is redirected; the command then refuses before it signs in.</summary>
    bool IsInteractive { get; }

    OrderIdInput ReadOrderId();
}

/// <summary>
/// The no-echo order-ID prompt (T-137 design note section 3). It reads the terminal key by key with the echo off and prints
/// nothing for the typed characters, not even a mask, so neither the value nor its length reaches the screen or a terminal
/// recording. It refuses redirected input, because a script that feeds it keeps the order ID somewhere (a file, shell history).
/// The value stays in a <c>char[]</c> that the caller clears.
/// </summary>
internal sealed class SecretPrompt(IKeySource keys, TextWriter prompt) : ISecretPrompt
{
    public bool IsInteractive => keys.IsInteractive;

    public const int MinLength = 6;

    public const int MaxLength = 64;

    public OrderIdInput ReadOrderId()
    {
        if (!keys.IsInteractive)
        {
            return new OrderIdInput(PromptStatus.NotInteractive, null);
        }

        prompt.Write("Store order ID (typed text is not shown): ");
        prompt.Flush();
        var buffer = new char[MaxLength];
        var length = 0;
        var invalid = false;
        try
        {
            while (true)
            {
                var key = keys.ReadKey();
                if (key.Key == ConsoleKey.Enter)
                {
                    break;
                }

                if (key.Key == ConsoleKey.Escape || (key.Key == ConsoleKey.C && (key.Modifiers & ConsoleModifiers.Control) != 0))
                {
                    prompt.WriteLine();
                    Array.Clear(buffer);
                    return new OrderIdInput(PromptStatus.Cancelled, null);
                }

                if (key.Key == ConsoleKey.Backspace)
                {
                    if (length > 0)
                    {
                        buffer[--length] = '\0';
                    }

                    continue;
                }

                var c = key.KeyChar;
                if (char.IsControl(c) || c == '\0')
                {
                    continue;
                }

                if (length == MaxLength || !(char.IsAsciiLetterOrDigit(c) || c is '.' or '-'))
                {
                    invalid = true;
                    continue;
                }

                buffer[length++] = c;
            }

            prompt.WriteLine();
            if (invalid || length < MinLength)
            {
                Array.Clear(buffer);
                return new OrderIdInput(PromptStatus.BadFormat, null);
            }

            var value = buffer.AsSpan(0, length).ToArray();
            Array.Clear(buffer);
            return new OrderIdInput(PromptStatus.Ok, value);
        }
        catch
        {
            Array.Clear(buffer);
            throw;
        }
    }
}
