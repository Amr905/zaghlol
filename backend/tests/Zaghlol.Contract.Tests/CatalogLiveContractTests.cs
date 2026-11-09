using System.Buffers.Text;
using System.Globalization;
using System.IO.Compression;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;
using Zaghlol.Api.Auth;
using Zaghlol.Application.Catalog;
using Zaghlol.Contract.Tests.Signing;
using Zaghlol.Infrastructure.Kms;
using Zaghlol.Testing;

namespace Zaghlol.Contract.Tests;

/// <summary>A test operator taken from two headers; production has no operator authenticator until T-136.</summary>
internal sealed class HeaderOperatorAuthenticator : IOperatorAuthenticator
{
    public const string OperatorHeader = "X-Test-Operator";
    public const string RolesHeader = "X-Test-Roles";

    public ValueTask<OperatorIdentity?> AuthenticateAsync(HttpContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        if (!Guid.TryParse(context.Request.Headers[OperatorHeader].ToString(), out var operatorId))
        {
            return ValueTask.FromResult<OperatorIdentity?>(null);
        }

        var roles = context.Request.Headers[RolesHeader].ToString().Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return ValueTask.FromResult<OperatorIdentity?>(new OperatorIdentity(operatorId, roles));
    }
}

/// <summary>The real API over a migrated PostgreSQL 17 with a fake KMS, a temporary snapshot directory and a test operator.</summary>
public sealed class CatalogContractFixture : IAsyncLifetime
{
    public const string BaseUrl = "https://api.zaghlol.test";
    public const string EditorRole = "catalog_editor";

    public static readonly Guid OperatorId = Guid.Parse("5f0c1c3a-0b7e-4f64-9c1d-7f2b1a2c3d4e");

    private readonly FakeKms kms = FakeKms.CreateDefault();
    private ZaghlolTestDatabase? database;
    private WebApplicationFactory<Program>? factory;

    public HttpClient Client { get; private set; } = null!;

    public string SnapshotDirectory { get; } = Path.Combine(Path.GetTempPath(), "zaghlol-catalog-" + Guid.NewGuid().ToString("N"));

    public string Superuser => database!.Superuser;

    public IReadOnlyList<SigningKey> SigningKeys => kms.Keys;

    public IServiceProvider Services => factory!.Services;

    public async Task InitializeAsync()
    {
        var db = await ZaghlolTestDatabase.StartAsync();
        database = db;
        await ZaghlolTestDatabase.ExecuteAsync(
            db.Superuser,
            $"INSERT INTO zaghlol.operators (id, oidc_subject, display_name, roles) VALUES ('{OperatorId}', 'test-subject', 'Test Operator', ARRAY['{EditorRole}'])");
        factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseSetting("ConnectionStrings:App", db.Api);
            builder.UseSetting("ConnectionStrings:Admin", db.Admin);
            builder.UseSetting("Catalog:Snapshots:Directory", SnapshotDirectory);
            builder.UseSetting("Catalog:Snapshots:BaseUrl", BaseUrl);
            foreach (var (key, value) in kms.Settings())
            {
                builder.UseSetting(key, value);
            }

            builder.ConfigureServices(services =>
            {
                kms.Use(services);
                services.RemoveAll<IOperatorAuthenticator>();
                services.AddSingleton<IOperatorAuthenticator, HeaderOperatorAuthenticator>();
            });
        });
        Client = factory.CreateClient();
    }

    public async Task DisposeAsync()
    {
        Client?.Dispose();
        if (factory is not null)
        {
            await factory.DisposeAsync();
        }

        if (database is not null)
        {
            await database.DisposeAsync();
        }

        kms.Dispose();
        if (Directory.Exists(SnapshotDirectory))
        {
            Directory.Delete(SnapshotDirectory, recursive: true);
        }
    }
}

/// <summary>
/// T-125 acceptance and FU-011: the catalog admin operations and <c>getFullCatalog</c> against the real API, a real
/// PostgreSQL and the OpenAPI document. Every status an operation answers is declared by it and every body validates against
/// its schema. One class, so the tests run one after another over the shared database; each uses names of its own.
/// </summary>
public class CatalogLiveContractTests(CatalogContractFixture fixture) : IClassFixture<CatalogContractFixture>
{
    private const string Json = "application/json";
    private const string Problem = "application/problem+json";

    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private static SpecOperation ListDraft => Operation("adminListCatalogDraft");

    private static SpecOperation Create => Operation("adminCreateDraftMerchant");

    private static SpecOperation Put => Operation("adminPutCatalogDraftEntry");

    private static SpecOperation Delete => Operation("adminDeleteCatalogDraftEntry");

    private static SpecOperation Publish => Operation("adminPublishCatalog");

    private static SpecOperation Full => Operation("getFullCatalog");

