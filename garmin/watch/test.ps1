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
    [int]$LockTimeoutSeconds = 1800,
    [switch]$KeepSimulator
)

$ErrorActionPreference = "Stop"

# monkeyc.bat shells out to java, which is not on PATH on a clean Windows shell.
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    $jdk = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "bin\java.exe") } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($jdk) {
        $env:JAVA_HOME = $jdk.FullName
        $env:PATH = (Join-Path $jdk.FullName "bin") + ";" + $env:PATH
    } else {
        Write-Host "No java on PATH and no Adoptium JDK found. Install JDK 21." -ForegroundColor Red
        exit 1
    }
}

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
$lockPath = "build\.simlock"

# One simulator at a time: a second monkeydo would push to the same instance and
# interleave two suites.
$deadline = (Get-Date).AddSeconds($LockTimeoutSeconds)
$held = $false
while (-not $held) {
    try {
        New-Item -ItemType Directory -Path $lockPath -ErrorAction Stop | Out-Null
        $held = $true
    } catch {
        if ((Get-Date) -gt $deadline) {
            Write-Host "Simulator lock held by another run for over $LockTimeoutSeconds s." -ForegroundColor Red
            exit 1
        }
        Start-Sleep -Seconds 3
    }
}

$startedSimulator = $false
try {
    & $monkeyc -f test.jungle -d $Device -o "build\Strive-test.prg" -y $key -t
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Test build failed." -ForegroundColor Red
        exit $LASTEXITCODE
    }

    if (-not (Get-Process simulator -ErrorAction SilentlyContinue)) {
        Write-Host "Starting the Connect IQ simulator for $Device..."
        Start-Process -FilePath $simulator -ArgumentList "-d", $Device | Out-Null
        $startedSimulator = $true
        Start-Sleep -Seconds 30
    }

    # The simulator takes a variable time to open its port, and on a loaded
    # machine it can accept the connection and then never answer at all. Each
    # attempt is therefore bounded: a monkeydo that hangs must not hang the
    # script, or a wedged simulator looks like a test run that never ends.
    $raw = ""
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        $outFile = Join-Path $PWD "build\test-run-$attempt.log"
        $proc = Start-Process -FilePath $monkeydo `
            -ArgumentList @("build\Strive-test.prg", $Device, "/t") `
            -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError "$outFile.err"
        $finished = $proc.WaitForExit(120000)
        if (-not $finished) {
            Write-Host "monkeydo did not answer in 120 s (attempt $attempt); stopping it." -ForegroundColor Yellow
            try { $proc.Kill() } catch { }
        }
        $raw = (Get-Content $outFile -Raw -ErrorAction SilentlyContinue) + (Get-Content "$outFile.err" -Raw -ErrorAction SilentlyContinue)
        if ($raw -and $raw -notmatch 'Unable to connect to simulator') {
            break
        }
        Write-Host "Simulator not ready (attempt $attempt), waiting..."
        Start-Sleep -Seconds 10
    }
    Write-Host $raw

    # monkeydo exits 0 whether the suite passed or failed, so the summary line is
    # the only honest signal. Requiring the explicit PASSED line also catches the
    # case where monkeydo never reached the tests at all.
    if ($raw -match 'PASSED \(passed=\d+, failed=0, errors=0\)') {
        $code = 0
    } else {
        $code = 1
    }
} finally {
    if ($startedSimulator -and -not $KeepSimulator) {
        Get-Process simulator -ErrorAction SilentlyContinue | Stop-Process -Force
    }
    Remove-Item -Recurse -Force $lockPath -ErrorAction SilentlyContinue
}

if ($code -ne 0) {
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Write-Host "The simulator did not answer: monkeydo returned nothing." -ForegroundColor Red
        Write-Host "It is running but wedged (no device loaded, no output). Kill it, then reboot or log out and back in: on this machine it has stayed wedged across restarts of simulator.exe alone." -ForegroundColor Yellow
    } else {
        Write-Host "Tests failed." -ForegroundColor Red
    }
    exit $code
}
Write-Host "Tests passed." -ForegroundColor Green
