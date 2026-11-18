namespace Zaghlol.Api.Auth;

/// <summary>Which IdP family issues operator tokens (T-136 design note §1). Only the proving-claim rule differs.</summary>
internal enum OperatorAuthProfile
{
    /// <summary>Any OIDC provider; no known phishing-resistant-MFA claim.</summary>
    Generic,

    /// <summary>Microsoft Entra ID: an authentication context in <c>acrs</c> can prove phishing-resistant MFA.</summary>
    Entra,

    /// <summary>
    /// Google Workspace: ID tokens carry no <c>amr</c>, <c>nbf</c>, group or role claim. Tenant control is the <c>hd</c>
    /// hosted-domain claim (<see cref="OperatorAuthOptions.AllowedDomains"/>); MFA is a Workspace 2-Step Verification
    /// enforcement (the IdP is the control, the API can't see it), so the MFA-claim rule is off and the mode is Advisory.
    /// </summary>
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

    /// <summary>Entra: the <c>tid</c> values (tenant GUIDs) accepted. Required for the Entra profile; deny by default.</summary>
    public IList<string> AllowedTenants { get; } = [];

    /// <summary>Google: the Workspace domains accepted in the <c>hd</c> claim. Required for the Google profile; deny by default.</summary>
    public IList<string> AllowedDomains { get; } = [];

    /// <summary>The claim that carries role or group values: <c>roles</c> (Entra app roles, preferred) or <c>groups</c> (group object IDs).</summary>
    public string RoleClaim { get; set; } = "roles";

    /// <summary>
    /// Optional map from a claim value (app-role name or group ID) to a Zaghlol operator role. When present, the operator's
    /// effective roles are the <c>operators</c> row's roles <b>intersected</b> with the mapped token roles: the token can only
    /// narrow, never grant. When empty, the row's roles apply alone.
    /// </summary>
    public IDictionary<string, string> RoleMap { get; } = new Dictionary<string, string>(StringComparer.Ordinal);

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

    /// <summary>Entra and Generic tokens must prove MFA by <c>amr</c>; Google ID tokens have none (Workspace policy is the control).</summary>
    public bool RequiresMfaClaim() => Profile != OperatorAuthProfile.Google;

    /// <summary><c>nbf</c> is required except for Google, whose ID tokens omit it.</summary>
    public bool RequiresNotBefore() => Profile != OperatorAuthProfile.Google;

    /// <summary>The <c>iss</c> values accepted: the configured one, plus Google's scheme-less alias.</summary>
    public IReadOnlyList<string> ValidIssuers() =>
        Profile == OperatorAuthProfile.Google ? [Issuer!, "accounts.google.com"] : [Issuer!];

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

        if (Profile == OperatorAuthProfile.Entra && (AllowedTenants.Count == 0 || AllowedTenants.Any(t => !Guid.TryParse(t, out _))
            || !AllowedTenants.Any(t => issuer.AbsolutePath.Trim('/').StartsWith(t, StringComparison.OrdinalIgnoreCase))))
        {
            return "OperatorAuth:AllowedTenants must list tenant GUIDs (at least one, matching the issuer path) for the Entra profile.";
        }

        if (Profile == OperatorAuthProfile.Google && (AllowedDomains.Count == 0 || AllowedDomains.Any(string.IsNullOrWhiteSpace)))
        {
            return "OperatorAuth:AllowedDomains must list at least one Workspace domain for the Google profile.";
        }

        if (Profile == OperatorAuthProfile.Google && (!string.Equals(Issuer, "https://accounts.google.com", StringComparison.Ordinal) || RoleMap.Count > 0))
        {
            return "OperatorAuth:Profile=Google needs Issuer=https://accounts.google.com and no RoleMap (Google ID tokens carry no role or group claim).";
        }

        if (RoleMap.Count > 0 && (RoleClaim is not ("roles" or "groups")
            || RoleMap.Values.Any(r => !Application.Operators.OperatorRoles.IsKnown(r))))
        {
            return "OperatorAuth:RoleMap values must be known operator roles and OperatorAuth:RoleClaim must be roles or groups.";
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
