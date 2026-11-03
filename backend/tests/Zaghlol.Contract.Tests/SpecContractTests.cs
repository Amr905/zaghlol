using System.Globalization;
using System.Text.Json.Nodes;

namespace Zaghlol.Contract.Tests;

/// <summary>
/// Structural and privacy checks on <c>zaghlol-v1.yaml</c>: closed request schemas (BR-SYNC-03), problem+json
/// on every error, signature / idempotency / install headers where backend-api.md requires them, and no
/// floating point money.
/// </summary>
public class SpecContractTests
{
    private const string UnexpectedField = "unexpectedField";

    private static readonly OpenApiSpec Spec = OpenApiSpec.Load();

    private static readonly string[] SignedOperations =
        ["sync", "verifyPurchase", "restorePurchases", "getEntitlement", "signIn", "getFullCatalog"];

    private static readonly string[] IdempotentOperations = ["registerInstall", "verifyPurchase", "signIn"];

    [Fact]
    public void SpecIsOpenApi31WithVersionedPaths()
    {
        Assert.StartsWith("3.1", Spec.Root["openapi"]!.GetValue<string>(), StringComparison.Ordinal);
        foreach (var operation in Spec.Operations())
        {
            Assert.True(
                operation.Path.StartsWith("/v1/", StringComparison.Ordinal) || operation.Path.StartsWith("/admin/v1/", StringComparison.Ordinal),
                $"{operation.Label} is not under /v1 or /admin/v1");
        }
    }

    [Fact]
    public void OperationIdsAreUniqueAndEveryOperationHasASuccessResponse()
    {
        var operations = Spec.Operations();
        var ids = operations.Select(o => o.Id).ToList();
        Assert.Equal(ids.Count, ids.Distinct(StringComparer.Ordinal).Count());
        foreach (var operation in operations)
        {
            var statuses = operation.Body["responses"]!.AsObject().Select(r => r.Key);
            Assert.Contains(statuses, s => s.StartsWith('2') || s.StartsWith('3'));
        }
    }

    [Fact]
    public void RequestSchemasAreClosedSoUnknownFieldsAreRejected()
    {
        var violations = new List<string>();
        var checkedSchemas = 0;
        foreach (var operation in Spec.Operations())
        {
            var schema = Spec.RequestSchema(operation);
            if (schema is null)
            {
                continue;
            }

            checkedSchemas++;
            Spec.CollectOpenObjects(schema, operation.Label, violations, new HashSet<string>(StringComparer.Ordinal));
        }

        Assert.True(checkedSchemas >= 11, "expected every body-carrying operation to be checked");
        Assert.Empty(violations);
    }

    [Fact]
    public void EveryRequestBodyHasAnExampleThatIsValidAndRejectsAnUnknownFieldAnywhere()
    {
        var failures = new List<string>();
        foreach (var operation in Spec.Operations())
        {
            var schema = Spec.RequestSchema(operation);
            if (schema is null)
            {
                continue;
            }

            var example = operation.Body["requestBody"]!["content"]!["application/json"]!["example"];
            if (example is null)
            {
                failures.Add($"{operation.Label}: request body has no example");
                continue;
            }

            var problem = Spec.Validate(schema, example);
            if (problem is not null)
            {
                failures.Add($"{operation.Label}: example is invalid: {problem}");
                continue;
            }

            foreach (var (where, mutated) in WithUnknownField(example))
            {
                if (Spec.Validate(schema, mutated) is null)
                {
                    failures.Add($"{operation.Label}: an unknown field at '{where}' was accepted");
                }
            }
        }

        Assert.Empty(failures);
    }

    [Fact]
    public void AllResponseExamplesConformToTheirSchemas()
    {
        var failures = new List<string>();
        var checkedExamples = 0;
        foreach (var operation in Spec.Operations())
        {
            foreach (var (status, responseNode) in operation.Body["responses"]!.AsObject())
            {
                var response = Spec.Resolve(responseNode!);
                if (response["content"] is not JsonObject content)
                {
                    continue;
                }

                foreach (var (mediaType, media) in content)
                {
                    var schema = media!["schema"];
                    if (schema is null)
                    {
                        continue;
                    }

                    var examples = new List<JsonNode?>();
                    if (media["example"] is { } single)
                    {
                        examples.Add(single);
                    }

                    if (media["examples"] is JsonObject named)
                    {
                        examples.AddRange(named.Select(e => e.Value!["value"]));
                    }

                    foreach (var example in examples)
                    {
                        checkedExamples++;
                        var problem = Spec.Validate(schema, example);
                        if (problem is not null)
                        {
                            failures.Add($"{operation.Label} {status} {mediaType}: {problem}");
                        }
                    }
                }
            }
        }

        Assert.True(checkedExamples > 0);
        Assert.Empty(failures);
    }

