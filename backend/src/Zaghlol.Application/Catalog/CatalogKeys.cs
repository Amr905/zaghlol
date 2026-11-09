using System.Buffers.Text;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.Text;

namespace Zaghlol.Application.Catalog;

/// <summary>The four kinds of catalog entry (the <c>{entity}</c> path segment).</summary>
public enum CatalogEntity
{
    Categories,
    Merchants,
    Aliases,
    Keywords,
}

public static class CatalogEntities
{
    public static string Name(CatalogEntity entity) => entity switch
    {
        CatalogEntity.Categories => "categories",
        CatalogEntity.Merchants => "merchants",
        CatalogEntity.Aliases => "aliases",
        CatalogEntity.Keywords => "keywords",
        _ => throw new ArgumentOutOfRangeException(nameof(entity)),
    };

    public static bool TryParse(string? text, out CatalogEntity entity)
    {
        foreach (var candidate in Enum.GetValues<CatalogEntity>())
        {
            if (string.Equals(text, Name(candidate), StringComparison.Ordinal))
            {
                entity = candidate;
                return true;
            }
        }

        entity = default;
        return false;
    }
}

/// <summary>
/// One draft entry's identity (backend-api §5.2). <see cref="PathId"/> is the URL form; <see cref="StorageKey"/> is the same key
/// decoded (<c>812:koshary el tahrir</c>, <c>ar:text</c>) as the draft table keeps it. Which of the other members are set depends
/// on <see cref="Entity"/>: <see cref="Code"/> for categories, <see cref="MerchantId"/> for merchants and aliases,
/// <see cref="Text"/> for aliases and keywords, <see cref="Lang"/> for keywords.
/// </summary>
public sealed record CatalogEntryKey
{
    public required CatalogEntity Entity { get; init; }

    public required string PathId { get; init; }

    public required string StorageKey { get; init; }

    public string? Code { get; init; }

    public int MerchantId { get; init; }

    public string? Text { get; init; }

    public string? Lang { get; init; }
}

/// <summary>
/// Parsing of the <c>{id}</c> path segment. A key is accepted only when it is canonical: no <c>=</c> padding, re-encoding the
/// decoded bytes reproduces the input (rejects non-zero trailing bits), the bytes are valid UTF-8, the decoded text equals its
/// own normalized form and is at most 64 characters (FU-009).
/// </summary>
public static class CatalogKeys
{
    public const int MaxPathLength = 360;

    private const int MaxEncodedLength = 342;

    private static readonly UTF8Encoding StrictUtf8 = new(false, true);

    public static bool TryParse(CatalogEntity entity, string? id, [NotNullWhen(true)] out CatalogEntryKey? key)
    {
        key = null;
        if (string.IsNullOrEmpty(id) || id.Length > MaxPathLength)
        {
            return false;
        }

        switch (entity)
        {
            case CatalogEntity.Categories:
                if (!IsCategoryCode(id))
                {
                    return false;
                }

                key = new CatalogEntryKey { Entity = entity, PathId = id, StorageKey = id, Code = id };
                return true;

            case CatalogEntity.Merchants:
                if (!TryParseId(id, out var merchantId))
                {
                    return false;
                }

                key = new CatalogEntryKey { Entity = entity, PathId = id, StorageKey = id, MerchantId = merchantId };
                return true;

            case CatalogEntity.Aliases:
                return TryParseAlias(id, out key);

            case CatalogEntity.Keywords:
                return TryParseKeyword(id, out key);

            default:
                return false;
        }
    }

    /// <summary>Rebuilds a key from the decoded form stored in the draft table or the live tables.</summary>
    public static CatalogEntryKey FromStorage(CatalogEntity entity, string storageKey)
    {
        ArgumentNullException.ThrowIfNull(storageKey);

        switch (entity)
        {
            case CatalogEntity.Categories:
                return new CatalogEntryKey { Entity = entity, PathId = storageKey, StorageKey = storageKey, Code = storageKey };
            case CatalogEntity.Merchants:
                return new CatalogEntryKey
                {
                    Entity = entity,
                    PathId = storageKey,
                    StorageKey = storageKey,
                    MerchantId = int.Parse(storageKey, CultureInfo.InvariantCulture),
                };
            case CatalogEntity.Aliases:
                return AliasFromStorage(storageKey);
            default:
                return KeywordFromStorage(storageKey);
        }
    }

    public static string StorageKeyOf(int merchantId, string alias) =>
        string.Create(CultureInfo.InvariantCulture, $"{merchantId}:{alias}");

    public static string StorageKeyOf(string lang, string keyword) => lang + ":" + keyword;

