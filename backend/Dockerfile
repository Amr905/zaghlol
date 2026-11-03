# syntax=docker/dockerfile:1
# One image, two processes: the API (default) and the worker (override the entrypoint).
# Build context: the backend/ directory.

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY global.json Directory.Build.props Directory.Packages.props nuget.config .editorconfig ./
COPY src/Zaghlol.Domain/Zaghlol.Domain.csproj src/Zaghlol.Domain/
COPY src/Zaghlol.Application/Zaghlol.Application.csproj src/Zaghlol.Application/
COPY src/Zaghlol.Infrastructure/Zaghlol.Infrastructure.csproj src/Zaghlol.Infrastructure/
COPY src/Zaghlol.Api/Zaghlol.Api.csproj src/Zaghlol.Api/
COPY src/Zaghlol.Workers/Zaghlol.Workers.csproj src/Zaghlol.Workers/
RUN dotnet restore src/Zaghlol.Api/Zaghlol.Api.csproj \
 && dotnet restore src/Zaghlol.Workers/Zaghlol.Workers.csproj

COPY src/ src/
RUN dotnet publish src/Zaghlol.Api/Zaghlol.Api.csproj -c Release --no-restore -p:UseAppHost=false -o /app/api \
 && dotnet publish src/Zaghlol.Workers/Zaghlol.Workers.csproj -c Release --no-restore -p:UseAppHost=false -o /app/worker

# Chiseled (distroless-style) runtime: no shell, no package manager, non-root by default.
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled AS final
WORKDIR /app
COPY --from=build /app/api ./api
COPY --from=build /app/worker ./worker

ENV ASPNETCORE_ENVIRONMENT=Production \
    ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_EnableDiagnostics=0

# Numeric UID of the built-in non-root "app" user of the .NET images.
USER 1654:1654
EXPOSE 8080
ENTRYPOINT ["dotnet", "/app/api/Zaghlol.Api.dll"]
