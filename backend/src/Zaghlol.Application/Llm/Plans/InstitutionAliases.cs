using System.Text.Json;

namespace Zaghlol.Application.Llm.Plans;

/// <summary>
/// The bundled institution names the validator refuses inside a plan (ask-llm §2.4 step 2): the names, wallet-card names and acronyms of
/// <c>app/assets/registry/institutions</c> in <c>backend/contracts/institution-aliases-v1.json</c> (a drift test checks the list against the app
/// assets), plus the Arabic aliases of the shared vectors.
/// </summary>
public static class InstitutionAliases
{
    private const string Resource = "Zaghlol.Llm.institution-aliases-v1.json";

    private static readonly Lazy<IReadOnlyList<string>> Loaded = new(Load);

    public static IReadOnlyList<string> All => Loaded.Value;

    /// <summary>The validator data with the bundled registry names added to the vectors' minimum lists.</summary>
    public static PlanValidatorData Data() =>
        PlanValidatorData.Default with
        {
            RegistryAliases = [.. PlanValidatorData.Default.RegistryAliases.Concat(All).Distinct(StringComparer.Ordinal)],
        };

    private static List<string> Load()
    {
        using var stream = typeof(InstitutionAliases).Assembly.GetManifestResourceStream(Resource)
            ?? throw new LlmConfigurationException("The institution aliases are not embedded.");
        using var document = JsonDocument.Parse(stream);
        return [.. document.RootElement.GetProperty("aliases").EnumerateArray().Select(a => a.GetString()!)];
    }
}
