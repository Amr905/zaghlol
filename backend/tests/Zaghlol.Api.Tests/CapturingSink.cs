using System.Collections.Concurrent;
using System.Globalization;
using Serilog.Core;
using Serilog.Events;

namespace Zaghlol.Api.Tests;

/// <summary>Collects everything the API logs (message, properties, exception) as text for assertions.</summary>
public sealed class CapturingSink : ILogEventSink
{
    private readonly ConcurrentQueue<string> entries = new();

    public IReadOnlyCollection<string> Entries => entries;

    public void Emit(LogEvent logEvent)
    {
        ArgumentNullException.ThrowIfNull(logEvent);

        var properties = string.Join(
            ';',
            logEvent.Properties.Select(p => string.Create(CultureInfo.InvariantCulture, $"{p.Key}={p.Value}")));
        entries.Enqueue(logEvent.RenderMessage(CultureInfo.InvariantCulture) + "|" + properties + "|" + logEvent.Exception);
    }
}