    [Fact]
    public void NoFloatingPointOrNumberTypedMoneyAnywhereInTheContract()
    {
        var offenders = new List<string>();
        FindNumberTypes(Spec.Root, "$", offenders);
        Assert.Empty(offenders);
    }

    [Fact]
    public void MoneyAndPricesAreDecimalStrings()
    {
        Assert.Equal("string", Spec.Schemas["DecimalString"]!["type"]!.GetValue<string>());

        foreach (var (propertyOwner, property) in new[] { ("GoldPrice", "price"), ("PriceOverrideRequest", "price"), ("PriceOverrideResponse", "price") })
        {
            var reference = Spec.Schemas[propertyOwner]!["properties"]![property]!["$ref"]!.GetValue<string>();
            Assert.Equal("#/components/schemas/DecimalString", reference);
        }

        Assert.Equal(
            "#/components/schemas/DecimalString",
            Spec.Schemas["FxBlock"]!["properties"]!["rates"]!["additionalProperties"]!["$ref"]!.GetValue<string>());
    }

    [Fact]
    public void EveryOperationDeclaresProblemJsonErrors()
    {
        var failures = new List<string>();
        foreach (var operation in Spec.Operations())
        {
            var responses = operation.Body["responses"]!.AsObject();
            Require(failures, operation, responses, "429");
            Require(failures, operation, responses, "500");

            if (operation.Body["requestBody"] is not null)
            {
                Require(failures, operation, responses, "400");
                Require(failures, operation, responses, "413");
                Require(failures, operation, responses, "415");
            }

            if (operation.Body["security"] is JsonArray { Count: > 0 })
            {
                Require(failures, operation, responses, "401");
            }

            if (operation.Path.StartsWith("/admin/", StringComparison.Ordinal))
            {
                Require(failures, operation, responses, "403");
            }

            foreach (var (status, responseNode) in responses)
            {
                if (!(status.StartsWith('4') || status.StartsWith('5')))
                {
                    continue;
                }

                var schema = Spec.Resolve(responseNode!)["content"]?["application/problem+json"]?["schema"]?["$ref"]?.GetValue<string>();
                if (schema != "#/components/schemas/Problem")
                {
                    failures.Add($"{operation.Label} {status}: error response is not application/problem+json with the Problem schema");
                }
            }
        }

        Assert.Empty(failures);
    }

    [Fact]
    public void SignedResponsesCarryTheSignatureHeader()
    {
        var operations = Spec.Operations().ToDictionary(o => o.Id, StringComparer.Ordinal);
        foreach (var id in SignedOperations)
        {
            var response = Spec.Resolve(operations[id].Body["responses"]!["200"]!);
            Assert.True(response["headers"]?["Zaghlol-Signature"] is not null, $"{id}: 200 response lacks Zaghlol-Signature");
        }
    }

    [Fact]
    public void IdempotencyKeyIsRequiredExactlyWhereTheDocumentSaysSo()
    {
        var withKey = Spec.Operations()
            .Where(o => ParameterRefs(o).Contains("#/components/parameters/IdempotencyKey"))
            .Select(o => o.Id)
            .Order(StringComparer.Ordinal)
            .ToList();

        Assert.Equal(IdempotentOperations.Order(StringComparer.Ordinal).ToList(), withKey);
    }

    [Fact]
    public void InstallScopedOperationsRequireTheAppAndInstallHeaders()
    {
        var failures = new List<string>();
        foreach (var operation in Spec.Operations())
        {
            var requirements = operation.Body["security"] as JsonArray;
            if (requirements is null)
            {
                continue;
            }

            foreach (var requirement in requirements.OfType<JsonObject>())
            {
                if (requirement.ContainsKey("accountToken") && !requirement.ContainsKey("installToken"))
                {
                    failures.Add($"{operation.Label}: accountToken is only valid together with installToken");
                }
            }

            if (requirements.OfType<JsonObject>().Any(r => r.ContainsKey("installToken")))
            {
                var refs = ParameterRefs(operation);
                if (!refs.Contains("#/components/parameters/ZaghlolApp") || !refs.Contains("#/components/parameters/ZaghlolInstall"))
                {
                    failures.Add($"{operation.Label}: install-scoped operation must require Zaghlol-App and Zaghlol-Install");
                }
            }
        }

        Assert.Empty(failures);
    }

