using Serilog.Core;
using Serilog.Events;
using Serilog.Formatting;

namespace Zaghlol.Infrastructure.Observability;

/// <summary>Writes formatted events to a <see cref="TextWriter"/> under a lock. Tests use it to capture the final log bytes.</summary>
internal sealed class TextWriterLogSink(ITextFormatter formatter, TextWriter writer) : ILogEventSink
{
    private readonly object gate = new();

    public void Emit(LogEvent logEvent)
    {
        lock (gate)
        {
            formatter.Format(logEvent, writer);
            writer.Flush();
        }
    }
}
