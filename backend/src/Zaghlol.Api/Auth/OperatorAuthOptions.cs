namespace Zaghlol.Api.Auth;

/// <summary>Which IdP family issues operator tokens (T-136 design note §1). Only the proving-claim rule differs.</summary>
internal enum OperatorAuthProfile
{
    /// <summary>Any OIDC provider; no known phishing-resistant-MFA claim.</summary>
    Generic,

    /// <summary>Microsoft Entra ID: an authentication context in <c>acrs</c> can prove phishing-resistant MFA.</summary>
    Entra,

    /// <summary>Google Workspace: tokens carry no proving claim, so the check is always advisory.</summary>
    Google,
}

/// <summary>How the API treats the phishing-resistant-MFA claim for <c>support_agent</c> and <c>support_lead</c> (R4-6).</summary>
internal enum PhishingResistantMode
{
    /// <summary>The IdP policy is the control; the API keeps the role and counts an unproven request.</summary>
    Advisory,

    /// <summary>The token must carry <c>acrs</c> containing <see cref="OperatorAuthOptions.RequiredAcrs"/>, else the role is dropped (403).</summary>
    Enforced,
}

/// <summary>
/// <c>OperatorAuth:*</c> (T-136 design note §8). Public values only: issuer, audiences and algorithm names; the IdP's
/// signing keys come from its JWKS. List members bind by index (<c>OperatorAuth:Audiences:0</c>).
/// </summary>
internal sealed class OperatorAuthOptions
{
    public const string Section = "OperatorAuth";

    public static readonly IReadOnlyList<string> AllowedAlgorithms = ["RS256", "ES256"];

    public static readonly IReadOnlyList<string> DefaultAcceptedAmr = ["mfa"];

    public bool Enabled { get; set; }

    public OperatorAuthProfile Profile { get; set; } = OperatorAuthProfile.Generic;

    /// <summary>Exact <c>iss</c>; discovery is <c>{Issuer}/.well-known/openid-configuration</c> over HTTPS.</summary>
    public string? Issuer { get; set; }

    /// <summary>Accepted <c>aud</c> values: the <c>zaghlol-ops</c> CLI client and the admin app.</summary>
    public IList<string> Audiences { get; } = [];

    /// <summary>A subset of <see cref="AllowedAlgorithms"/>; empty means both.</summary>
    public IList<string> Algorithms { get; } = [];

    /// <summary><c>amr</c> values that count as the MFA signal; empty means <c>["mfa"]</c>.</summary>
    public IList<string> AcceptedAmr { get; } = [];

    public PhishingResistantMode PhishingResistantMode { get; set; } = PhishingResistantMode.Advisory;

    /// <summary>The Entra authentication-context ID that the conditional-access policy puts in <c>acrs</c>.</summary>
    public string? RequiredAcrs { get; set; }

    public int ClockSkewSeconds { get; set; } = 60;

    public int MaxLifetimeSeconds { get; set; } = 3600;

    public int JwksRefreshHours { get; set; } = 24;

    public int OperatorCacheSeconds { get; set; } = 30;

    public TestIssuerOptions TestIssuer { get; } = new();

    // Methods, not properties: the configuration binder reads every public property while binding.
    public IReadOnlyList<string> EffectiveAlgorithms() =>
        Algorithms.Count == 0 ? AllowedAlgorithms : [.. Algorithms.Distinct(StringComparer.Ordinal)];

    public IReadOnlyList<string> EffectiveAcceptedAmr() =>
        AcceptedAmr.Count == 0 ? DefaultAcceptedAmr : [.. AcceptedAmr.Where(a => !string.IsNullOrWhiteSpace(a))];

    /// <summary>The issuer without a trailing slash, for the discovery URL.</summary>
    public Uri DiscoveryUri() => new(Issuer!.TrimEnd('/') + "/.well-known/openid-configuration");

    /// <summary>
    /// Why these settings can't run the validator, or <c>null</c> when they can. Messages name settings only, never values.
    /// </summary>
    public string? Problem()
    {
        if (!Uri.TryCreate(Issuer, UriKind.Absolute, out var issuer) || issuer.Scheme != Uri.UriSchemeHttps
            || !string.IsNullOrEmpty(issuer.Query) || !string.IsNullOrEmpty(issuer.Fragment))
        {
            return "OperatorAuth:Issuer must be an absolute https URL without a query or fragment.";
        }

        if (Audiences.Count == 0 || Audiences.Any(string.IsNullOrWhiteSpace))
        {
            return "OperatorAuth:Audiences must list at least one audience.";
        }

        if (Algorithms.Any(a => !AllowedAlgorithms.Contains(a, StringComparer.Ordinal)))
        {
            return "OperatorAuth:Algorithms may only contain RS256 and ES256.";
        }

        if (EffectiveAcceptedAmr().Count == 0)
        {
            return "OperatorAuth:AcceptedAmr must list at least one value.";
        }

        if (PhishingResistantMode == PhishingResistantMode.Enforced
            && (Profile == OperatorAuthProfile.Google || string.IsNullOrWhiteSpace(RequiredAcrs)))
        {
            return "OperatorAuth:PhishingResistantMode=Enforced needs OperatorAuth:RequiredAcrs and a profile with a proving claim (Entra or Generic).";
        }

        if (ClockSkewSeconds is < 0 or > 300 || MaxLifetimeSeconds is < 60 or > 3600 || JwksRefreshHours is < 1 or > 24
            || OperatorCacheSeconds is < 0 or > 30)
        {
            return "OperatorAuth: ClockSkewSeconds (0-300), MaxLifetimeSeconds (60-3600), JwksRefreshHours (1-24) or OperatorCacheSeconds (0-30) is out of range.";
        }

        return null;
    }
}

/// <summary><c>OperatorAuth:TestIssuer</c>: a local fake issuer, honoured only in Development and Testing.</summary>
internal sealed class TestIssuerOptions
{
    public bool Enabled { get; set; }
}
