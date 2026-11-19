using System.Collections.Concurrent;
using System.Globalization;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Zaghlol.Application.Purchases;
using Zaghlol.Domain;
using Zaghlol.Infrastructure.GooglePlay;
using Zaghlol.Infrastructure.Persistence;

namespace Zaghlol.Api.Dev;

/// <summary>
/// DEV ONLY. Lets Gold be tested on a development build without Google Play: a fake Play Developer API and
/// <c>POST /dev/v1/grant-gold</c>. Switched on by <c>Dev:FakeStores=true</c> and refused (the host does not start) in any
/// environment but Development. The real verification, seat and entitlement code still runs; only the store answer is invented.
/// The dev-signed entitlement is accepted by the app only in non-release builds (dev signing keys).
/// </summary>
internal static partial class DevFakeStores
{
    public const string ConfigKey = "Dev:FakeStores";

    public static bool IsEnabled(IConfiguration configuration) =>
        string.Equals(configuration[ConfigKey], "true", StringComparison.OrdinalIgnoreCase);

    /// <summary>Registers the fake Play API in place of the real one. Throws unless the host is Development.</summary>
    public static IServiceCollection AddZaghlolDevFakeStores(this IServiceCollection services, IConfiguration configuration, IHostEnvironment environment)
    {
        ArgumentNullException.ThrowIfNull(services);
        if (!IsEnabled(configuration))
        {
            return services;
        }

        if (!environment.IsDevelopment())
        {
            throw new InvalidOperationException("Dev:FakeStores is only allowed in the Development environment.");
        }

        services.RemoveAll<IPlayDeveloperApi>();
        services.AddSingleton<DevFakePlayApi>();
        services.AddSingleton<IPlayDeveloperApi>(provider => provider.GetRequiredService<DevFakePlayApi>());
        return services;
    }

    public static IEndpointRouteBuilder MapDevFakeStores(this WebApplication app)
    {
        ArgumentNullException.ThrowIfNull(app);
        if (!IsEnabled(app.Configuration))
        {
            return app;
        }

        if (!app.Environment.IsDevelopment())
        {
            throw new InvalidOperationException("Dev:FakeStores is only allowed in the Development environment.");
        }

        LogFakeStoresOn(app.Logger);
        app.MapPost("/dev/v1/grant-gold", GrantGoldAsync).AllowAnonymous();
        app.MapGet("/dev/v1/app-keys", (IConfiguration configuration) => Results.Text(AppKeys(configuration) + "\n", "text/plain")).AllowAnonymous();
        return app;
    }

    /// <summary>The <c>kid:x:y,...</c> list for the app's <c>--dart-define=ZAGHLOL_DEV_KEYS</c>: the public JWKs of the local ring.</summary>
    internal static string AppKeys(IConfiguration configuration) =>
        string.Join(
            ',',
            configuration.GetSection("Signing:Keys").GetChildren()
                .Select(k => (Kid: k["Kid"], X: k["PublicJwk:X"], Y: k["PublicJwk:Y"]))
                .Where(k => k.Kid is { Length: > 0 } && k.X is { Length: > 0 } && k.Y is { Length: > 0 })
                .Select(k => $"{k.Kid}:{k.X}:{k.Y}"));

    [LoggerMessage(Level = LogLevel.Warning, Message = "DEV FAKE STORES ARE ON: POST /dev/v1/grant-gold grants Gold without any purchase. Never run this outside local development.")]
    private static partial void LogFakeStoresOn(ILogger logger);

