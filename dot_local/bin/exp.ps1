<#
.SYNOPSIS
Opens several folders as tabs in one Windows 11 File Explorer window.

.DESCRIPTION
Explorer exposes no documented tab API, but tabs can be driven without synthetic
keystrokes:

  * A tab is created by posting WM_COMMAND 0xA21B - the internal command id
    behind Ctrl+T - to the window's ShellTabWindowClass child.
  * The new tab is then matched to its SHDocVw shell view by asking each view's
    IServiceProvider for IShellBrowser and comparing IOleWindow::GetWindow to
    the tab handle, and navigated with the documented IWebBrowser2::Navigate2.

Only the command id is undocumented; nothing here depends on keyboard focus, so
the script is safe to run while you keep typing.

Requires Windows 11 22H2 (build 22621) or later.

.PARAMETER Path
Folders to open, absolute or relative to the current directory. The first
becomes the window, the rest become tabs. Defaults to the current directory.

.PARAMETER Reuse
Add every folder as a tab to an existing Explorer window instead of opening a
new one. Targets the foreground Explorer window, else the most recent.

.PARAMETER TimeoutSeconds
How long to wait for a window, tab, or shell view to appear.

.EXAMPLE
Open-ExplorerTabs

Opens the current directory.

.EXAMPLE
Open-ExplorerTabs foo/bar ../baz

.EXAMPLE
Open-ExplorerTabs C:\Windows C:\Users $env:TEMP

.EXAMPLE
Open-ExplorerTabs -Reuse .

Adds the current directory as a tab to the Explorer window already open.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments)]
    [string[]]$Path = @('.'),

    [switch]$Reuse,

    [ValidateRange(1, 60)]
    [int]$TimeoutSeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace WinExp {

[ComImport, Guid("6d5140c1-7436-11ce-8034-00aa006009fa"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IServiceProvider {
    [PreserveSig] int QueryService(ref Guid guidService, ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out object ppvObject);
}

// Only IOleWindow::GetWindow is declared; it is the first slot after IUnknown,
// so the rest of the vtable never has to be described.
[ComImport, Guid("000214E2-0000-0000-C000-000000000046"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IShellBrowser {
    [PreserveSig] int GetWindow(out IntPtr phwnd);
}

public static class Tabs {
    const uint WM_COMMAND = 0x0111;
    const int  IDM_NEW_TAB = 0xA21B;
    const string TAB_CLASS = "ShellTabWindowClass";

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
    [DllImport("user32.dll")]
    static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")]
    static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder buf, int max);

    public static IntPtr[] TabHandles(IntPtr frame) {
        var found = new List<IntPtr>();
        IntPtr child = IntPtr.Zero;
        while ((child = FindWindowEx(frame, child, TAB_CLASS, null)) != IntPtr.Zero)
            found.Add(child);
        return found.ToArray();
    }

    public static bool NewTab(IntPtr frame) {
        var tabs = TabHandles(frame);
        if (tabs.Length == 0) return false;
        return PostMessage(tabs[0], WM_COMMAND, (IntPtr)IDM_NEW_TAB, IntPtr.Zero);
    }

    // Maps a SHDocVw shell view to the tab window that hosts it.
    public static IntPtr HostTabOf(object shellWindow) {
        var sp = shellWindow as IServiceProvider;
        if (sp == null) return IntPtr.Zero;
        var iid = typeof(IShellBrowser).GUID;
        object browser;
        if (sp.QueryService(ref iid, ref iid, out browser) != 0 || browser == null)
            return IntPtr.Zero;
        IntPtr hwnd;
        int hr = ((IShellBrowser)browser).GetWindow(out hwnd);
        Marshal.ReleaseComObject(browser);
        return hr == 0 ? hwnd : IntPtr.Zero;
    }

    public static IntPtr Foreground() { return GetForegroundWindow(); }

    public static string ClassOf(IntPtr hWnd) {
        var buf = new System.Text.StringBuilder(256);
        GetClassName(hWnd, buf, buf.Capacity);
        return buf.ToString();
    }
}
}
'@

function Get-ShellView {
    $shell = New-Object -ComObject Shell.Application
    try {
        @($shell.Windows() | Where-Object { $_.FullName -like '*\explorer.exe' })
    }
    finally {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}

function Get-ExplorerFrame {
    @(Get-ShellView | ForEach-Object { [IntPtr]$_.HWND }) | Sort-Object -Unique
}

function Wait-For {
    param([scriptblock]$Condition, [string]$What)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $result = & $Condition
        if ($result) { return $result }
        Start-Sleep -Milliseconds 120
    } while ((Get-Date) -lt $deadline)
    throw "Timed out after ${TimeoutSeconds}s waiting for $What."
}

$folders = @(foreach ($p in $Path) {
    $resolved = Resolve-Path -LiteralPath $p
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "Not a folder: $p"
    }
    $resolved.ProviderPath
})

if ($Reuse) {
    $frames = Get-ExplorerFrame
    if (-not $frames) { throw 'No Explorer window is open; drop -Reuse.' }
    $front = [WinExp.Tabs]::Foreground()
    $frame = if ($front -in $frames) { $front } else { $frames[-1] }
    $tabs = $folders
}
else {
    $before = Get-ExplorerFrame
    Start-Process explorer.exe -ArgumentList "/n,`"$($folders[0])`""
    $frame = Wait-For { (Get-ExplorerFrame | Where-Object { $_ -notin $before }) | Select-Object -First 1 } 'the new Explorer window'
    $tabs = $folders | Select-Object -Skip 1
}

foreach ($folder in $tabs) {
    $existing = [WinExp.Tabs]::TabHandles($frame)
    if (-not [WinExp.Tabs]::NewTab($frame)) {
        throw "No $([WinExp.Tabs]::ClassOf($frame)) tab host under window $frame - is this Windows 11 22H2 or later?"
    }

    $tab = Wait-For { ([WinExp.Tabs]::TabHandles($frame) | Where-Object { $_ -notin $existing }) | Select-Object -First 1 } 'the new tab'

    $view = Wait-For { Get-ShellView | Where-Object { [WinExp.Tabs]::HostTabOf($_) -eq $tab } | Select-Object -First 1 } 'the new tab to publish a shell view'

    $view.Navigate2($folder)
    Write-Verbose "tab $tab -> $folder"
}

Write-Verbose "Opened $($folders.Count) folder(s) in window $frame."
