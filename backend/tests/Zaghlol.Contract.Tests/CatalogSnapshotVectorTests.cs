using System.Buffers.Text;
using System.Text.Json.Nodes;
using Zaghlol.Application.Catalog;
using Zaghlol.Contract.Tests.Signing;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// T-125 app-side vector: <c>vectors/catalog-snapshot-v1.json</c> holds the exact snapshot bytes, a public JWKS and the
/// <c>Zaghlol-Signature</c> over them. The app (T-141, T-030) verifies the same file with its own code; here the reference
/// verifier applies the app's rules, and the backend serializer must reproduce the committed bytes.
/// </summary>
public class CatalogSnapshotVectorTests
{
    private static JsonObject Vectors =>
        JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "vectors", "catalog-snapshot-v1.json")))!.AsObject();

    [Fact]
    public void TheSnapshotSignatureVerifiesWithTheAppSideRules()
    {
        var vectors = Vectors;
        var snapshot = vectors["snapshot"]!;

        Assert.True(ReferenceVerifiers.VerifyResponse(
            vectors["jwks"]!,
            Base64Url.DecodeFromChars(snapshot["bodyB64u"]!.GetValue<string>()),
            snapshot["header"]!.GetValue<string>()));
    }

    [Fact]
    public void ATamperedSnapshotDoesNotVerify()
    {
        var vectors = Vectors;
        var tampered = vectors["tampered"]!;

        Assert.False(ReferenceVerifiers.VerifyResponse(
            vectors["jwks"]!,
            Base64Url.DecodeFromChars(tampered["bodyB64u"]!.GetValue<string>()),
            tampered["header"]!.GetValue<string>()));
    }

    [Fact]
    public void TheBackendSerializerReproducesTheCommittedBytes()
    {
        var ops = new[]
        {
            Upsert(CatalogEntity.Categories, "dining", new CatalogFields { NameAr = "أكل", NameEn = "Dining", Icon = "restaurant", Color = "#FFB86B", Bucket = "wants", Sort = 3 }),
            Upsert(
                CatalogEntity.Merchants,
                "812",
                new CatalogFields { Canonical = "Koshary El Tahrir", NameAr = "كشري التحرير", Category = "dining" }),
            Upsert(CatalogEntity.Aliases, "812:koshary el tahrir", new CatalogFields { Match = "exact" }),
            Upsert(CatalogEntity.Keywords, "ar:صيدلية", new CatalogFields { Category = "dining", Weight = 80 }),
        };

        var committed = Base64Url.DecodeFromChars(Vectors["snapshot"]!["bodyB64u"]!.GetValue<string>());

        Assert.Equal(committed, CatalogJson.Snapshot(7, ops));
    }

    private static CatalogOp Upsert(CatalogEntity entity, string storageKey, CatalogFields fields) =>
        new(CatalogKeys.FromStorage(entity, storageKey), false, fields);
}
