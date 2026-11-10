using System.Text.Json.Serialization;
using Zaghlol.Api.Endpoints.Admin;
using Zaghlol.Api.Endpoints.V1;

namespace Zaghlol.Api.Json;

/// <summary>
/// Source-generated metadata for every Zaghlol-defined request and response body (T-124 strict DTO policy). Strict reading
/// options are layered on top in <see cref="StrictJson"/>; the open third-party bodies (T-133/134/135) never use this
/// context.
/// </summary>
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
    NumberHandling = JsonNumberHandling.Strict,
    PropertyNameCaseInsensitive = false,
    Converters = new[] { typeof(UtcZDateTimeOffsetConverter) })]
[JsonSerializable(typeof(InstallRequest))]
[JsonSerializable(typeof(InstallResponse))]
[JsonSerializable(typeof(MerchantDraftRequest))]
[JsonSerializable(typeof(AliasDraftRequest))]
[JsonSerializable(typeof(KeywordDraftRequest))]
[JsonSerializable(typeof(CategoryDraftRequest))]
[JsonSerializable(typeof(CatalogPublishRequest))]
[JsonSerializable(typeof(CatalogPublishResponse))]
[JsonSerializable(typeof(FlagUpdateRequest))]
[JsonSerializable(typeof(FlagStateDto))]
[JsonSerializable(typeof(PriceOverrideRequest))]
[JsonSerializable(typeof(PriceOverrideResponse))]
[JsonSerializable(typeof(string))]
internal sealed partial class ApiJsonContext : JsonSerializerContext;
