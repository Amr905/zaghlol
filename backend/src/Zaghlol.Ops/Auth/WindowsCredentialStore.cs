using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;

namespace Zaghlol.Ops.Auth;

/// <summary>The Credential Manager blob limits, kept apart from the Windows-only store so that every platform can test them.</summary>
internal static class CredentialBlobLimits
{
    /// <summary>One credential blob holds at most 2560 bytes (CRED_MAX_CREDENTIAL_BLOB_SIZE); a chunk stays well under it.</summary>
    public const int ChunkBytes = 2000;

    public const int MaxChunks = 4;
}

/// <summary>
/// Windows Credential Manager (T-137 design note section 2): a generic credential per chunk, persisted for this user and
/// protected by DPAPI. A credential blob holds at most 2560 bytes, so a token is split over up to <see cref="MaxChunks"/>
/// entries; a longer token is not persisted. This class compiles on every OS but runs only on Windows.
/// </summary>
[SupportedOSPlatform("windows")]
internal sealed partial class WindowsCredentialStore : ITokenStore
{
    private const int ChunkBytes = CredentialBlobLimits.ChunkBytes;
    private const int MaxChunks = CredentialBlobLimits.MaxChunks;
    private const uint CredTypeGeneric = 1;
    private const uint PersistLocalMachine = 2;
    private const int ErrorNotFound = 1168;

    public string Name => "windows-credential-manager";

    public Task<string?> ReadAsync(string key, CancellationToken cancellationToken)
    {
        var builder = new StringBuilder();
        for (var i = 0; i < MaxChunks; i++)
        {
            var chunk = ReadChunk(Target(key, i));
            if (chunk is null)
            {
                break;
            }

            builder.Append(chunk);
        }

        return Task.FromResult<string?>(builder.Length == 0 ? null : builder.ToString());
    }

    public async Task<bool> WriteAsync(string key, string value, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(value);

        var bytes = Encoding.UTF8.GetBytes(value);
        if (bytes.Length == 0 || bytes.Length > ChunkBytes * MaxChunks)
        {
            return false;
        }

        DeleteAll(key);
        for (var i = 0; i * ChunkBytes < bytes.Length; i++)
        {
            var part = bytes.AsSpan(i * ChunkBytes, Math.Min(ChunkBytes, bytes.Length - (i * ChunkBytes)));
            if (!WriteChunk(Target(key, i), part))
            {
                DeleteAll(key);
                return false;
            }
        }

        // "Stored and read back" (ITokenStore.WriteAsync, FU-264 F8): a value that does not come back equal is removed, so a
        // half-working store is never reported as holding the token.
        if (!string.Equals(await ReadAsync(key, cancellationToken).ConfigureAwait(false), value, StringComparison.Ordinal))
        {
            DeleteAll(key);
            return false;
        }

        return true;
    }

    public Task<bool> DeleteAsync(string key, CancellationToken cancellationToken) => Task.FromResult(DeleteAll(key));

    private static string Target(string key, int index) => "zaghlol-ops/" + key + "#" + index.ToString(System.Globalization.CultureInfo.InvariantCulture);

    private static string? ReadChunk(string target)
    {
        if (!CredRead(target, CredTypeGeneric, 0, out var pointer))
        {
            return null;
        }

        try
        {
            var credential = Marshal.PtrToStructure<Credential>(pointer);
            var bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            try
            {
                return Encoding.UTF8.GetString(bytes);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(bytes);
            }
        }
        finally
        {
            CredFree(pointer);
        }
    }

    private static bool WriteChunk(string target, ReadOnlySpan<byte> bytes)
    {
        var name = Marshal.StringToCoTaskMemUni(target);
        var user = Marshal.StringToCoTaskMemUni("zaghlol-ops");
        var blob = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes.ToArray(), 0, blob, bytes.Length);
            var credential = new Credential
            {
                Type = CredTypeGeneric,
                TargetName = name,
                UserName = user,
                CredentialBlobSize = (uint)bytes.Length,
                CredentialBlob = blob,
                Persist = PersistLocalMachine,
            };
            return CredWrite(ref credential, 0);
        }
        finally
        {
            Marshal.Copy(new byte[bytes.Length], 0, blob, bytes.Length);
            Marshal.FreeHGlobal(blob);
            Marshal.FreeCoTaskMem(name);
            Marshal.FreeCoTaskMem(user);
        }
    }

    private static bool DeleteAll(string key)
    {
        for (var i = 0; i < MaxChunks; i++)
        {
            if (!CredDelete(Target(key, i), CredTypeGeneric, 0) && Marshal.GetLastPInvokeError() != ErrorNotFound)
            {
                return false;
            }
        }

        return true;
    }

    [LibraryImport("advapi32.dll", EntryPoint = "CredReadW", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool CredRead(string target, uint type, uint flags, out IntPtr credential);

    [LibraryImport("advapi32.dll", EntryPoint = "CredWriteW", SetLastError = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool CredWrite(ref Credential credential, uint flags);

    [LibraryImport("advapi32.dll", EntryPoint = "CredDeleteW", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool CredDelete(string target, uint type, uint flags);

    [LibraryImport("advapi32.dll", EntryPoint = "CredFree")]
    [DefaultDllImportSearchPaths(DllImportSearchPath.System32)]
    private static partial void CredFree(IntPtr buffer);

    /// <summary>The native CREDENTIALW layout with the FILETIME as two integers.</summary>
    [StructLayout(LayoutKind.Sequential)]
    private struct Credential
    {
        public uint Flags;
        public uint Type;
        public IntPtr TargetName;
        public IntPtr Comment;
        public uint LastWrittenLow;
        public uint LastWrittenHigh;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        public IntPtr UserName;
    }
}