    [Fact]
    public async Task WithoutAnOperatorEveryAdminOperationIs401AndWithoutTheRoleIs403()
    {
        using var anonymous = await SendAsync(HttpMethod.Get, "/admin/v1/catalog/draft/categories", roles: null);
        using var wrongRole = await SendAsync(HttpMethod.Post, "/admin/v1/catalog/publish", "{}", roles: "flags_admin");
        using var anonymousPut = await SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/categories/dining", CategoryBody, roles: null);

        var unauthorized = await AssertDeclared(anonymous, ListDraft, HttpStatusCode.Unauthorized, Problem);
        var forbidden = await AssertDeclared(wrongRole, Publish, HttpStatusCode.Forbidden, Problem);
        await AssertDeclared(anonymousPut, Put, HttpStatusCode.Unauthorized, Problem);
        Assert.Equal("UNAUTHORIZED", unauthorized!["code"]!.GetValue<string>());
        Assert.Equal("FORBIDDEN", forbidden!["code"]!.GetValue<string>());
        Assert.Equal("Bearer", anonymous.Headers.WwwAuthenticate.ToString());
    }

    [Fact]
    public async Task PutAndPostAnswerTheDeclaredOpsAndTheListShowsThem()
    {
        var category = Unique("c");
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(Put)!, JsonNode.Parse(CategoryBody)));
        using var putCategory = await SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/categories/" + category, CategoryBody);
        var categoryOp = await AssertDeclared(putCategory, Put, HttpStatusCode.OK, Json);
        Assert.Equal("category", categoryOp!["t"]!.GetValue<string>());
        Assert.Equal(category, categoryOp["code"]!.GetValue<string>());
        Assert.True(putCategory.Headers.CacheControl?.NoStore);

        var merchantBody = MerchantBody(Unique("Merchant "), category);
        Assert.Null(Spec.Validate(OpenApiSpec.RequestSchema(Create)!, JsonNode.Parse(merchantBody)));
        using var createMerchant = await SendAsync(HttpMethod.Post, "/admin/v1/catalog/draft/merchants", merchantBody);
        var merchantOp = await AssertDeclared(createMerchant, Create, HttpStatusCode.Created, Json);
        var id = merchantOp!["id"]!.GetValue<int>();
        Assert.Equal("merchant", merchantOp["t"]!.GetValue<string>());

        using var putMerchant = await SendAsync(HttpMethod.Put, $"/admin/v1/catalog/draft/merchants/{id}", MerchantBody(Unique("Merchant "), category));
        await AssertDeclared(putMerchant, Put, HttpStatusCode.OK, Json);

        var alias = AliasPath(id, "koshary el tahrir");
        using var putAlias = await SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/aliases/" + alias, "{\"match\":\"prefix\"}");
        var aliasOp = await AssertDeclared(putAlias, Put, HttpStatusCode.OK, Json);
        Assert.Equal("prefix", aliasOp!["match"]!.GetValue<string>());

        using var putKeyword = await SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/keywords/en:" + CatalogKeys.EncodeText("pharmacy shop"), $"{{\"category\":\"{category}\",\"weight\":40}}");
        await AssertDeclared(putKeyword, Put, HttpStatusCode.OK, Json);

        using var list = await SendAsync(HttpMethod.Get, "/admin/v1/catalog/draft/merchants?limit=500");
        var page = await AssertDeclared(list, ListDraft, HttpStatusCode.OK, Json);
        Assert.Contains(page!["items"]!.AsArray(), item => item!["id"]!.GetValue<int>() == id);
    }

    [Fact]
    public async Task TheDraftListPagesWithAnOpaqueCursor()
    {
        var category = await NewCategoryAsync();
        var first = await NewMerchantAsync(category);
        var second = await NewMerchantAsync(category);

        using var firstPage = await SendAsync(HttpMethod.Get, "/admin/v1/catalog/draft/merchants?limit=1");
        var one = await AssertDeclared(firstPage, ListDraft, HttpStatusCode.OK, Json);
        var cursor = one!["nextCursor"]!.GetValue<string>();
        Assert.Single(one["items"]!.AsArray());

        using var secondPage = await SendAsync(HttpMethod.Get, "/admin/v1/catalog/draft/merchants?limit=500&cursor=" + cursor);
        var rest = await AssertDeclared(secondPage, ListDraft, HttpStatusCode.OK, Json);
        var ids = rest!["items"]!.AsArray().Select(i => i!["id"]!.GetValue<int>()).ToList();
        var firstId = one["items"]![0]!["id"]!.GetValue<int>();
        Assert.DoesNotContain(firstId, ids);
        Assert.Contains(second, ids);
        Assert.True(firstId == first || ids.Contains(first));
        Assert.Null(rest["nextCursor"]);
    }

    [Theory]
    [InlineData("/admin/v1/catalog/draft/places")]
    [InlineData("/admin/v1/catalog/draft/merchants?limit=0")]
    [InlineData("/admin/v1/catalog/draft/merchants?limit=501")]
    [InlineData("/admin/v1/catalog/draft/merchants?cursor=x")]
    [InlineData("/admin/v1/catalog/draft/merchants?cursor=-1")]
    public async Task AnInvalidEntityLimitOrCursorIs400(string path)
    {
        using var response = await SendAsync(HttpMethod.Get, path);

        var body = await AssertDeclared(response, ListDraft, HttpStatusCode.BadRequest, Problem);
        Assert.Equal("VALIDATION_FAILED", body!["code"]!.GetValue<string>());
    }

    [Fact]
    public async Task ConflictsAndMissingKeysAreTheDeclaredProblems()
    {
        var category = await NewCategoryAsync();

        using var unknownCategory = await SendAsync(HttpMethod.Post, "/admin/v1/catalog/draft/merchants", MerchantBody(Unique("M "), "nocategory"));
        using var noMerchantPut = await SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/merchants/987654321", MerchantBody(Unique("M "), category));
        using var aliasOfNobody = await SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/aliases/" + AliasPath(987654321, "nobody"), "{\"match\":\"exact\"}");
        using var missingDelete = await SendAsync(HttpMethod.Delete, "/admin/v1/catalog/draft/categories/" + Unique("c"));
        var canonical = Unique("Twin ");
        using var first = await SendAsync(HttpMethod.Post, "/admin/v1/catalog/draft/merchants", MerchantBody(canonical, category));
        using var twin = await SendAsync(HttpMethod.Post, "/admin/v1/catalog/draft/merchants", MerchantBody(canonical, category));

        var conflict = await AssertDeclared(unknownCategory, Create, HttpStatusCode.Conflict, Problem);
        Assert.Equal("ADMIN_CONFLICT", conflict!["code"]!.GetValue<string>());
        var notFound = await AssertDeclared(noMerchantPut, Put, HttpStatusCode.NotFound, Problem);
        Assert.Equal("NOT_FOUND", notFound!["code"]!.GetValue<string>());
        await AssertDeclared(aliasOfNobody, Put, HttpStatusCode.Conflict, Problem);
        await AssertDeclared(missingDelete, Delete, HttpStatusCode.NotFound, Problem);
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        await AssertDeclared(twin, Create, HttpStatusCode.Conflict, Problem);
    }

    [Fact]
    public async Task BodiesAreStrictAndKeysNeverBelongInThem()
    {
        var category = await NewCategoryAsync();
        var path = "/admin/v1/catalog/draft/categories/" + category;

        using var extra = await SendAsync(HttpMethod.Put, path, CategoryBody.Replace("\"sort\":1", "\"sort\":1,\"code\":\"x\"", StringComparison.Ordinal));
        using var missing = await SendAsync(HttpMethod.Put, path, "{\"nameAr\":\"x\"}");
        using var badColor = await SendAsync(HttpMethod.Put, path, CategoryBody.Replace("#0F7A55", "green", StringComparison.Ordinal));
        using var wrongShape = await SendAsync(HttpMethod.Put, path, "{\"match\":\"exact\"}");
        using var wrongType = await SendAsync(HttpMethod.Put, path, CategoryBody, contentType: "text/plain");
        using var tooLarge = await SendAsync(HttpMethod.Put, path, "{\"nameAr\":\"" + new string('a', 70_000) + "\"}");
        using var badKey = await SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/categories/Not-A-Code", CategoryBody);
        using var badEntity = await SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/places/" + category, CategoryBody);

        var unknown = await AssertDeclared(extra, Put, HttpStatusCode.BadRequest, Problem);
        Assert.Equal("UNKNOWN_FIELD", unknown!["code"]!.GetValue<string>());
        foreach (var response in new[] { missing, badColor, wrongShape, badKey, badEntity })
        {
            var body = await AssertDeclared(response, Put, HttpStatusCode.BadRequest, Problem);
            Assert.Equal("VALIDATION_FAILED", body!["code"]!.GetValue<string>());
        }

        await AssertDeclared(wrongType, Put, HttpStatusCode.UnsupportedMediaType, Problem);
        await AssertDeclared(tooLarge, Put, HttpStatusCode.RequestEntityTooLarge, Problem);
    }

    [Fact]
    public async Task NonCanonicalAliasKeysAreRejectedAndAKeywordKeyRoundTrips()
    {
        var category = await NewCategoryAsync();
        var id = await NewMerchantAsync(category);
        var body = "{\"match\":\"exact\"}";
        var canonical = CatalogKeys.EncodeText("koshary el tahrir");

        using var padded = await SendAsync(HttpMethod.Put, $"/admin/v1/catalog/draft/aliases/{id}:{canonical}=", body);
        using var trailingBits = await SendAsync(HttpMethod.Put, $"/admin/v1/catalog/draft/aliases/{id}:{canonical[..^1]}J", body);
        using var notNormalized = await SendAsync(HttpMethod.Put, $"/admin/v1/catalog/draft/aliases/{id}:{CatalogKeys.EncodeText("Koshary El Tahrir")}", body);
        using var accepted = await SendAsync(HttpMethod.Put, $"/admin/v1/catalog/draft/aliases/{id}:{canonical}", body);

        foreach (var response in new[] { padded, trailingBits, notNormalized })
        {
            var problem = await AssertDeclared(response, Put, HttpStatusCode.BadRequest, Problem);
            Assert.Equal("VALIDATION_FAILED", problem!["code"]!.GetValue<string>());
        }

        await AssertDeclared(accepted, Put, HttpStatusCode.OK, Json);

        using var keyword = await SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/keywords/ar:2LXZitiv2YTZitip", $"{{\"category\":\"{category}\",\"weight\":70}}");
        var op = await AssertDeclared(keyword, Put, HttpStatusCode.OK, Json);
        Assert.Equal("صيدلية", op!["keyword"]!.GetValue<string>());
        Assert.Equal("ar", op["lang"]!.GetValue<string>());

        using var list = await SendAsync(HttpMethod.Get, "/admin/v1/catalog/draft/keywords?limit=500");
        var page = await AssertDeclared(list, ListDraft, HttpStatusCode.OK, Json);
        Assert.Contains(page!["items"]!.AsArray(), item => item!["keyword"]!.GetValue<string>() == "صيدلية");
    }

    [Fact]
    public async Task DeletingAReferencedCategoryIs409AdminConflictUntilNothingUsesIt()
    {
        var category = await NewCategoryAsync();
        var merchant = await NewMerchantAsync(category);
        var keywordPath = "/admin/v1/catalog/draft/keywords/en:" + CatalogKeys.EncodeText("pizza place");
        using var keyword = await SendAsync(HttpMethod.Put, keywordPath, $"{{\"category\":\"{category}\",\"weight\":10}}");
        Assert.Equal(HttpStatusCode.OK, keyword.StatusCode);
        var categoryPath = "/admin/v1/catalog/draft/categories/" + category;

        using var usedByMerchant = await SendAsync(HttpMethod.Delete, categoryPath);
        using var deleteMerchant = await SendAsync(HttpMethod.Delete, $"/admin/v1/catalog/draft/merchants/{merchant}");
        using var usedByKeyword = await SendAsync(HttpMethod.Delete, categoryPath);
        using var deleteKeyword = await SendAsync(HttpMethod.Delete, keywordPath);
        using var free = await SendAsync(HttpMethod.Delete, categoryPath);
        using var merchantAfter = await SendAsync(HttpMethod.Post, "/admin/v1/catalog/draft/merchants", MerchantBody(Unique("M "), category));

        var conflict = await AssertDeclared(usedByMerchant, Delete, HttpStatusCode.Conflict, Problem);
        Assert.Equal("ADMIN_CONFLICT", conflict!["code"]!.GetValue<string>());
        await AssertDeclared(deleteMerchant, Delete, HttpStatusCode.NoContent, string.Empty);
        await AssertDeclared(usedByKeyword, Delete, HttpStatusCode.Conflict, Problem);
        Assert.Equal(HttpStatusCode.NoContent, deleteKeyword.StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, free.StatusCode);
        await AssertDeclared(merchantAfter, Create, HttpStatusCode.Conflict, Problem);
    }

    [Fact]
    public async Task DeletingAMerchantListsItsAliasDeletesBeforeTheMerchantDeleteInTheNextDelta()
    {
        var category = await NewCategoryAsync();
        var merchant = await NewMerchantAsync(category);
        foreach (var alias in new[] { "alpha shop", "beta shop" })
        {
            using var put = await SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/aliases/" + AliasPath(merchant, alias), "{\"match\":\"exact\"}");
            Assert.Equal(HttpStatusCode.OK, put.StatusCode);
        }

        var first = await PublishAsync();
        var snapshot = await FetchSnapshotAsync(first);
        Assert.Contains(Ops(snapshot.Body), op => op["t"]!.GetValue<string>() == "merchant" && op["id"]!.GetValue<int>() == merchant);

        using var delete = await SendAsync(HttpMethod.Delete, $"/admin/v1/catalog/draft/merchants/{merchant}");
        Assert.Equal(HttpStatusCode.NoContent, delete.StatusCode);
        using var aliases = await SendAsync(HttpMethod.Get, "/admin/v1/catalog/draft/aliases?limit=500");
        Assert.DoesNotContain(
            (await AssertDeclared(aliases, ListDraft, HttpStatusCode.OK, Json))!["items"]!.AsArray(),
            item => item!["merchantId"]!.GetValue<int>() == merchant);
        var second = await PublishAsync();

        var reader = fixture.Services.GetRequiredService<ICatalogReader>();
        var delta = await reader.DeltaAsync(first, second, CancellationToken.None);
        var forMerchant = delta.Where(op => op.Key.MerchantId == merchant && op.Key.Entity is CatalogEntity.Aliases or CatalogEntity.Merchants).ToList();
        Assert.Equal(
            new[] { "-aliases/" + merchant + ":alpha shop", "-aliases/" + merchant + ":beta shop", "-merchants/" + merchant },
            forMerchant.Select(op => (op.Delete ? "-" : "+") + CatalogEntities.Name(op.Key.Entity) + "/" + op.Key.StorageKey));
        Assert.All(forMerchant, op => Assert.True(op.Delete));

        var later = await FetchSnapshotAsync(second);
        Assert.DoesNotContain(Ops(later.Body), op => op["t"]!.GetValue<string>() == "merchant" && op["id"]!.GetValue<int>() == merchant);
    }

    [Fact]
    public async Task APublishedDeleteIsATombstoneThatAPutRevivesAndANeverPublishedDeleteVanishes()
    {
        var kept = await NewCategoryAsync();
        var first = await PublishAsync();

        using var tombstone = await SendAsync(HttpMethod.Delete, "/admin/v1/catalog/draft/categories/" + kept);
        Assert.Equal(HttpStatusCode.NoContent, tombstone.StatusCode);
        using var listed = await SendAsync(HttpMethod.Get, "/admin/v1/catalog/draft/categories?limit=500");
        Assert.DoesNotContain(
            (await AssertDeclared(listed, ListDraft, HttpStatusCode.OK, Json))!["items"]!.AsArray(),
            item => item!["code"]!.GetValue<string>() == kept);
        using var again = await SendAsync(HttpMethod.Delete, "/admin/v1/catalog/draft/categories/" + kept);
        Assert.Equal(HttpStatusCode.NotFound, again.StatusCode);

        var second = await PublishAsync();
        var reader = fixture.Services.GetRequiredService<ICatalogReader>();
        var delta = await reader.DeltaAsync(first, second, CancellationToken.None);
        Assert.Contains(delta, op => op.Delete && op.Key.Code == kept);

        using var revive = await SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/categories/" + kept, CategoryBody);
        Assert.Equal(HttpStatusCode.OK, revive.StatusCode);
        var third = await PublishAsync();
        var revived = await reader.DeltaAsync(second, third, CancellationToken.None);
        Assert.Contains(revived, op => !op.Delete && op.Key.Code == kept);

        var neverPublished = await NewCategoryAsync();
        using var removed = await SendAsync(HttpMethod.Delete, "/admin/v1/catalog/draft/categories/" + neverPublished);
        Assert.Equal(HttpStatusCode.NoContent, removed.StatusCode);
        Assert.Equal(0L, await ScalarAsync($"SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'categories' AND entry_key = '{neverPublished}'"));
    }

    [Fact]
    public async Task ThePublishedSnapshotIsSignedAndVerifiesWithTheAppSideRules()
    {
        var category = await NewCategoryAsync();
        var merchant = await NewMerchantAsync(category);
        var version = await PublishAsync("November refresh");

        var snapshot = await FetchSnapshotAsync(version);

        Assert.Equal(version, snapshot.Body["version"]!.GetValue<int>());
        Assert.All(Ops(snapshot.Body), op => Assert.Equal("upsert", op["op"]!.GetValue<string>()));
        Assert.Contains(Ops(snapshot.Body), op => op["t"]!.GetValue<string>() == "merchant" && op["id"]!.GetValue<int>() == merchant);
        var jwks = JsonNode.Parse(EcPublicJwk.ToJwks(fixture.SigningKeys))!;
        Assert.True(ReferenceVerifiers.VerifyResponse(jwks, snapshot.Bytes, snapshot.Signature));

        var tampered = (byte[])snapshot.Bytes.Clone();
        tampered[^3] ^= 0x01;
        Assert.False(ReferenceVerifiers.VerifyResponse(jwks, tampered, snapshot.Signature));

        // The stored objects: the gzip decompresses to the served bytes and the .sig file verifies over them.
        var folder = Path.Combine(fixture.SnapshotDirectory, "catalog", version.ToString(CultureInfo.InvariantCulture));
        await using (var file = File.OpenRead(Path.Combine(folder, "full.json.gz")))
        await using (var gzip = new GZipStream(file, CompressionMode.Decompress))
        await using (var plain = new MemoryStream())
        {
            await gzip.CopyToAsync(plain);
            Assert.Equal(snapshot.Bytes, plain.ToArray());
        }

        var stored = await File.ReadAllTextAsync(Path.Combine(folder, "full.json.sig"));
        Assert.True(ReferenceVerifiers.VerifyResponse(jwks, snapshot.Bytes, stored));

        // catalog_versions: hash of the JSON, the public URL and the note.
        Assert.Equal(
            Convert.ToHexStringLower(SHA256.HashData(snapshot.Bytes)),
            await ScalarAsync($"SELECT encode(full_snapshot_sha256, 'hex') FROM zaghlol.catalog_versions WHERE version = {version}"));
        Assert.Equal(
            $"{CatalogContractFixture.BaseUrl}/v1/catalog/{version}/full",
            await ScalarAsync($"SELECT full_snapshot_url FROM zaghlol.catalog_versions WHERE version = {version}"));
        Assert.Equal("November refresh", await ScalarAsync($"SELECT notes FROM zaghlol.catalog_versions WHERE version = {version}"));
        Assert.Equal(CatalogContractFixture.OperatorId.ToString("D"), await ScalarAsync($"SELECT published_by::text FROM zaghlol.catalog_versions WHERE version = {version}"));
    }

    [Fact]
    public async Task TheFullEndpointIsPublicImmutableAndDeclaresItsStatuses()
    {
        var version = await PublishAsync();

        using var ok = await fixture.Client.GetAsync($"/v1/catalog/{version}/full");
        using var unknown = await fixture.Client.GetAsync("/v1/catalog/987654/full");
        using var zero = await fixture.Client.GetAsync("/v1/catalog/0/full");

        var body = await AssertDeclared(ok, Full, HttpStatusCode.OK, Json);
        Assert.Equal(version, body!["version"]!.GetValue<int>());
        Assert.Matches(Spec.Root["components"]!["headers"]!["ZaghlolSignature"]!["schema"]!["pattern"]!.GetValue<string>(), ok.Headers.GetValues("Zaghlol-Signature").Single());
        Assert.Contains("immutable", ok.Headers.CacheControl?.ToString(), StringComparison.Ordinal);
        foreach (var response in new[] { unknown, zero })
        {
            var problem = await AssertDeclared(response, Full, HttpStatusCode.NotFound, Problem);
            Assert.Equal("CATALOG_VERSION_UNKNOWN", problem!["code"]!.GetValue<string>());
        }
    }

    [Fact]
    public async Task AnUpToDateClientGetsAnEmptyDelta()
    {
        await NewCategoryAsync();
        var latest = await PublishAsync();
        var reader = fixture.Services.GetRequiredService<ICatalogReader>();

        Assert.Equal(latest, await reader.LatestVersionAsync(CancellationToken.None));
        Assert.Empty(await reader.DeltaAsync(latest, latest, CancellationToken.None));
        Assert.Empty(await reader.DeltaAsync(latest + 5, latest, CancellationToken.None));
        Assert.NotEmpty(await reader.DeltaAsync(latest - 1, latest, CancellationToken.None));
    }

    [Fact]
    public async Task PublishWithNothingChangedIs409AndTheNoteIsBounded()
    {
        await NewCategoryAsync();
        await PublishAsync();

        using var nothing = await SendAsync(HttpMethod.Post, "/admin/v1/catalog/publish", "{}");
        using var longNote = await SendAsync(HttpMethod.Post, "/admin/v1/catalog/publish", "{\"note\":\"" + new string('n', 201) + "\"}");
        using var unknownField = await SendAsync(HttpMethod.Post, "/admin/v1/catalog/publish", "{\"title\":\"x\"}");
        using var wrongType = await SendAsync(HttpMethod.Post, "/admin/v1/catalog/publish", "{}", contentType: "text/plain");

        var conflict = await AssertDeclared(nothing, Publish, HttpStatusCode.Conflict, Problem);
        Assert.Equal("ADMIN_CONFLICT", conflict!["code"]!.GetValue<string>());
        var invalid = await AssertDeclared(longNote, Publish, HttpStatusCode.BadRequest, Problem);
        Assert.Equal("VALIDATION_FAILED", invalid!["code"]!.GetValue<string>());
        var unknown = await AssertDeclared(unknownField, Publish, HttpStatusCode.BadRequest, Problem);
        Assert.Equal("UNKNOWN_FIELD", unknown!["code"]!.GetValue<string>());
        await AssertDeclared(wrongType, Publish, HttpStatusCode.UnsupportedMediaType, Problem);
    }

    [Fact]
    public async Task APutThatChangesNothingDoesNotMakeTheNextPublishHappen()
    {
        var category = await NewCategoryAsync();
        await PublishAsync();

        using var same = await SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/categories/" + category, CategoryBody);
        Assert.Equal(HttpStatusCode.OK, same.StatusCode);
        using var nothing = await SendAsync(HttpMethod.Post, "/admin/v1/catalog/publish", "{}");
        Assert.Equal(HttpStatusCode.Conflict, nothing.StatusCode);

        using var changed = await SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/categories/" + category, CategoryBody.Replace("\"sort\":1", "\"sort\":2", StringComparison.Ordinal));
        Assert.Equal(HttpStatusCode.OK, changed.StatusCode);
        Assert.True(await PublishAsync() > 0);
    }

    [Fact]
    public async Task EveryAdminWriteIsAuditedWithTheOperatorAndNoIdentifiers()
    {
        var category = Unique("c");
        using var put = await SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/categories/" + category, CategoryBody);
        Assert.Equal(HttpStatusCode.OK, put.StatusCode);
        using var delete = await SendAsync(HttpMethod.Delete, "/admin/v1/catalog/draft/categories/" + category);
        Assert.Equal(HttpStatusCode.NoContent, delete.StatusCode);
        var version = await PublishAsync();

        var operatorId = CatalogContractFixture.OperatorId.ToString("D");
        Assert.Equal(1L, await ScalarAsync($"SELECT count(*) FROM zaghlol.audit_log WHERE action = 'catalog_draft_put' AND target = 'categories/{category}' AND operator_id = '{operatorId}'"));
        Assert.Equal(1L, await ScalarAsync($"SELECT count(*) FROM zaghlol.audit_log WHERE action = 'catalog_draft_delete' AND target = 'categories/{category}' AND operator_id = '{operatorId}'"));
        Assert.Equal(1L, await ScalarAsync($"SELECT count(*) FROM zaghlol.audit_log WHERE action = 'catalog_publish' AND target = 'catalog/{version}' AND operator_id = '{operatorId}'"));
        Assert.Equal(0L, await ScalarAsync("SELECT count(*) FROM zaghlol.audit_log WHERE action LIKE 'catalog_%' AND (details::text LIKE '%@%' OR target LIKE '%@%')"));
    }

    [Fact]
    public async Task ASeedFileLoadsIntoTheDraftInOneTransactionAndPublishes()
    {
        var suffix = Guid.NewGuid().ToString("N")[..8];
        var category = "seed" + suffix;
        var csv = "entity,code,nameAr,nameEn,icon,color,bucket,sort,canonical,category,alias,match,keyword,lang,weight\n"
            + $"category,{category},مطاعم,Seed {suffix},restaurant,#FFB86B,wants,3,,,,,,,\n"
            + $"merchant,,مطعم,,,,,,Seed Diner {suffix},{category},,,,,\n"
            + $"alias,,,,,,,,Seed Diner {suffix},,seed diner {suffix},exact,,,\n"
            + $"alias,,,,,,,,Seed Diner {suffix},,diner {suffix},prefix,,,\n"
            + $"keyword,,,,,,,,,{category},,,seed menu {suffix},en,55\n";
        var store = fixture.Services.GetRequiredService<ICatalogAdminStore>();

        var result = await store.ImportSeedAsync(CatalogContractFixture.OperatorId, CatalogSeedCsv.Parse(csv), CancellationToken.None);
        var again = await store.ImportSeedAsync(CatalogContractFixture.OperatorId, CatalogSeedCsv.Parse(csv), CancellationToken.None);

        Assert.Equal(new SeedImportResult(1, 1, 2, 1), result);
        Assert.Equal(result, again);
        Assert.Equal(1L, await ScalarAsync($"SELECT count(*) FROM zaghlol.catalog_drafts WHERE entity = 'merchants' AND body ->> 'canonical' = 'Seed Diner {suffix}'"));
        var version = await PublishAsync();
        var ops = Ops((await FetchSnapshotAsync(version)).Body);
        Assert.Contains(ops, op => op["t"]!.GetValue<string>() == "category" && op["code"]!.GetValue<string>() == category);
        Assert.Equal(2, ops.Count(op => op["t"]!.GetValue<string>() == "alias" && op["alias"]!.GetValue<string>().EndsWith(suffix, StringComparison.Ordinal)));
        Assert.Contains(ops, op => op["t"]!.GetValue<string>() == "keyword" && op["keyword"]!.GetValue<string>() == "seed menu " + suffix);
        Assert.Equal(2L, await ScalarAsync($"SELECT count(*) FROM zaghlol.audit_log WHERE action = 'catalog_seed_import' AND operator_id = '{CatalogContractFixture.OperatorId:D}' AND details ->> 'aliases' = '2' AND details ->> 'merchants' = '1'"));
    }

    [Fact]
    public async Task ASeedRowThatConflictsRollsTheWholeImportBack()
    {
        var suffix = Guid.NewGuid().ToString("N")[..8];
        var csv = "entity,code,nameAr,nameEn,icon,color,bucket,sort,canonical,category,alias,match,keyword,lang,weight\n"
            + $"merchant,,مطعم,,,,,,Orphan {suffix},nosuchcategory{suffix},,,,,\n";
        var store = fixture.Services.GetRequiredService<ICatalogAdminStore>();

        await Assert.ThrowsAsync<CatalogSeedFormatException>(() => store.ImportSeedAsync(CatalogContractFixture.OperatorId, CatalogSeedCsv.Parse(csv), CancellationToken.None));

        Assert.Equal(0L, await ScalarAsync($"SELECT count(*) FROM zaghlol.catalog_drafts WHERE body ->> 'canonical' = 'Orphan {suffix}'"));
    }

    private static string CategoryBody =>
        "{\"nameAr\":\"اختبار\",\"nameEn\":\"Test\",\"icon\":\"tag\",\"color\":\"#0F7A55\",\"bucket\":\"wants\",\"sort\":1}";

    private static SpecOperation Operation(string id) => Spec.Operations().Single(o => o.Id == id);

    private static string Unique(string prefix) => prefix + Guid.NewGuid().ToString("N")[..10];

    private static string MerchantBody(string canonical, string category) =>
        "{\"canonical\":\"" + canonical + "\",\"nameAr\":\"مطعم\",\"category\":\"" + category + "\"}";

    private static string AliasPath(int merchantId, string alias) =>
        merchantId.ToString(CultureInfo.InvariantCulture) + ":" + CatalogKeys.EncodeText(alias);

    private static IEnumerable<JsonNode> Ops(JsonNode snapshot) => snapshot["ops"]!.AsArray().Select(op => op!);

    private async Task<string> NewCategoryAsync()
    {
        var code = Unique("c");
        using var response = await SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/categories/" + code, CategoryBody);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return code;
    }

    private async Task<int> NewMerchantAsync(string category)
    {
        using var response = await SendAsync(HttpMethod.Post, "/admin/v1/catalog/draft/merchants", MerchantBody(Unique("Merchant "), category));
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return JsonNode.Parse(await response.Content.ReadAsStringAsync())!["id"]!.GetValue<int>();
    }

    private async Task<int> PublishAsync(string? note = null)
    {
        var body = note is null ? "{}" : "{\"note\":\"" + note + "\"}";
        using var response = await SendAsync(HttpMethod.Post, "/admin/v1/catalog/publish", body);
        var published = await AssertDeclared(response, Publish, HttpStatusCode.OK, Json);
        var version = published!["version"]!.GetValue<int>();
        Assert.Equal($"{CatalogContractFixture.BaseUrl}/v1/catalog/{version}/full", published["snapshotUrl"]!.GetValue<string>());
        Assert.EndsWith("Z", published["publishedAt"]!.GetValue<string>(), StringComparison.Ordinal);
        return version;
    }

    private async Task<(JsonNode Body, byte[] Bytes, string Signature)> FetchSnapshotAsync(int version)
    {
        using var response = await fixture.Client.GetAsync($"/v1/catalog/{version}/full");
        var bytes = await response.Content.ReadAsByteArrayAsync();
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return (JsonNode.Parse(bytes)!, bytes, response.Headers.GetValues("Zaghlol-Signature").Single());
    }

    private async Task<HttpResponseMessage> SendAsync(HttpMethod method, string path, string? body = null, string? roles = CatalogContractFixture.EditorRole, string contentType = Json)
    {
        using var request = new HttpRequestMessage(method, path);
        if (roles is not null)
        {
            request.Headers.Add(HeaderOperatorAuthenticator.OperatorHeader, CatalogContractFixture.OperatorId.ToString("D"));
            request.Headers.Add(HeaderOperatorAuthenticator.RolesHeader, roles);
        }

        if (body is not null)
        {
            request.Content = new StringContent(body, Encoding.UTF8);
            request.Content.Headers.ContentType = new MediaTypeHeaderValue(contentType);
        }

        return await fixture.Client.SendAsync(request);
    }

    private async Task<object?> ScalarAsync(string sql)
    {
        await using var connection = new NpgsqlConnection(fixture.Superuser);
        await connection.OpenAsync();
        await using var command = new NpgsqlCommand(sql, connection);
        return await command.ExecuteScalarAsync();
    }

    private static async Task<JsonNode?> AssertDeclared(HttpResponseMessage response, SpecOperation operation, HttpStatusCode status, string mediaType)
    {
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(status == response.StatusCode, $"expected {(int)status}, got {(int)response.StatusCode}: {text}");
        var code = ((int)status).ToString(CultureInfo.InvariantCulture);
        Assert.True(operation.Body["responses"]!.AsObject().ContainsKey(code), $"{operation.Label} does not declare {code}");
        if (mediaType.Length == 0)
        {
            Assert.Empty(text);
            return null;
        }

        Assert.Equal(mediaType, response.Content.Headers.ContentType?.MediaType);
        var schema = Spec.ResponseSchema(operation, code, mediaType);
        Assert.NotNull(schema);
        var body = JsonNode.Parse(text);
        Assert.Null(Spec.Validate(schema, body));
        return body;
    }
}

