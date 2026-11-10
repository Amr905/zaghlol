namespace Zaghlol.Application.Catalog;

/// <summary>
/// Field rules of the draft bodies (OpenAPI <c>CategoryDraftRequest</c>, <c>MerchantDraftRequest</c>,
/// <c>AliasDraftRequest</c>, <c>KeywordDraftRequest</c>) that the JSON shape can't express. Used by the admin endpoints and the
/// seed import, so both refuse the same input.
/// </summary>
public static class CatalogValidation
{
    public const int MaxNoteLength = 200;

    public static IReadOnlyList<string> MatchModes { get; } = ["exact", "prefix", "token"];

    /// <summary>True when <paramref name="fields"/> are complete and in range for <paramref name="entity"/>.</summary>
    public static bool IsValid(CatalogEntity entity, CatalogFields fields)
    {
        ArgumentNullException.ThrowIfNull(fields);

        return entity switch
        {
            CatalogEntity.Categories => IsText(fields.NameAr, 1, 80)
                && IsText(fields.NameEn, 1, 80)
                && IsText(fields.Icon, 0, 64)
                && IsColor(fields.Color)
                && IsText(fields.Bucket, 0, 32)
                && fields.Sort is not null,
            CatalogEntity.Merchants => IsText(fields.Canonical, 1, 120)
                && IsText(fields.NameAr, 1, 120)
                && fields.Category is not null
                && CatalogKeys.IsCategoryCode(fields.Category),
            CatalogEntity.Aliases => fields.Match is not null && MatchModes.Contains(fields.Match),
            CatalogEntity.Keywords => fields.Category is not null
                && CatalogKeys.IsCategoryCode(fields.Category)
                && fields.Weight is >= 0 and <= 100,
            _ => false,
        };
    }

    /// <summary>True when the publish note is absent or at most 200 characters without control characters.</summary>
    public static bool IsValidNote(string? note) =>
        note is null || (note.Length <= MaxNoteLength && CatalogText.HasNoControlCharacters(note));

    private static bool IsText(string? text, int min, int max) =>
        text is not null && text.Length >= min && text.Length <= max && CatalogText.HasNoControlCharacters(text);

    private static bool IsColor(string? text) =>
        text is { Length: 7 } && text[0] == '#' && text.Skip(1).All(Uri.IsHexDigit);
}
