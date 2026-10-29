# Build a .prg for one device and copy it to the watch.
#
#   .\build.ps1 -Device fenix7
#   .\build.ps1 -Device fenix7 -Deploy E:\
#
# Run `monkeyc --devices` (or check the SDK manager) for the exact id of your
# watch; the manifest must list the same id.

param(
    [string]$Device = "fenix847mm",
    [string]$Deploy = "",
    [string]$Sdk = ""
)

$ErrorActionPreference = "Stop"

# The SDK directory name carries a version and date, so read the active SDK from
# the manager's config instead of hardcoding a path that will go stale.
if ($Sdk -eq "") {
    $sdkConfig = Join-Path $env:APPDATA "Garmin\ConnectIQ\current-sdk.cfg"
    if (Test-Path $sdkConfig) {
        $Sdk = (Get-Content $sdkConfig -Raw).Trim()
    } else {
        Write-Host "No active SDK found. Run sdkmanager.exe and install a Connect IQ SDK." -ForegroundColor Red
        exit 1
    }
}

$monkeyc = Join-Path $Sdk "bin\monkeyc.bat"
if (-not (Test-Path $monkeyc)) {
    Write-Host "monkeyc not found at $monkeyc" -ForegroundColor Red
    Write-Host "Install the Connect IQ SDK with sdkmanager.exe, then pass -Sdk <path>." -ForegroundColor Yellow
    exit 1
}

$key = "keys\developer_key.der"
if (-not (Test-Path $key)) {
    Write-Host "Missing developer key. Generate one:" -ForegroundColor Yellow
    Write-Host '  openssl genrsa -out keys/developer_key.pem 4096'
    Write-Host '  openssl pkcs8 -topk8 -inform PEM -outform DER -in keys/developer_key.pem -out keys/developer_key.der -nocrypt'
    exit 1
}

New-Item -ItemType Directory -Force -Path build | Out-Null

& $monkeyc -f monkey.jungle -d $Device -o "build\Strive-$Device.prg" -y $key --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "Built build\Strive-$Device.prg" -ForegroundColor Green

if ($Deploy -ne "") {
    $apps = Join-Path $Deploy "GARMIN\APPS"
    if (-not (Test-Path $apps)) {
        Write-Host "No GARMIN\APPS at $Deploy - is the watch mounted?" -ForegroundColor Red
        exit 1
    }
    Copy-Item "build\Strive-$Device.prg" $apps -Force
    Write-Host "Copied to $apps. Unplug, then find Strive in the watch app list." -ForegroundColor Green
}
