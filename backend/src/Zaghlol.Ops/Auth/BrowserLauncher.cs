using System.ComponentModel;
using System.Diagnostics;

namespace Zaghlol.Ops.Auth;

/// <summary>Opens the URL with the OS: <c>xdg-open</c>, <c>open</c> or the shell association. No shell string is built on Unix.</summary>
internal sealed class SystemBrowserLauncher : IBrowserLauncher
{
    public bool TryOpen(Uri url)
    {
        ArgumentNullException.ThrowIfNull(url);

        if (url.Scheme != Uri.UriSchemeHttps)
        {
            return false;
        }

        try
        {
            ProcessStartInfo start;
            if (OperatingSystem.IsWindows())
            {
                start = new ProcessStartInfo(url.AbsoluteUri) { UseShellExecute = true };
            }
            else
            {
                start = new ProcessStartInfo(OperatingSystem.IsMacOS() ? "open" : "xdg-open")
                {
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                };
                start.ArgumentList.Add(url.AbsoluteUri);
            }

            using var process = Process.Start(start);
            return process is not null;
        }
        catch (Win32Exception)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }
}