    public static string AliasPathId(int merchantId, string alias) =>
        string.Create(CultureInfo.InvariantCulture, $"{merchantId}:") + EncodeText(alias);

    public static string KeywordPathId(string lang, string keyword) => lang + ":" + EncodeText(keyword);

    /// <summary>Canonical base64url without padding of the UTF-8 bytes.</summary>
    public static string EncodeText(string text)
    {
        ArgumentNullException.ThrowIfNull(text);

        return Base64Url.EncodeToString(Encoding.UTF8.GetBytes(text));
    }

    public static bool IsCategoryCode(string text)
    {
        if (text.Length is < 2 or > 32 || text[0] is not (>= 'a' and <= 'z'))
        {
            return false;
        }

        return text.All(c => c is (>= 'a' and <= 'z') or (>= '0' and <= '9') or '_');
    }

    private static bool TryParseAlias(string id, [NotNullWhen(true)] out CatalogEntryKey? key)
    {
        key = null;
        var colon = id.IndexOf(':', StringComparison.Ordinal);
        if (colon <= 0
            || !TryParseId(id[..colon], out var owner)
            || !TryDecode(id[(colon + 1)..], out var alias)
            || !CatalogText.IsNormalized(alias)
            || !CatalogText.IsAsciiText(alias))
        {
            return false;
        }

        key = new CatalogEntryKey
        {
            Entity = CatalogEntity.Aliases,
            PathId = id,
            StorageKey = StorageKeyOf(owner, alias),
            MerchantId = owner,
            Text = alias,
        };
        return true;
    }

    private static bool TryParseKeyword(string id, [NotNullWhen(true)] out CatalogEntryKey? key)
    {
        key = null;
        if (id.Length < 4 || id[2] != ':' || !IsLang(id[..2]) || !TryDecode(id[3..], out var keyword) || !CatalogText.IsNormalized(keyword))
        {
            return false;
        }

        var lang = id[..2];
        key = new CatalogEntryKey
        {
            Entity = CatalogEntity.Keywords,
            PathId = id,
            StorageKey = StorageKeyOf(lang, keyword),
            Lang = lang,
            Text = keyword,
        };
        return true;
    }

    private static CatalogEntryKey AliasFromStorage(string storageKey)
    {
        var colon = storageKey.IndexOf(':', StringComparison.Ordinal);
        var owner = int.Parse(storageKey[..colon], CultureInfo.InvariantCulture);
        var alias = storageKey[(colon + 1)..];
        return new CatalogEntryKey
        {
            Entity = CatalogEntity.Aliases,
            PathId = AliasPathId(owner, alias),
            StorageKey = storageKey,
            MerchantId = owner,
            Text = alias,
        };
    }

    private static CatalogEntryKey KeywordFromStorage(string storageKey)
    {
        var colon = storageKey.IndexOf(':', StringComparison.Ordinal);
        var lang = storageKey[..colon];
        var keyword = storageKey[(colon + 1)..];
        return new CatalogEntryKey
        {
            Entity = CatalogEntity.Keywords,
            PathId = KeywordPathId(lang, keyword),
            StorageKey = storageKey,
            Lang = lang,
            Text = keyword,
        };
    }

    private static bool IsLang(string text) => text.Length == 2 && text.All(c => c is >= 'a' and <= 'z');

    /// <summary>A merchant id in path form: 1 to 9 ASCII digits, no leading zero.</summary>
    private static bool TryParseId(string text, out int id)
    {
        id = 0;
        if (text.Length is < 1 or > 9 || text[0] is not (>= '1' and <= '9') || !text.All(c => c is >= '0' and <= '9'))
        {
            return false;
        }

        id = int.Parse(text, CultureInfo.InvariantCulture);
        return true;
    }

    private static bool TryDecode(string encoded, out string text)
    {
        text = string.Empty;
        if (encoded.Length is < 2 or > MaxEncodedLength
            || !encoded.All(c => c is (>= 'A' and <= 'Z') or (>= 'a' and <= 'z') or (>= '0' and <= '9') or '-' or '_'))
        {
            return false;
        }

        var buffer = new byte[Base64Url.GetMaxDecodedLength(encoded.Length)];
        if (!Base64Url.TryDecodeFromChars(encoded, buffer, out var written))
        {
            return false;
        }

        var bytes = buffer.AsSpan(0, written);
        if (!string.Equals(Base64Url.EncodeToString(bytes), encoded, StringComparison.Ordinal))
        {
            return false;
        }

        try
        {
            text = StrictUtf8.GetString(bytes);
        }
        catch (DecoderFallbackException)
        {
            return false;
        }

        return true;
    }
}