/// <summary>
/// T-123 I-5: a full snapshot larger than the default 1 MiB signing buffer is published, served and signed (the cap for this
/// endpoint is <see cref="CatalogLimits.MaxSnapshotBytes"/>). Its own fixture, so the large catalog stays out of the other tests.
/// </summary>
public class CatalogLargeSnapshotTests(CatalogContractFixture fixture) : IClassFixture<CatalogContractFixture>
{
    private const int Aliases = 16_000;

    [Fact]
    public async Task ASnapshotOverOneMebibyteIsServedAndStillVerifies()
    {
        var category = "large" + Guid.NewGuid().ToString("N")[..8];
        using var put = await SendAsync(HttpMethod.Put, "/admin/v1/catalog/draft/categories/" + category, "{\"nameAr\":\"x\",\"nameEn\":\"x\",\"icon\":\"x\",\"color\":\"#0F7A55\",\"bucket\":\"wants\",\"sort\":1}");
        Assert.Equal(HttpStatusCode.OK, put.StatusCode);
        using var post = await SendAsync(HttpMethod.Post, "/admin/v1/catalog/draft/merchants", "{\"canonical\":\"Large " + category + "\",\"nameAr\":\"x\",\"category\":\"" + category + "\"}");
        Assert.Equal(HttpStatusCode.Created, post.StatusCode);
        var merchant = JsonNode.Parse(await post.Content.ReadAsStringAsync())!["id"]!.GetValue<int>();
        await ZaghlolTestDatabase.ExecuteAsync(
            fixture.Superuser,
            "INSERT INTO zaghlol.catalog_drafts (entity, entry_key, body, deleted, published, changed) "
            + $"SELECT 'aliases', '{merchant}:large alias number ' || g, '{{\"match\":\"exact\"}}'::jsonb, false, false, true FROM generate_series(1, {Aliases}) g");

        using var publish = await SendAsync(HttpMethod.Post, "/admin/v1/catalog/publish", "{}");
        Assert.Equal(HttpStatusCode.OK, publish.StatusCode);
        var version = JsonNode.Parse(await publish.Content.ReadAsStringAsync())!["version"]!.GetValue<int>();

        using var response = await fixture.Client.GetAsync($"/v1/catalog/{version}/full");
        var bytes = await response.Content.ReadAsByteArrayAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(bytes.Length > 1024 * 1024, $"snapshot was only {bytes.Length} bytes");
        Assert.True(bytes.Length < CatalogLimits.MaxSnapshotBytes);
        var jwks = JsonNode.Parse(EcPublicJwk.ToJwks(fixture.SigningKeys))!;
        Assert.True(ReferenceVerifiers.VerifyResponse(jwks, bytes, response.Headers.GetValues("Zaghlol-Signature").Single()));
        Assert.True(JsonNode.Parse(bytes)!["ops"]!.AsArray().Count > Aliases);
    }

    private async Task<HttpResponseMessage> SendAsync(HttpMethod method, string path, string body)
    {
        using var request = new HttpRequestMessage(method, path);
        request.Headers.Add(HeaderOperatorAuthenticator.OperatorHeader, CatalogContractFixture.OperatorId.ToString("D"));
        request.Headers.Add(HeaderOperatorAuthenticator.RolesHeader, CatalogContractFixture.EditorRole);
        request.Content = new StringContent(body, Encoding.UTF8);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        return await fixture.Client.SendAsync(request);
    }
}
