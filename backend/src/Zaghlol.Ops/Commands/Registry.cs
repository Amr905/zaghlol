using Zaghlol.Ops.Cli;

namespace Zaghlol.Ops.Commands;

/// <summary>Every command. The OpenAPI file's Admin operations are each covered by one (a test checks it).</summary>
internal static class Registry
{
    public static IReadOnlyList<CommandSpec> All { get; } =
    [
        .. SessionCommands.Specs,
        .. CatalogCommands.Specs,
        .. FlagCommands.Specs,
        .. ConfigCommands.Specs,
        .. PriceCommands.Specs,
        .. ContributionCommands.Specs,
        .. LlmCatCommands.Specs,
        .. SupportCommands.Specs,
        .. ReportCommands.Specs,
    ];
}
