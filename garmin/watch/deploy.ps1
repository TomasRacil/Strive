# Copy the built .prg onto a watch connected as an MTP device.
#
#   .\deploy.ps1
#   .\deploy.ps1 -Source build\Strive-fenix847mm.prg
#
# The fenix presents as an MTP device, not a drive, so there is no path to copy
# to and `Copy-Item` cannot see it. The Shell COM object can: it walks "This PC"
# the way Explorer does, which is the only interface Windows gives for MTP.
#
# The watch indexes Connect IQ apps at boot, so the app will not appear in the
# activity list until the watch is restarted.

param(
    [string]$Source = "build\Strive-fenix847mm.prg",
    [string]$DeviceName = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Source)) {
    Write-Host "No build at $Source. Run .\build.ps1 first." -ForegroundColor Red
    exit 1
}
$full = (Resolve-Path $Source).Path

$shell = New-Object -ComObject Shell.Application
$pc = $shell.NameSpace(17)   # ssfDRIVES: "This PC", which is where MTP devices live

$watch = $null
foreach ($item in $pc.Items()) {
    if ($DeviceName -ne "") {
        if ($item.Name -like "*$DeviceName*") { $watch = $item; break }
    } elseif ($item.Name -match 'fenix|Forerunner|Garmin|quatix|tactix|epix') {
        $watch = $item
        break
    }
}

if ($null -eq $watch) {
    Write-Host "No Garmin device under This PC. Unlock the watch, plug it in, and pick 'File transfer' if it asks." -ForegroundColor Red
    exit 1
}
Write-Host "Device: $($watch.Name)"

# Internal Storage is the MTP store name; GARMIN\APPS is where sideloaded apps go.
$storage = $null
foreach ($child in $watch.GetFolder.Items()) {
    if ($child.Name -match 'Internal Storage|Internal shared storage') { $storage = $child; break }
}
if ($null -eq $storage) {
    Write-Host "No Internal Storage on $($watch.Name)." -ForegroundColor Red
    exit 1
}

function Find-Folder($folderItem, [string[]]$names) {
    $current = $folderItem
    foreach ($name in $names) {
        $next = $null
        foreach ($child in $current.GetFolder.Items()) {
            if ($child.Name -ieq $name) { $next = $child; break }
        }
        if ($null -eq $next) { return $null }
        $current = $next
    }
    return $current
}

$apps = Find-Folder $storage @("GARMIN", "APPS")
if ($null -eq $apps) {
    $apps = Find-Folder $storage @("GARMIN", "Apps")
}
if ($null -eq $apps) {
    Write-Host "No GARMIN\APPS folder. Is this the right device?" -ForegroundColor Red
    exit 1
}

$target = $apps.GetFolder
$leaf = Split-Path $full -Leaf
Write-Host "Copying $leaf to $($watch.Name)\Internal Storage\GARMIN\APPS ..."
$target.CopyHere($full, 0x14)   # 0x14 = no progress dialog, no confirmation

Start-Sleep -Seconds 2
$landed = $null
foreach ($child in $target.Items()) {
    if ($child.Name -ieq $leaf) { $landed = $child; break }
}

if ($null -eq $landed) {
    Write-Host "Copy did not land. Unplug and try again; MTP writes fail silently when the watch is asleep." -ForegroundColor Red
    exit 1
}

Write-Host "Copied $($landed.Name) ($($landed.Size) bytes)." -ForegroundColor Green
Write-Host "Restart the watch, then find Strive at the end of the activity list."
