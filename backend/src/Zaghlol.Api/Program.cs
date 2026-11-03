using Serilog;
using Serilog.Core;
using Zaghlol.Api;
using Zaghlol.Api.Endpoints;
using Zaghlol.Api.Problems;
using Zaghlol.Application;
using Zaghlol.Infrastructure;
using Zaghlol.Infrastructure.Logging;

// `dotnet Zaghlol.Api.dll --healthcheck` is used by container health checks (the runtime image has no shell or curl).
if (args.Contains("--healthcheck", StringComparer.Ordinal))
{
    return await HealthProbe.RunAsync();
}

var builder = WebApplication.CreateBuilder(args);

builder.WebHost.ConfigureKestrel(options => options.AddServerHeader = false);

builder.Host.UseSerilog((_, services, logger) =>
{
    logger.ConfigureZaghlol("api");
    foreach (var sink in services.GetServices<ILogEventSink>())
    {
        logger.WriteTo.Sink(sink);
    }
});

builder.Services.AddApplication();
builder.Services.AddInfrastructure();
builder.Services.AddProblemDetails(options => options.CustomizeProblemDetails = ProblemDetailsCustomizer.Customize);
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseSerilogRequestLogging();

app.MapHealth();

await app.RunAsync();
return 0;

public partial class Program;