    [Fact]
    public void AdminEndpointsAreSeparatedAndRoleProtected()
    {
        var failures = new List<string>();
        foreach (var operation in Spec.Operations())
        {
            var isAdmin = operation.Path.StartsWith("/admin/", StringComparison.Ordinal);
            var schemes = (operation.Body["security"] as JsonArray ?? new JsonArray())
                .OfType<JsonObject>()
                .SelectMany(r => r.Select(p => p.Key))
                .ToList();

            if (isAdmin)
            {
                if (schemes.Count != 1 || schemes[0] != "operatorOidc")
                {
                    failures.Add($"{operation.Label}: admin operations must use only operatorOidc");
                }

                if (operation.Body["x-required-roles"] is not JsonArray { Count: > 0 })
                {
                    failures.Add($"{operation.Label}: admin operation lacks x-required-roles");
                }
            }
            else if (schemes.Contains("operatorOidc"))
            {
                failures.Add($"{operation.Label}: public operation must not accept operator tokens");
            }
        }

        Assert.Empty(failures);
    }

    [Fact]
    public void NotificationEndpointsNeverAcceptInstallOrAccountTokens()
    {
        foreach (var operation in Spec.Operations().Where(o => o.Path.StartsWith("/v1/notifications/", StringComparison.Ordinal)))
        {
            var schemes = (operation.Body["security"] as JsonArray ?? new JsonArray())
                .OfType<JsonObject>()
                .SelectMany(r => r.Select(p => p.Key))
                .ToList();
            Assert.DoesNotContain("installToken", schemes);
            Assert.DoesNotContain("accountToken", schemes);
        }
    }

    private static void Require(List<string> failures, SpecOperation operation, JsonObject responses, string status)
    {
        if (!responses.ContainsKey(status))
        {
            failures.Add($"{operation.Label}: missing {status} response");
        }
    }

    private static HashSet<string> ParameterRefs(SpecOperation operation)
    {
        var refs = new HashSet<string>(StringComparer.Ordinal);
        if (operation.Body["parameters"] is JsonArray parameters)
        {
            foreach (var parameter in parameters)
            {
                if (parameter?["$ref"] is JsonValue reference)
                {
                    refs.Add(reference.GetValue<string>());
                }
            }
        }

        return refs;
    }

    private static void FindNumberTypes(JsonNode? node, string where, List<string> offenders)
    {
        switch (node)
        {
            case JsonObject obj:
                if (obj["type"] is JsonValue single && single.TryGetValue<string>(out var typeName) && typeName == "number")
                {
                    offenders.Add($"{where}: type number");
                }

                if (obj["type"] is JsonArray types && types.Any(t => t?.GetValue<string>() == "number"))
                {
                    offenders.Add($"{where}: type number");
                }

                if (obj["format"] is JsonValue format && format.TryGetValue<string>(out var formatName) && formatName is "float" or "double")
                {
                    offenders.Add($"{where}: format {formatName}");
                }

                foreach (var (key, child) in obj)
                {
                    FindNumberTypes(child, $"{where}.{key}", offenders);
                }

                break;
            case JsonArray array:
                for (var i = 0; i < array.Count; i++)
                {
                    FindNumberTypes(array[i], $"{where}[{i.ToString(CultureInfo.InvariantCulture)}]", offenders);
                }

                break;
            default:
                break;
        }
    }

    /// <summary>Yields one copy of <paramref name="example"/> per object in it, with an unexpected field added there.</summary>
    private static List<(string Where, JsonNode Mutated)> WithUnknownField(JsonNode example)
    {
        var paths = new List<List<string>>();
        CollectObjectPaths(example, [], paths);

        var result = new List<(string, JsonNode)>();
        foreach (var path in paths)
        {
            var clone = JsonNode.Parse(example.ToJsonString())!;
            var target = clone;
            foreach (var segment in path)
            {
                target = target is JsonArray array
                    ? array[int.Parse(segment, CultureInfo.InvariantCulture)]!
                    : target[segment]!;
            }

            target.AsObject()[UnexpectedField] = "x";
            result.Add((path.Count == 0 ? "$" : "$." + string.Join('.', path), clone));
        }

        return result;
    }

    private static void CollectObjectPaths(JsonNode? node, List<string> current, List<List<string>> output)
    {
        switch (node)
        {
            case JsonObject obj:
                output.Add([.. current]);
                foreach (var (key, child) in obj)
                {
                    current.Add(key);
                    CollectObjectPaths(child, current, output);
                    current.RemoveAt(current.Count - 1);
                }

                break;
            case JsonArray array:
                for (var i = 0; i < array.Count; i++)
                {
                    current.Add(i.ToString(CultureInfo.InvariantCulture));
                    CollectObjectPaths(array[i], current, output);
                    current.RemoveAt(current.Count - 1);
                }

                break;
            default:
                break;
        }
    }
}
