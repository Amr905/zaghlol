using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using Zaghlol.Application.Llm;
using Zaghlol.Application.Llm.Ask;
using Zaghlol.Application.Llm.Plans;

namespace Zaghlol.Infrastructure.Llm;

public static class AskPlanServiceCollectionExtensions
{
    /// <summary>
    /// The <c>POST /v1/ask/plan</c> pipeline (T-349): the shared gate chain (T-352 reuses it), the service and the plan validator with the
    /// bundled institution names. Call after <c>AddZaghlolLlm</c>, <c>AddZaghlolLlmQuota</c>, <c>AddZaghlolLlmSpend</c>,
    /// <c>AddZaghlolLlmAttestation</c>, <c>AddZaghlolRemoteConfig</c> and <c>AddZaghlolEntitlements</c>; the host registers <see cref="ILlmRateLimiter"/>.
    /// </summary>
    public static IServiceCollection AddZaghlolAskPlan(this IServiceCollection services)
    {
        ArgumentNullException.ThrowIfNull(services);
        services.TryAddSingleton(TimeProvider.System);
        services.TryAddSingleton(provider => new PlanValidator(InstitutionAliases.Data(), provider.GetRequiredService<ILogger<PlanValidator>>()));

        // The attestation verifier is transient (it opens its own transaction), so the chain and the service are too.
        services.TryAddTransient<LlmGateChain>();
        services.TryAddTransient<AskPlanService>();
        return services;
    }
}