    private static async Task<IResult> GrantGoldAsync(
        HttpContext context,
        [FromServices] DevFakePlayApi play,
        [FromServices] GooglePlayOptions options,
        [FromServices] IEnumerable<IStoreVerification> verifiers,
        [FromServices] IVerifyGrant grant,
        [FromServices] IAppDbContextFactory contexts,
        [FromServices] TimeProvider clock,
        CancellationToken cancellationToken)
    {
        context.Response.Headers.CacheControl = "no-store";

        // Body (optional): {"plan":"monthly|yearly|lifetime","installId":"<uuid>"}. Default: yearly, the newest install.
        var plan = GoldPlan.Yearly;
        InstallId? target = null;
        if (context.Request.ContentLength is > 0)
        {
            JsonElement root;
            try
            {
                using var document = await JsonDocument.ParseAsync(context.Request.Body, cancellationToken: cancellationToken);
                root = document.RootElement.Clone();
            }
            catch (JsonException)
            {
                return Text(StatusCodes.Status400BadRequest, "body must be JSON");
            }

            if (root.ValueKind != JsonValueKind.Object)
            {
                return Text(StatusCodes.Status400BadRequest, "body must be a JSON object");
            }

            if (root.TryGetProperty("plan", out var planText))
            {
                if (planText.ValueKind != JsonValueKind.String || !Enum.TryParse(planText.GetString(), ignoreCase: true, out plan) || !Enum.IsDefined(plan))
                {
                    return Text(StatusCodes.Status400BadRequest, "plan must be monthly, yearly or lifetime");
                }
            }

            if (root.TryGetProperty("installId", out var idText))
            {
                if (idText.ValueKind != JsonValueKind.String || !InstallId.TryParse(idText.GetString(), out var parsed))
                {
                    return Text(StatusCodes.Status400BadRequest, "installId must be a UUID");
                }

                target = parsed;
            }
        }

        InstallId install;
        if (target is { } given)
        {
            await using var db = contexts.CreateDbContext();
            if (!await db.Installs.AnyAsync(i => i.Id == given.Value && i.DeletedAt == null, cancellationToken))
            {
                return Text(StatusCodes.Status404NotFound, "no such install");
            }

            install = given;
        }
        else
        {
            await using var db = contexts.CreateDbContext();
            var newest = await db.Installs
                .Where(i => i.DeletedAt == null)
                .OrderByDescending(i => i.FirstSeenAt)
                .Select(i => (Guid?)i.Id)
                .FirstOrDefaultAsync(cancellationToken);
            if (newest is not { } id)
            {
                return Text(StatusCodes.Status404NotFound, "no install has registered yet: open the app once, then retry");
            }

            install = InstallId.FromGuid(id);
        }

        var product = options.Catalog.Products.FirstOrDefault(p => p.Value.Plan == plan);
        if (product.Key is null)
        {
            return Text(StatusCodes.Status500InternalServerError, "Purchases:Google:Products does not define that plan");
        }

        var verifier = verifiers.FirstOrDefault(v => v.Store == PurchaseStore.GooglePlay);
        if (verifier is null)
        {
            return Text(StatusCodes.Status500InternalServerError, "no Google verifier registered");
        }

        var now = clock.GetUtcNow();
        var token = "devfake." + Guid.NewGuid().ToString("N");
        play.Register(token, product.Key, product.Value.Kind, StoreBindingRef.Compute(install), now);

        var result = await verifier.VerifyAsync(new PlayPurchaseRef(product.Key, new Sensitive<string>(token)), install, BindingCheck.RequireCaller, cancellationToken);
        var issued = false;
        if (result is { Status: VerifyStatus.Active, PurchaseId: not null })
        {
            var granted = await grant.ComposeAsync(result, new VerifyContext(install, null, now), cancellationToken);
            issued = granted.EntitlementToken is not null;
        }

        var body = string.Create(
            CultureInfo.InvariantCulture,
            $"{{\"installId\":\"{install}\",\"plan\":\"{plan.ToString().ToLowerInvariant()}\",\"status\":\"{PurchaseEndpointsStatus(result.Status)}\",\"entitlementIssued\":{(issued ? "true" : "false")},\"devOnly\":true}}");
        return Results.Content(body, "application/json");
    }

    private static string PurchaseEndpointsStatus(VerifyStatus status) => status switch
    {
        VerifyStatus.Active => "active",
        VerifyStatus.Pending => "pending",
        VerifyStatus.Expired => "expired",
        VerifyStatus.Refunded => "refunded",
        _ => "invalid",
    };

    private static IResult Text(int status, string message) => Results.Text(message + "\n", "text/plain", statusCode: status);
}

/// <summary>
/// DEV ONLY in-memory stand-in for the Play Developer API: a token registered through <c>/dev/v1/grant-gold</c> reads as an
/// active, test-flagged, already-acknowledged purchase bound to the chosen install; any other token is a 404 (client error).
/// </summary>
internal sealed class DevFakePlayApi : IPlayDeveloperApi
{
    private readonly ConcurrentDictionary<string, Entry> entries = new(StringComparer.Ordinal);

    public void Register(string token, string productId, PlayProductKind kind, string binding, DateTimeOffset now) =>
        entries[token] = new Entry(productId, kind, binding, now, kind == PlayProductKind.Subscription ? now.AddDays(365) : null);

    public Task<PlaySubscription> GetSubscriptionAsync(Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken)
    {
        var e = Find(token, PlayApi.SubscriptionGet, PlayProductKind.Subscription);
        return Task.FromResult(new PlaySubscription(
            PlaySubscriptionState.Active,
            [new PlayLineItem(e.ProductId, e.Expiry, null)],
            null,
            Acknowledged: true,
            TestPurchase: true,
            e.Binding,
            e.Start));
    }

    public Task<PlayProduct> GetProductAsync(Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken)
    {
        var e = Find(token, PlayApi.ProductGet, PlayProductKind.OneTime);
        return Task.FromResult(new PlayProduct([e.ProductId], PlayProductState.Purchased, TestPurchase: true, null, e.Binding, Acknowledged: true, e.Start));
    }

    public Task AcknowledgeSubscriptionAsync(string productId, Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken) => Task.CompletedTask;

    public Task AcknowledgeProductAsync(string productId, Sensitive<string> token, StoreLane lane, CancellationToken cancellationToken) => Task.CompletedTask;

    public Task<PlayOrder> GetOrderAsync(Sensitive<string> orderId, StoreLane lane, CancellationToken cancellationToken) =>
        throw new PlayApiException(PlayApi.OrderGet, PlayCallOutcome.ClientError, 404);

    public Task<PlayVoidedPage> ListVoidedPurchasesAsync(DateTimeOffset from, DateTimeOffset until, Sensitive<string>? pageToken, StoreLane lane, CancellationToken cancellationToken) =>
        Task.FromResult(new PlayVoidedPage([], null));

    private Entry Find(Sensitive<string> token, PlayApi api, PlayProductKind kind) =>
        entries.TryGetValue(token.Reveal(), out var e) && e.Kind == kind
            ? e
            : throw new PlayApiException(api, PlayCallOutcome.ClientError, 404);

    private sealed record Entry(string ProductId, PlayProductKind Kind, string Binding, DateTimeOffset Start, DateTimeOffset? Expiry);
}
