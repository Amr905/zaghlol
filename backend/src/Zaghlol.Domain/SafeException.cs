namespace Zaghlol.Domain;

/// <summary>
/// An exception whose message is a constant written in code, never built from request data, tokens, order IDs, URIs or
/// database text. Only these messages are written to the logs (error-handling-and-observability.md section 3.2); for
/// every other exception type the log carries the type name and stack frames only (D-57).
/// </summary>
public abstract class SafeException : Exception
{
    protected SafeException()
    {
    }

    protected SafeException(string message)
        : base(message)
    {
    }

    protected SafeException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}
