# Bring the simulator to the foreground and click the centre of the watch
# display, to capture the weight picker for the store listing.

param(
    [int]$ProcessId = 27876,
    [int]$X = 446,
    [int]$Y = 555
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinClick {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, IntPtr dwExtraInfo);
}
"@

$proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
if (-not $proc) { Write-Host "process not found"; exit 1 }

[WinClick]::ShowWindow($proc.MainWindowHandle, 9) | Out-Null
[WinClick]::SetForegroundWindow($proc.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 700

[WinClick]::SetCursorPos($X, $Y) | Out-Null
Start-Sleep -Milliseconds 200
[WinClick]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)   # left down
Start-Sleep -Milliseconds 60
[WinClick]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)   # left up

Write-Host "clicked $X,$Y"
Start-Sleep -Milliseconds 1200
