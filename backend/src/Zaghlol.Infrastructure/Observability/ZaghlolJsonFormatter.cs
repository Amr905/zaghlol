using System.Buffers;
using System.Globalization;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using Serilog.Events;
using Serilog.Formatting;
using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.Observability;

/// <summary>
/// One JSON object per line with the names of error-handling-and-observability.md section 3.2 (FU-002): <c>ts, level, msg,
/// traceId, spanId</c>, then only the allow-listed properties of <see cref="LogFieldPolicy"/>, each checked against its
/// shape. <c>msg</c> is the message template, never the rendered text, so a value logged through a placeholder can't reach
/// the output. An exception is written as <c>errorType</c> and <c>stack</c>; its message only when it is a
/// <see cref="SafeException"/> (<c>errorMessage</c>).
/// </summary>
public sealed class ZaghlolJsonFormatter : ITextFormatter
{
    private const int MaxStackChars = 8000;
    private const int MaxTypeChain = 5;

    private static readonly JsonWriterOptions WriterOptions = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    public void Format(LogEvent logEvent, TextWriter output)
    {
        ArgumentNullException.ThrowIfNull(logEvent);
        ArgumentNullException.ThrowIfNull(output);

        var buffer = new ArrayBufferWriter<byte>(512);
        using (var json = new Utf8JsonWriter(buffer, WriterOptions))
        {
            var template = logEvent.MessageTemplate.Text;
            json.WriteStartObject();
            json.WriteString("ts", logEvent.Timestamp.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture));
            json.WriteString("level", Level(logEvent.Level));
            json.WriteString("msg", template);
            if (logEvent.TraceId is { } traceId)
            {
                json.WriteString("traceId", traceId.ToHexString());
            }

            if (logEvent.SpanId is { } spanId)
            {
                json.WriteString("spanId", spanId.ToHexString());
            }

            WriteProperties(json, logEvent, string.Equals(template, LogFieldPolicy.AuditAlertMessage, StringComparison.Ordinal));
            WriteException(json, logEvent.Exception);
            json.WriteEndObject();
        }

        output.Write(Encoding.UTF8.GetString(buffer.WrittenSpan));
        output.Write('\n');
    }

    private static string Level(LogEventLevel level) => level switch
    {
        LogEventLevel.Verbose or LogEventLevel.Debug => "debug",
        LogEventLevel.Information => "info",
        LogEventLevel.Warning => "warn",
        LogEventLevel.Error => "error",
        _ => "fatal",
    };

    private static void WriteProperties(Utf8JsonWriter json, LogEvent logEvent, bool auditAlert)
    {
        var values = new Dictionary<string, LogEventPropertyValue>(StringComparer.Ordinal);
        foreach (var (name, value) in logEvent.Properties)
        {
            values[name == "SourceContext" ? "category" : LogFieldPolicy.Canonical(name)] = value;
        }

        foreach (var field in LogFieldPolicy.OrderedFields)
        {
            if (!values.TryGetValue(field, out var value) || !LogFieldPolicy.TryGetShape(field, out var shape))
            {
                continue;
            }

            // purchaseId belongs to audit_alert events only (the purchase UUID, never user data elsewhere).
            if (field == "purchaseId" && !auditAlert)
            {
                continue;
            }

            if (value is not ScalarValue { Value: var scalar })
            {
                json.WriteString(field, LogFieldPolicy.InvalidValue);
                continue;
            }

            if (scalar is null)
            {
                continue;
            }

            WriteValue(json, field, shape, scalar);
        }
    }

    private static void WriteValue(Utf8JsonWriter json, string field, LogFieldShape shape, object scalar)
    {
        if (shape == LogFieldShape.Number)
        {
            switch (scalar)
            {
                case sbyte or byte or short or ushort or int or uint or long:
                    json.WriteNumber(field, Convert.ToInt64(scalar, CultureInfo.InvariantCulture));
                    return;
                case ulong unsigned when unsigned <= long.MaxValue:
                    json.WriteNumber(field, (long)unsigned);
                    return;
                case double or float or decimal:
                    var number = Convert.ToDouble(scalar, CultureInfo.InvariantCulture);
                    if (double.IsFinite(number))
                    {
                        json.WriteNumber(field, number);
                        return;
                    }

                    break;
            }

            json.WriteString(field, LogFieldPolicy.InvalidValue);
            return;
        }

        var text = scalar switch
        {
            string s => s,
            Guid g => g.ToString("D", CultureInfo.InvariantCulture),
            _ => null,
        };
        json.WriteString(field, text is not null && LogFieldPolicy.Matches(shape, text) ? text : LogFieldPolicy.InvalidValue);
    }

    private static void WriteException(Utf8JsonWriter json, Exception? exception)
    {
        if (exception is null)
        {
            return;
        }

        var chain = new StringBuilder();
        var depth = 0;
        for (var current = exception; current is not null && depth < MaxTypeChain; current = current.InnerException, depth++)
        {
            if (depth > 0)
            {
                chain.Append('>');
            }

            chain.Append(current.GetType().FullName);
        }

        json.WriteString("errorType", chain.ToString());
        if (exception is SafeException)
        {
            json.WriteString("errorMessage", exception.Message);
        }

        var stack = exception.StackTrace;
        if (!string.IsNullOrEmpty(stack))
        {
            json.WriteString("stack", stack.Length > MaxStackChars ? stack[..MaxStackChars] : stack);
        }
    }
}
