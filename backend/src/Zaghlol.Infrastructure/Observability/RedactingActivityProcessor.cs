using System.Diagnostics;
using System.Globalization;
using OpenTelemetry;

namespace Zaghlol.Infrastructure.Observability;

/// <summary>
/// Runs before the exporter and strips every span tag that is not in <see cref="SpanTagPolicy"/>. It drops
/// <c>url.full</c>, <c>url.query</c>, <c>http.url</c> and <c>http.target</c> with everything else not listed, sets
/// <c>url.path</c> to the matched route template on server spans, removes the status description (exception text) and
/// renames spans from the method and the route or the explicit <c>url.template</c>, never a raw path. Instrumentations are
/// configured not to record exceptions, so spans carry no exception events.
/// </summary>
public sealed class RedactingActivityProcessor : BaseProcessor<Activity>
{
    private const int MaxTagChars = 1000;

    public override void OnEnd(Activity data)
    {
        ArgumentNullException.ThrowIfNull(data);

        List<string>? remove = null;
        List<KeyValuePair<string, string>>? truncate = null;
        foreach (var tag in data.TagObjects)
        {
            if (!SpanTagPolicy.IsAllowed(tag.Key))
            {
                (remove ??= []).Add(tag.Key);
            }
            else if (tag.Value is string text && text.Length > MaxTagChars)
            {
                (truncate ??= []).Add(new KeyValuePair<string, string>(tag.Key, text[..MaxTagChars]));
            }
        }

        if (remove is not null)
        {
            foreach (var key in remove)
            {
                data.SetTag(key, null);
            }
        }

        if (truncate is not null)
        {
            foreach (var (key, text) in truncate)
            {
                data.SetTag(key, text);
            }
        }

        var method = Text(data, "http.request.method");
        var route = Text(data, "http.route");
        if (data.Kind == ActivityKind.Server)
        {
            if (route is not null)
            {
                data.SetTag("url.path", route);
            }

            data.DisplayName = route is null ? method ?? "request" : string.Create(CultureInfo.InvariantCulture, $"{method} {route}");
        }
        else if (data.Kind == ActivityKind.Client && Text(data, "url.template") is { } template)
        {
            data.DisplayName = string.Create(CultureInfo.InvariantCulture, $"{method} {template}");
        }

        if (data.StatusDescription is not null)
        {
            data.SetStatus(data.Status);
        }
    }

    private static string? Text(Activity activity, string key) => activity.GetTagItem(key) as string;
}
