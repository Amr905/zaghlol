namespace Zaghlol.Application.Llm.Plans;

/// <summary>
/// Lists the validator needs besides the schema: bundled number words (step 4), institution registry aliases (step 2) and the
/// currencies whose exponent is not 2. The defaults are the minimum lists of the shared vectors; the bundled registry is injected
/// by the endpoint task (T-349).
/// </summary>
public sealed record PlanValidatorData(
    IReadOnlyDictionary<string, decimal> NumberWords,
    IReadOnlyCollection<string> RegistryAliases,
    IReadOnlyCollection<string> ThreeDecimalCurrencies,
    IReadOnlyCollection<string> ZeroDecimalCurrencies)
{
    public static PlanValidatorData Default { get; } = new(
        new Dictionary<string, decimal>(StringComparer.Ordinal)
        {
            ["ألف"] = 1000m,
            ["الف"] = 1000m,
            ["ميت"] = 100m,
            ["مية"] = 100m,
            ["مئة"] = 100m,
            ["مليون"] = 1_000_000m,
            ["thousand"] = 1000m,
            ["hundred"] = 100m,
            ["million"] = 1_000_000m,
        },
        ["cib", "nbe", "banque misr", "بنك مصر", "سي آي بي", "الأهلي", "فودافون كاش", "wise"],
        ["KWD", "BHD", "OMR", "JOD", "TND", "LYD", "IQD"],
        ["JPY", "KRW"]);
}
