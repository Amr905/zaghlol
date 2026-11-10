using System.Collections.Concurrent;
using System.Diagnostics.Metrics;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Zaghlol.Api.Auth;
using Zaghlol.Api.Tests.Installs;
using Zaghlol.Application.Operators;
using Zaghlol.Infrastructure.Observability;
using Zaghlol.Testing;

namespace Zaghlol.Api.Tests.Operators;

/// <summary>An in-memory <c>operators</c> table that counts its reads.</summary>
internal sealed class FakeOperatorDirectory : IOperatorDirectory
{
    private readonly ConcurrentDictionary<string, OperatorRecord> rows = new(StringComparer.Ordinal);
    private int reads;

    public int Reads => Volatile.Read(ref reads);

    public Guid Add(string subject, params string[] roles)
    {
        var id = Guid.NewGuid();
        rows[subject] = new OperatorRecord(id, roles, Disabled: false);
        return id;
    }

    public void Disable(string subject) => rows[subject] = rows[subject] with { Disabled = true };

    public Task<OperatorRecord?> FindBySubjectAsync(string subject, CancellationToken cancellationToken)
    {
        Interlocked.Increment(ref reads);
        return Task.FromResult(rows.GetValueOrDefault(subject));
    }
}

/// <summary>Hands out clients whose only handler is the fake issuer.</summary>
internal sealed class IssuerClientFactory(FakeOidcIssuer issuer) : IHttpClientFactory
{
    public HttpClient CreateClient(string name) => new(issuer.CreateHandler());
}

/// <summary>Counts the Zaghlol meter's counter measurements by instrument and <c>role</c> tag.</summary>
internal sealed class CounterRecorder : IDisposable
{
    private readonly MeterListener listener = new();
    private readonly ConcurrentDictionary<string, long> totals = new(StringComparer.Ordinal);

    public CounterRecorder()
    {
        listener.InstrumentPublished = (instrument, l) =>
        {
            if (instrument.Meter.Name == ZaghlolMetrics.MeterName)
            {
                l.EnableMeasurementEvents(instrument);
            }
        };
        listener.SetMeasurementEventCallback<long>((instrument, value, tags, _) =>
        {
            var role = string.Empty;
            foreach (var tag in tags)
            {
                if (tag.Key == "role")
                {
                    role = tag.Value as string ?? string.Empty;
                }
            }

            totals.AddOrUpdate(instrument.Name + "|" + role, value, (_, total) => total + value);
        });
        listener.Start();
    }

    public long Total(string instrument, string role = "") => totals.GetValueOrDefault(instrument + "|" + role);

    public void Dispose() => listener.Dispose();
}

/// <summary>The real validator over a fake issuer, a fake directory and a manual clock.</summary>
internal sealed class ValidatorKit : IDisposable
{
    public const string ContextId = "c1";

    public ValidatorKit(Action<OperatorAuthOptions>? configure = null)
    {
        var settings = new OperatorAuthOptions
        {
            Enabled = true,
            Profile = OperatorAuthProfile.Entra,
            Issuer = FakeOidcIssuer.DefaultIssuer,
            RequiredAcrs = ContextId,
        };
        settings.Audiences.Add(FakeOidcIssuer.CliAudience);
        settings.Audiences.Add(FakeOidcIssuer.AdminAudience);
        configure?.Invoke(settings);
        Options = Microsoft.Extensions.Options.Options.Create(settings);
        Keys = new OidcKeyCache(new IssuerClientFactory(Issuer), Options, Clock, NullLogger<OidcKeyCache>.Instance);
        Validator = new OidcOperatorTokenValidator(Options, Keys, Directory, Metrics, Clock, NullLogger<OidcOperatorTokenValidator>.Instance);
    }

    public FakeOidcIssuer Issuer { get; } = new();

    public FakeOperatorDirectory Directory { get; } = new();

    public ManualClock Clock { get; } = new();

    public ZaghlolMetrics Metrics { get; } = new();

    public IOptions<OperatorAuthOptions> Options { get; }

    public OidcKeyCache Keys { get; }

    public OidcOperatorTokenValidator Validator { get; }

    public string Mint(OperatorTokenSpec spec) => Issuer.Mint(spec, Clock.Now);

    public Task<OperatorIdentity?> ValidateAsync(string token) => Validator.ValidateAsync(token, CancellationToken.None).AsTask();

    public void Dispose()
    {
        Keys.Dispose();
        Metrics.Dispose();
        Issuer.Dispose();
    }
}
