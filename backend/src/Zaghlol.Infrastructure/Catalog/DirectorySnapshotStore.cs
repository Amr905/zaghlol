using System.Globalization;
using System.Text;
using Microsoft.Extensions.Configuration;
using Zaghlol.Application.Catalog;
using Zaghlol.Domain;

namespace Zaghlol.Infrastructure.Catalog;

/// <summary><c>Catalog:Snapshots:Directory</c> or <c>BaseUrl</c> is not set. Constant message.</summary>
public sealed class CatalogStorageConfigurationException : SafeException
{
    public const string DefaultMessage = "Catalog:Snapshots:Directory and Catalog:Snapshots:BaseUrl must be set to publish a catalog.";

    public CatalogStorageConfigurationException()
        : base(DefaultMessage)
    {
    }

    public CatalogStorageConfigurationException(string message)
        : base(message)
    {
    }

    public CatalogStorageConfigurationException(string message, Exception innerException)
        : base(message, innerException)
    {
    }
}

/// <summary>
/// Stores each snapshot as <c>&lt;Directory&gt;/catalog/&lt;version&gt;/full.json.gz</c> with <c>full.json.sig</c> beside it
/// (written to a temporary name, then moved, so a reader never sees half a file). The directory is the origin of the CDN or a
/// volume the bucket sync reads. The recorded URL is <c>&lt;BaseUrl&gt;/v1/catalog/&lt;version&gt;/full</c>, the public address of
/// the snapshot endpoint (the CDN caches it). Settings are read on first use, so a host without them still starts.
/// </summary>
internal sealed class DirectorySnapshotStore(IConfiguration configuration) : ICatalogSnapshotStore
{
    public const string DirectoryKey = "Catalog:Snapshots:Directory";
    public const string BaseUrlKey = "Catalog:Snapshots:BaseUrl";

    public async Task<Uri> PutAsync(int version, ReadOnlyMemory<byte> gzipJson, string signature, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(signature);

        var (directory, baseUrl) = Settings();
        var folder = FolderOf(directory, version);
        Directory.CreateDirectory(folder);
        await WriteAtomicAsync(Path.Combine(folder, "full.json.gz"), gzipJson, cancellationToken);
        await WriteAtomicAsync(Path.Combine(folder, "full.json.sig"), Encoding.ASCII.GetBytes(signature), cancellationToken);
        return new Uri(string.Create(CultureInfo.InvariantCulture, $"{baseUrl}/v1/catalog/{version}/full"));
    }

    public async Task<byte[]?> GetAsync(int version, CancellationToken cancellationToken)
    {
        var (directory, _) = Settings();
        var path = Path.Combine(FolderOf(directory, version), "full.json.gz");
        return File.Exists(path) ? await File.ReadAllBytesAsync(path, cancellationToken) : null;
    }

    private static string FolderOf(string directory, int version) =>
        Path.Combine(directory, "catalog", version.ToString(CultureInfo.InvariantCulture));

    private static async Task WriteAtomicAsync(string path, ReadOnlyMemory<byte> content, CancellationToken cancellationToken)
    {
        var temporary = path + ".tmp";
        await File.WriteAllBytesAsync(temporary, content.ToArray(), cancellationToken);
        File.Move(temporary, path, overwrite: true);
    }

    private (string Root, string BaseUrl) Settings()
    {
        var directory = configuration[DirectoryKey];
        var baseUrl = configuration[BaseUrlKey];
        if (string.IsNullOrWhiteSpace(directory)
            || string.IsNullOrWhiteSpace(baseUrl)
            || !Uri.TryCreate(baseUrl, UriKind.Absolute, out var parsed)
            || parsed.Scheme is not ("https" or "http"))
        {
            throw new CatalogStorageConfigurationException();
        }

        return (directory, baseUrl.TrimEnd('/'));
    }
}
