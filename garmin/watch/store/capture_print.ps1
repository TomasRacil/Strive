# Capture the Connect IQ simulator window to a PNG using PrintWindow.
#
# CopyFromScreen captures the desktop at the window's coordinates, so anything
# covering the window ends up in the image. PrintWindow asks the window to
# render itself, which works even when it is occluded.

param(
    [int]$ProcessId = 0,
    [string]$Out = "C:\GitFiles\Strive\garmin\watch\store\screenshot_full.png"
)

Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinPrint {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, uint nFlags);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@

$proc = if ($ProcessId -gt 0) {
    Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
} else {
    Get-Process simulator -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}

if (-not $proc -or $proc.MainWindowHandle -eq 0) {
    Write-Host "No simulator window found." -ForegroundColor Red
    exit 1
}

Write-Host "window: $($proc.MainWindowTitle)"

$rect = New-Object WinPrint+RECT
[WinPrint]::GetWindowRect($proc.MainWindowHandle, [ref]$rect) | Out-Null
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
Write-Host "size: ${width}x${height}"

$bmp = New-Object System.Drawing.Bitmap $width, $height
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $gfx.GetHdc()
# 0x00000002 = PW_RENDERFULLCONTENT, required for hardware-accelerated windows
$ok = [WinPrint]::PrintWindow($proc.MainWindowHandle, $hdc, 2)
$gfx.ReleaseHdc($hdc)
$gfx.Dispose()

if (-not $ok) {
    Write-Host "PrintWindow failed." -ForegroundColor Red
    $bmp.Dispose()
    exit 1
}

$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Write-Host "saved $Out ($((Get-Item $Out).Length) bytes)"
