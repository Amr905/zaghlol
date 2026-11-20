using System.Text.Json;
using System.Text.Json.Nodes;
using Zaghlol.Ops.Cli;

namespace Zaghlol.Ops.Commands;

/// <summary>Draft catalog: list, create merchant, put, delete, import, publish (role <c>catalog_editor</c>).</summary>
internal static class CatalogCommands
{
    private static readonly string[] Entities = ["categories", "merchants", "aliases", "keywords"];

    private static readonly Opt[] KeyOptions = [new("merchant"), new("alias"), new("lang"), new("keyword")];

    public static IReadOnlyList<CommandSpec> Specs { get; } =
    [
        new("catalog draft list", "List draft entries of one kind (adminListCatalogDraft).",
            "catalog draft list <categories|merchants|aliases|keywords> [--limit 1-500] [--cursor C] [--all]",
            [new("limit"), new("cursor"), new("all", IsFlag: true)], 1, 1, ListAsync, "adminListCatalogDraft"),
        new("catalog draft create-merchant", "Create a draft merchant; the server allocates its id (adminCreateDraftMerchant).",
            "catalog draft create-merchant --canonical NAME --name-ar NAME --category CODE",
            [new("canonical"), new("name-ar"), new("category")], 0, 0, CreateMerchantAsync, "adminCreateDraftMerchant"),
        new("catalog draft put", "Create or replace one draft entry from a JSON file of its non-key fields (adminPutCatalogDraftEntry).",
            "catalog draft put <entity> [<key> | --merchant N --alias TEXT | --lang xx --keyword TEXT] --file FILE|-",
            [.. KeyOptions, new("file")], 1, 2, PutAsync, "adminPutCatalogDraftEntry"),
        new("catalog draft delete", "Tombstone one draft entry (adminDeleteCatalogDraftEntry).",
            "catalog draft delete <entity> [<key> | --merchant N --alias TEXT | --lang xx --keyword TEXT]",
            KeyOptions, 1, 2, DeleteAsync, "adminDeleteCatalogDraftEntry"),
        new("catalog import", "Apply a JSON file of draft changes in order (the put, create and delete calls above). Nothing is published.",
            "catalog import FILE [--dry-run]", [new("dry-run", IsFlag: true)], 1, 1, ImportAsync),
        new("catalog publish", "Publish the draft as a new signed catalog version (adminPublishCatalog).",
            "catalog publish [--note TEXT]", [new("note")], 0, 0, PublishAsync, "adminPublishCatalog"),
    ];

    private static async Task<int> ListAsync(CommandContext ctx)
    {
        var entity = ctx.Args.Positionals[0];
        if (!Entities.Contains(entity, StringComparer.Ordinal))
        {
            return ctx.Usage("The entity must be categories, merchants, aliases or keywords.");
        }

        var limit = 100;
        if (ctx.Args.Get("limit") is { } rawLimit && !Validate.PositiveInt(rawLimit, 500, out limit))
        {
            return ctx.Usage("--limit must be a whole number from 1 to 500.");
        }

        var cursor = ctx.Args.Get("cursor");
        if (cursor is not null && (cursor.Length > 256 || cursor.Any(char.IsControl)))
        {
            return ctx.Usage("--cursor is not a valid cursor.");
        }

        if (!ctx.Args.Has("all"))
        {
            return await ctx.CallAsync(HttpMethod.Get, ListPath(entity, limit, cursor)).ConfigureAwait(false);
        }

        // --all follows nextCursor (at most 200 pages) and prints one {"items": [...]} array.
        var items = new JsonArray();
        for (var page = 0; page < 200; page++)
        {
            Api.ApiResponse response;
            try
            {
                if (await ctx.SignInAsync().ConfigureAwait(false) is { } failed)
                {
                    return failed;
                }

                response = await ctx.Api.SendAsync(HttpMethod.Get, ListPath(entity, limit, cursor), null, ctx.CancellationToken).ConfigureAwait(false);
            }
            catch (Auth.LoginException e)
            {
                ctx.Printer.Err("error: sign-in failed: " + e.Message);
                return ExitCode.Auth;
            }
            catch (Api.ApiUnreachableException e)
            {
                ctx.Printer.Err("error: " + e.Message);
                return ExitCode.Unreachable;
            }

            if (!response.IsSuccess)
            {
                return ctx.Report(response);
            }

            foreach (var item in (response.Body?["items"] as JsonArray) ?? [])
            {
                items.Add(item?.DeepClone());
            }

            cursor = response.Body?["nextCursor"] is JsonValue next && next.TryGetValue<string>(out var value) ? value : null;
            if (cursor is null)
            {
                ctx.Printer.Json(new JsonObject { ["items"] = items });
                return ExitCode.Success;
            }
        }

        ctx.Printer.Err("error: more than 200 pages; use --cursor to continue.");
        return ExitCode.ApiRefused;
    }

