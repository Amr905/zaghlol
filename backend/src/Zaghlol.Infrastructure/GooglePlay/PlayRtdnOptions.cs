using System.Text.RegularExpressions;
using Microsoft.Extensions.Configuration;
using Zaghlol.Application.Purchases;

namespace Zaghlol.Infrastructure.GooglePlay;

/// <summary>
/// <c>Purchases:Google:Rtdn:*</c> (T-133 design note §1 step 2, deployment.md "RTDN push"), read and checked once. A value that is set
/// but malformed stops the host in every environment; a missing <c>Audience</c> or <c>PushServiceAccount</c> stops it in Production
/// (<c>GoogleRtdnStartupCheck</c>) and makes every push 401 elsewhere. Errors name the key, never the value.
/// </summary>
public static partial class PlayRtdnOptions
{
    public const string Section = "Purchases:Google:Rtdn";

    public static PlayRtdnSettings Read(IConfiguration configuration)
    {
        ArgumentNullException.ThrowIfNull(configuration);

        var section = configuration.GetSection(Section);
        var audience = Blank(section["Audience"]);
        var account = Blank(section["PushServiceAccount"]);
        var subscription = Blank(section["Subscription"]);

        if (audience is not null
            && (audience.Length > 2048 || !Uri.TryCreate(audience, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps
                || uri.UserInfo.Length > 0 || uri.Query.Length > 0 || uri.Fragment.Length > 0))
        {
            throw new PlayConfigurationException("Purchases:Google:Rtdn:Audience must be the push endpoint's absolute https URL.");
        }

        if (account is not null && !ServiceAccountRegex().IsMatch(account))
        {
            throw new PlayConfigurationException("Purchases:Google:Rtdn:PushServiceAccount must be a service-account e-mail address.");
        }

        if (subscription is not null && !SubscriptionRegex().IsMatch(subscription))
        {
            throw new PlayConfigurationException("Purchases:Google:Rtdn:Subscription must be projects/<project>/subscriptions/<name>.");
        }

        return new PlayRtdnSettings(audience, account, subscription);
    }

    private static string? Blank(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    // A lower-case service-account address (…@<project>.iam.gserviceaccount.com and similar); compared case-sensitively later.
    [GeneratedRegex(@"^[a-z0-9][a-z0-9._-]{0,99}@[a-z0-9][a-z0-9.-]{0,199}\.[a-z]{2,63}\z", RegexOptions.CultureInvariant)]
    private static partial Regex ServiceAccountRegex();

    [GeneratedRegex(@"^projects/[a-z][a-z0-9-]{4,28}[a-z0-9]/subscriptions/[A-Za-z][A-Za-z0-9._~%+-]{2,254}\z", RegexOptions.CultureInvariant)]
    private static partial Regex SubscriptionRegex();
}
