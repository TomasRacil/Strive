# Compile and run the watch unit tests in the Connect IQ simulator.
#
#   .\test.ps1                # build, launch the simulator, run every test
#   .\test.ps1 -KeepSimulator # leave the simulator running afterwards
#
# The simulator is a GUI process, so this starts it if it is not already up and
# waits for it to accept a push. Tests that need a radio or a heart-rate strap
# cannot be covered here: Sensor.getInfo() returns a null heartRate in the
# simulator, which is exactly the case the app has to survive.

param(
    [string]$Device = "fenix847mm",
    [string]$Sdk = "",
    [switch]$KeepSimulator
)

$ErrorActionPreference = "Stop"

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
$monkeydo = Join-Path $Sdk "bin\monkeydo.bat"
$simulator = Join-Path $Sdk "bin\simulator.exe"

$key = "keys\developer_key.der"
if (-not (Test-Path $key)) {
    Write-Host "Missing developer key at $key." -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Force -Path build | Out-Null

& $monkeyc -f test.jungle -d $Device -o "build\Strive-test.prg" -y $key -t
if ($LASTEXITCODE -ne 0) {
    Write-Host "Test build failed." -ForegroundColor Red
    exit $LASTEXITCODE
}

$running = Get-Process simulator -ErrorAction SilentlyContinue
if (-not $running) {
    Write-Host "Starting the Connect IQ simulator for $Device..."
    $sim = Start-Process -FilePath $simulator -ArgumentList "-d", $Device -PassThru
    Start-Sleep -Seconds 18
}

& $monkeydo "build\Strive-test.prg" $Device /t
$code = $LASTEXITCODE

if (-not $KeepSimulator) {
    Get-Process simulator -ErrorAction SilentlyContinue | Stop-Process -Force
}

if ($code -ne 0) {
    Write-Host "Tests failed." -ForegroundColor Red
    exit $code
}
Write-Host "Tests passed." -ForegroundColor Green