    private static string ListPath(string entity, int limit, string? cursor) =>
        "/admin/v1/catalog/draft/" + entity + "?limit=" + limit.ToString(System.Globalization.CultureInfo.InvariantCulture)
        + (cursor is null ? string.Empty : "&cursor=" + Uri.EscapeDataString(cursor));

    private static async Task<int> CreateMerchantAsync(CommandContext ctx)
    {
        var canonical = ctx.Args.Get("canonical");
        var nameAr = ctx.Args.Get("name-ar");
        var category = ctx.Args.Get("category");
        if (!Validate.Text(canonical, 120) || !Validate.Text(nameAr, 120) || !Validate.Match(Validate.CategoryCode(), category))
        {
            return ctx.Usage("--canonical and --name-ar (1-120 characters) and --category (a category code) are required.");
        }

        return await ctx.CallAsync(HttpMethod.Post, "/admin/v1/catalog/draft/merchants", (w, _) => WriteMerchant(w, canonical!, nameAr!, category!)).ConfigureAwait(false);
    }

    private static void WriteMerchant(Utf8JsonWriter w, string canonical, string nameAr, string category)
    {
        w.WriteStartObject();
        w.WriteString("canonical", canonical);
        w.WriteString("nameAr", nameAr);
        w.WriteString("category", category);
        w.WriteEndObject();
    }

    private static async Task<int> PutAsync(CommandContext ctx)
    {
        var entity = ctx.Args.Positionals[0];
        var key = EntryKey(ctx, entity, out var error);
        if (key is null)
        {
            return ctx.Usage(error!);
        }

        if (ctx.Args.Get("file") is not { } file)
        {
            return ctx.Usage("--file FILE (or -) with the entry's non-key fields is required.");
        }

        using var body = Inputs.ReadObject(ctx, file, Inputs.MaxBodyBytes, out var fileError);
        if (body is null)
        {
            return ctx.Usage(fileError!);
        }

        return await ctx.CallAsync(HttpMethod.Put, "/admin/v1/catalog/draft/" + entity + "/" + Uri.EscapeDataString(key), (w, _) => body.RootElement.WriteTo(w)).ConfigureAwait(false);
    }

    private static async Task<int> DeleteAsync(CommandContext ctx)
    {
        var entity = ctx.Args.Positionals[0];
        var key = EntryKey(ctx, entity, out var error);
        return key is null
            ? ctx.Usage(error!)
            : await ctx.CallAsync(HttpMethod.Delete, "/admin/v1/catalog/draft/" + entity + "/" + Uri.EscapeDataString(key)).ConfigureAwait(false);
    }

    private static async Task<int> PublishAsync(CommandContext ctx)
    {
        var note = ctx.Args.Get("note");
        if (note is not null && !Validate.Text(note, 200))
        {
            return ctx.Usage("--note must be 1-200 characters.");
        }

        return await ctx.CallAsync(HttpMethod.Post, "/admin/v1/catalog/publish", (w, _) =>
        {
            w.WriteStartObject();
            if (note is not null)
            {
                w.WriteString("note", note);
            }

            w.WriteEndObject();
        }).ConfigureAwait(false);
    }

    /// <summary>The path key for an entity: given as the second positional, or built from --merchant/--alias or --lang/--keyword.</summary>
    internal static string? EntryKey(CommandContext ctx, string entity, out string? error)
    {
        return KeyFrom(entity, ctx.Args.Positionals.Count > 1 ? ctx.Args.Positionals[1] : null, ctx.Args.Get("merchant"), ctx.Args.Get("alias"), ctx.Args.Get("lang"), ctx.Args.Get("keyword"), out error);
    }

