using System.Buffers.Binary;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Zaghlol.Infrastructure.Kms;

/// <summary>What <c>statx</c> says about one file system entry (T-200 design note §3).</summary>
internal readonly record struct PosixStat(uint Uid, uint Mode, ulong Inode, uint DevMajor, uint DevMinor, ulong Size)
{
    public const uint TypeMask = 0xF000;
    public const uint TypeRegular = 0x8000;
    public const uint TypeDirectory = 0x4000;
    public const uint TypeSymlink = 0xA000;
    public const uint Sticky = 0x200;

    public bool IsRegular => (Mode & TypeMask) == TypeRegular;

    public bool IsDirectory => (Mode & TypeMask) == TypeDirectory;

    public bool IsSymlink => (Mode & TypeMask) == TypeSymlink;

    /// <summary>Any group or other permission bit (<c>mode &amp; 0o077</c>).</summary>
    public bool HasGroupOrOtherBits => (Mode & 0x3F) != 0;

    /// <summary>Group or other may write (<c>mode &amp; 0o022</c>).</summary>
    public bool GroupOrOtherWritable => (Mode & 0x12) != 0;

    public bool IsSticky => (Mode & Sticky) != 0;

    public bool SameFileAs(PosixStat other) => Inode == other.Inode && DevMajor == other.DevMajor && DevMinor == other.DevMinor;
}

/// <summary>
/// Linux file ownership and mode through glibc <c>statx</c>: .NET exposes the mode but not the owner. <c>struct statx</c> has
/// the same 256-byte layout on every architecture. Any failure (another OS, a missing symbol, an errno) is reported as
/// <c>null</c> and the callers refuse to start; no errno text or path ever reaches a message.
/// </summary>
internal static class PosixFiles
{
    private const string LibC = "libc.so.6";
    private const int AtFdCwd = -100;
    private const int AtSymlinkNoFollow = 0x100;
    private const int AtEmptyPath = 0x1000;

    // STATX_TYPE | STATX_MODE | STATX_UID | STATX_INO | STATX_SIZE: the fields this file reads.
    private const uint NeededMask = 0x1 | 0x2 | 0x8 | 0x100 | 0x200;
    private const int StatxSize = 256;
    private const int PrGetDumpable = 3;
    private const int PrSetDumpable = 4;

    /// <summary>The effective uid, or <c>null</c> when it can't be read.</summary>
    public static uint? EffectiveUid()
    {
        if (!OperatingSystem.IsLinux())
        {
            return null;
        }

        try
        {
            return NativeMethods.geteuid();
        }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException)
        {
            return null;
        }
    }

    /// <summary>
    /// <c>prctl(PR_SET_DUMPABLE, 0)</c> (review S2): no core file of this process, and no same-uid <c>ptrace</c> or
    /// <c>/proc/&lt;pid&gt;/mem</c> read by another process. False when the call is unavailable or fails.
    /// </summary>
    public static bool SetNotDumpable()
    {
        if (!OperatingSystem.IsLinux())
        {
            return false;
        }

        try
        {
            return NativeMethods.prctl(PrSetDumpable, 0, 0, 0, 0) == 0 && Dumpable() == 0;
        }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException)
        {
            return false;
        }
    }

    /// <summary><c>prctl(PR_GET_DUMPABLE)</c>, or <c>null</c> when it can't be read.</summary>
    public static int? Dumpable()
    {
        if (!OperatingSystem.IsLinux())
        {
            return null;
        }

        try
        {
            var result = NativeMethods.prctl(PrGetDumpable, 0, 0, 0, 0);
            return result < 0 ? null : result;
        }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException)
        {
            return null;
        }
    }

    /// <summary><c>lstat</c>-like: the entry itself, a symlink is not followed. <c>null</c> on any error.</summary>
    public static PosixStat? LStat(string path) => Statx(AtFdCwd, path, AtSymlinkNoFollow);

    /// <summary>The file behind an open handle. <c>null</c> on any error.</summary>
    public static PosixStat? FStat(SafeFileHandle handle)
    {
        ArgumentNullException.ThrowIfNull(handle);
        var added = false;
        try
        {
            handle.DangerousAddRef(ref added);
            return Statx((int)handle.DangerousGetHandle(), string.Empty, AtEmptyPath);
        }
        finally
        {
            if (added)
            {
                handle.DangerousRelease();
            }
        }
    }

    private static PosixStat? Statx(int dirFd, string path, int flags)
    {
        if (!OperatingSystem.IsLinux())
        {
            return null;
        }

        var buffer = new byte[StatxSize];
        int result;
        try
        {
            result = NativeMethods.statx(dirFd, path, flags, NeededMask, buffer);
        }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException)
        {
            return null;
        }

        if (result != 0)
        {
            return null;
        }

        var span = buffer.AsSpan();
        var mask = BinaryPrimitives.ReadUInt32LittleEndian(span) & NeededMask;
        if (!BitConverter.IsLittleEndian || mask != NeededMask)
        {
            return null;
        }

        return new PosixStat(
            Uid: BinaryPrimitives.ReadUInt32LittleEndian(span[20..]),
            Mode: BinaryPrimitives.ReadUInt16LittleEndian(span[28..]),
            Inode: BinaryPrimitives.ReadUInt64LittleEndian(span[32..]),
            DevMajor: BinaryPrimitives.ReadUInt32LittleEndian(span[136..]),
            DevMinor: BinaryPrimitives.ReadUInt32LittleEndian(span[140..]),
            Size: BinaryPrimitives.ReadUInt64LittleEndian(span[40..]));
    }

    private static class NativeMethods
    {
        [DllImport(LibC, SetLastError = true)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.SafeDirectories)]
#pragma warning disable SYSLIB1054 // LibraryImport needs AllowUnsafeBlocks for the whole assembly; two blittable calls don't justify it.
        public static extern int statx(int dirfd, [MarshalAs(UnmanagedType.LPUTF8Str)] string pathname, int flags, uint mask, [Out] byte[] statxbuf);

        [DllImport(LibC)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.SafeDirectories)]
        public static extern uint geteuid();

        // prctl is variadic in C; on the Linux x64 and arm64 ABIs integer varargs pass like fixed arguments.
        [DllImport(LibC, SetLastError = true)]
        [DefaultDllImportSearchPaths(DllImportSearchPath.SafeDirectories)]
        public static extern int prctl(int option, nuint arg2, nuint arg3, nuint arg4, nuint arg5);
#pragma warning restore SYSLIB1054
    }
}
