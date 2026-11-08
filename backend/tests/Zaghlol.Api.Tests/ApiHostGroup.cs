namespace Zaghlol.Api.Tests;

/// <summary>
/// Test classes that boot the API host run one after another. Serilog's request-logging middleware writes to the
/// process-wide <c>Log.Logger</c>, which each host replaces when it is built, so two hosts built in parallel would steal
/// each other's request logs (and <c>RequestBodiesAreNeverLogged</c> would see none).
/// </summary>
[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class ApiHostGroup
{
    public const string Name = "api-host";
}
