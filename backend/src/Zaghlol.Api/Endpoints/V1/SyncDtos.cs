using System.Text.Json;
using System.Text.Json.Serialization;
using Zaghlol.Api.Signing;
using Zaghlol.Application.Catalog;

namespace Zaghlol.Api.Endpoints.V1;

/// <summary>
/// <c>SyncRequest</c> (backend-api §4.2). Exactly the BR-SYNC-03 members: three version cursors, the diagnostic registry version,
/// the entitlement delivery proof, and the opt-in outbox. Closed at every level: any other member is <c>400 UNKNOWN_FIELD</c>
/// (a contract test pins the member list). No amount, date, account, message or free text other than the two names.
/// </summary>
public sealed class SyncRequest
{
    public const int MaxContributions = 50;
    public const int MaxBankRequests = 10;

    public required int CatalogVersion { get; init; }

    public required int FlagsVersion { get; init; }

    public DateTimeOffset? PricesAsOf { get; init; }

    public DateTimeOffset? EntitlementIssuedAt { get; init; }

    public int? RegistryVersion { get; init; }

    public IReadOnlyList<SyncContributionInput>? Contributions { get; init; }

    public IReadOnlyList<SyncBankRequestInput>? BankRequests { get; init; }
}

/// <summary><c>ContributionInput</c>: one opt-in merchant contribution (BR-SYNC-04).</summary>
public sealed class SyncContributionInput
{
    public required string MerchantNorm { get; init; }

    public required string InstitutionCode { get; init; }

    public required string CategoryCode { get; init; }
}

/// <summary><c>BankRequestInput</c>: a "request my bank" submission (FR-PAR-14). Never carries a message.</summary>
public sealed class SyncBankRequestInput
{
    public required string InstitutionName { get; init; }

    public required string Country { get; init; }

    public required string Channel { get; init; }
}

/// <summary>
/// The full sync 200 (OpenAPI <c>SyncResponse</c>). Unchanged blocks are explicit <c>null</c>; <c>accepted</c> is always present.
/// <c>rotateInstallToken</c> is never emitted by T-128 (FU-052 S-3). Lives in the API so it can implement the internal
/// <see cref="IAnchoredResponse"/> (T-123 code #10).
/// </summary>
internal sealed class SyncResponse : IAnchoredResponse
{
    public required DateTimeOffset ServerTime { get; init; }

    public required DateTimeOffset NextSyncNotBefore { get; init; }

    public required SyncCatalogDto? Catalog { get; init; }

    public required SyncFlagsDto? Flags { get; init; }

    public required SyncPricesDto? Prices { get; init; }

    public required SyncEntitlementDto? Entitlement { get; init; }

    public required SyncAcceptedDto Accepted { get; init; }

    public required string? AccountToken { get; init; }

    public required string? SupportNotice { get; init; }

    [JsonIgnore(Condition = JsonIgnoreCondition.Never)]
    public required string? TimeNonce { get; init; }
}

/// <summary>
/// The throttle answer: exactly <c>serverTime</c>, <c>nextSyncNotBefore</c> and <c>timeNonce</c> (R4-2). A separate type, so
/// "only three members" is structural rather than a serializer option.
/// </summary>
internal sealed class SyncThrottledResponse : IAnchoredResponse
{
    public required DateTimeOffset ServerTime { get; init; }

    public required DateTimeOffset NextSyncNotBefore { get; init; }

    [JsonIgnore(Condition = JsonIgnoreCondition.Never)]
    public required string? TimeNonce { get; init; }
}

/// <summary><c>FlagsBlock</c>.</summary>
internal sealed class SyncFlagsDto
{
    public required int Version { get; init; }

    public required IReadOnlyDictionary<string, bool> Values { get; init; }
}

/// <summary><c>PricesBlock</c>: prices and rates are decimal strings, never JSON numbers.</summary>
internal sealed class SyncPricesDto
{
    public required DateTimeOffset AsOf { get; init; }

    public required bool Stale { get; init; }

    public required IReadOnlyList<SyncGoldPriceDto> Gold { get; init; }

    public required SyncFxDto Fx { get; init; }
}

/// <summary><c>GoldPrice</c>.</summary>
internal sealed class SyncGoldPriceDto
{
    public required string Symbol { get; init; }

    public required string Currency { get; init; }

    public required string Price { get; init; }
}

/// <summary><c>FxBlock</c>.</summary>
internal sealed class SyncFxDto
{
    public required string Base { get; init; }

    public required IReadOnlyDictionary<string, string> Rates { get; init; }
}

/// <summary><c>Entitlement</c>: the signed token only.</summary>
internal sealed class SyncEntitlementDto
{
    public required string Token { get; init; }
}

/// <summary><c>AcceptedCounts</c>.</summary>
internal sealed class SyncAcceptedDto
{
    public required int Contributions { get; init; }

    public required int BankRequests { get; init; }
}

/// <summary>
/// <c>CatalogDelta</c>. Written by hand (<see cref="SyncCatalogDtoConverter"/>) so the ops use the same writer as the full
/// snapshot (<see cref="CatalogJson.WriteOp"/>): the same op always gives the same bytes.
/// </summary>
[JsonConverter(typeof(SyncCatalogDtoConverter))]
internal sealed class SyncCatalogDto
{
    public required int FromVersion { get; init; }

    public required int ToVersion { get; init; }

    public required string Mode { get; init; }

    public required Uri? FullUrl { get; init; }

    public required IReadOnlyList<CatalogOp> Ops { get; init; }
}

/// <summary>Writes <see cref="SyncCatalogDto"/>; it is never read.</summary>
internal sealed class SyncCatalogDtoConverter : JsonConverter<SyncCatalogDto>
{
    public override SyncCatalogDto Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        throw new JsonException();

    public override void Write(Utf8JsonWriter writer, SyncCatalogDto value, JsonSerializerOptions options)
    {
        ArgumentNullException.ThrowIfNull(writer);
        ArgumentNullException.ThrowIfNull(value);

        writer.WriteStartObject();
        writer.WriteNumber("fromVersion", value.FromVersion);
        writer.WriteNumber("toVersion", value.ToVersion);
        writer.WriteString("mode", value.Mode);
        if (value.FullUrl is { } url)
        {
            writer.WriteString("fullUrl", url.AbsoluteUri);
        }
        else
        {
            writer.WriteNull("fullUrl");
        }

        writer.WriteStartArray("ops");
        foreach (var op in value.Ops)
        {
            CatalogJson.WriteOp(writer, op);
        }

        writer.WriteEndArray();
        writer.WriteEndObject();
    }
}
