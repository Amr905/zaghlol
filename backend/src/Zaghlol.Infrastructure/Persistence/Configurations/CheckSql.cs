namespace Zaghlol.Infrastructure.Persistence.Configurations;

/// <summary>
/// CHECK predicates shared by several tables (backend-schema.md section 2 conventions and section 3). They are
/// backstops: the API validates and normalizes first (BR-SYNC-04, CLAUDE.md section 2.5).
/// </summary>
internal static class CheckSql
{
    /// <summary>
    /// Digits of every script a phone, card or account number may arrive in: ASCII, Arabic-Indic (U+0660-0669),
    /// Extended Arabic-Indic (U+06F0-06F9) and fullwidth (U+FF10-FF19).
    /// </summary>
    public const string AnyDigit = "0-9٠-٩۰-۹０-９";

    /// <summary>The characters allowed between the digits of one run, inside a bracket expression.</summary>
    public const string DigitSeparators = "[:space:].,/_،-";

    /// <summary>
    /// A free-text norm of at most 64 characters with no run of 6 digits (any script, separated by up to three whitespace, dot,
    /// comma, slash, underscore, Arabic comma or dash characters: "010 1234 5678" and "01 / 23 / 45" are runs; FU-018) and no "@"
    /// (no e-mail or InstaPay address). The API filter (<c>ContributionPrivacy</c>) is stricter and runs first.
    /// </summary>
    public static string PrivacySafeNorm(string column) =>
        $"char_length({column}) <= 64 AND {column} !~ '([{AnyDigit}][{DigitSeparators}]{{0,3}}){{6,}}' AND position('@' in {column}) = 0";

    /// <summary>Same as <c>appVersion</c> in the OpenAPI file, loosened to 2-4 numeric parts.</summary>
    public static string AppVersion(string column) =>
        $"{column} ~ '^[0-9]{{1,4}}(\\.[0-9]{{1,4}}){{1,3}}([+-][0-9A-Za-z.-]{{1,32}})?$'";

    /// <summary>Institution codes are lowercase ASCII slugs (OpenAPI <c>InstitutionCode</c>, project-structure.md).</summary>
    public const string InstitutionCodeAlphabet = "^[a-z0-9_]{1,64}$";

    /// <summary>System category codes (OpenAPI <c>CategoryCode</c> uses the same alphabet).</summary>
    public const string CategoryCodeAlphabet = "^[a-z0-9_]{1,64}$";

    /// <summary>Purchase tokens and originalTransactionIds are far shorter; this caps abuse of the column.</summary>
    public const int StoreKeyMaxLength = 512;
}