    internal static string? KeyFrom(string entity, string? raw, string? merchant, string? alias, string? lang, string? keyword, out string? error)
    {
        error = null;
        var built = entity switch
        {
            "aliases" when merchant is not null && alias is not null && raw is null =>
                Validate.PositiveInt(merchant, 999_999_999, out _) && Validate.Text(alias, 64) ? merchant + ":" + Validate.B64u(alias) : null,
            "keywords" when lang is not null && keyword is not null && raw is null =>
                lang.Length == 2 && lang.All(char.IsAsciiLetterLower) && Validate.Text(keyword, 64) ? lang + ":" + Validate.B64u(keyword) : null,
            _ => raw,
        };
        var shapeOk = entity switch
        {
            "categories" => built is not null && Validate.Match(Validate.CategoryCode(), built),
            "merchants" => built is not null && Validate.PositiveInt(built, 999_999_999, out _),
            "aliases" => built is not null && System.Text.RegularExpressions.Regex.IsMatch(built, "^[0-9]{1,9}:[A-Za-z0-9_-]{2,342}$", System.Text.RegularExpressions.RegexOptions.CultureInvariant, TimeSpan.FromSeconds(1)),
            "keywords" => built is not null && System.Text.RegularExpressions.Regex.IsMatch(built, "^[a-z]{2}:[A-Za-z0-9_-]{2,342}$", System.Text.RegularExpressions.RegexOptions.CultureInvariant, TimeSpan.FromSeconds(1)),
            _ => false,
        };
        if (!Entities.Contains(entity, StringComparer.Ordinal))
        {
            error = "The entity must be categories, merchants, aliases or keywords.";
            return null;
        }

        if (!shapeOk || built is null)
        {
            error = entity switch
            {
                "categories" => "Give the category code (for example dining).",
                "merchants" => "Give the merchant id (a whole number).",
                "aliases" => "Give <merchantId>:<base64url alias>, or --merchant N --alias TEXT (TEXT at most 64 characters).",
                _ => "Give <lang>:<base64url keyword>, or --lang xx --keyword TEXT (TEXT at most 64 characters).",
            };
            return null;
        }

        return built;
    }

    private static async Task<int> ImportAsync(CommandContext ctx)
    {
        using var document = Inputs.ReadObject(ctx, ctx.Args.Positionals[0], OpsEnvironment.MaxFileBytes, out var fileError);
        if (document is null)
        {
            return ctx.Usage(fileError!);
        }

        var plan = CatalogImport.Plan(document.RootElement, out var planError);
        if (plan is null)
        {
            return ctx.Usage(planError!);
        }

        if (ctx.Args.Has("dry-run"))
        {
            ctx.Printer.Json(new JsonObject { ["valid"] = true, ["entries"] = plan.Count });
            return ExitCode.Success;
        }

        if (await ctx.SignInAsync().ConfigureAwait(false) is { } failed)
        {
            return failed;
        }

        for (var i = 0; i < plan.Count; i++)
        {
            ctx.Printer.Err($"[{(i + 1).ToString(System.Globalization.CultureInfo.InvariantCulture)}/{plan.Count.ToString(System.Globalization.CultureInfo.InvariantCulture)}] {plan[i].Method.Method} {plan[i].Label}");
            var item = plan[i];
            var code = await ctx.CallAsync(item.Method, item.Path, item.Body is null ? null : (w, _) => item.Body.WriteTo(w), quiet: true).ConfigureAwait(false);
            if (code != ExitCode.Success)
            {
                ctx.Printer.Err($"error: stopped at entry {(i + 1).ToString(System.Globalization.CultureInfo.InvariantCulture)}; {i.ToString(System.Globalization.CultureInfo.InvariantCulture)} applied before it.");
                return code;
            }
        }

        ctx.Printer.Json(new JsonObject { ["applied"] = plan.Count, ["total"] = plan.Count });
        return ExitCode.Success;
    }
}
