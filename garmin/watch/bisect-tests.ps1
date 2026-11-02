param(
    [int]$PerTestTimeoutSeconds = 20,
    [string]$Device = "fenix847mm"
)

# Run the watch unit tests ONE AT A TIME, so a test that never returns is named
# instead of taking the whole suite down with it. monkeydo reports nothing at all
# when the run hangs, so the only signal is the timeout.
#
#   .\bisect-tests.ps1            # every test, 20 s each
#   .\bisect-tests.ps1 -Only testBusAckFrameClearsTheOutbox

$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot

$jdk = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName "bin\java.exe") } |
    Sort-Object Name -Descending | Select-Object -First 1
$env:JAVA_HOME = $jdk.FullName
$env:PATH = (Join-Path $jdk.FullName "bin") + ";" + $env:PATH

$sdk = (Get-Content (Join-Path $env:APPDATA "Garmin\ConnectIQ\current-sdk.cfg") -Raw).Trim()
$monkeyc = Join-Path $sdk "bin\monkeyc.bat"
$monkeydo = Join-Path $sdk "bin\monkeydo.bat"
$simulator = Join-Path $sdk "bin\simulator.exe"

New-Item -ItemType Directory -Force -Path build | Out-Null
& $monkeyc -f test.jungle -d $Device -o "build\Strive-test.prg" -y "keys\developer_key.der" -t | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "test build failed"; exit 1 }

$names = @()
foreach ($file in Get-ChildItem test -Filter *.mc) {
    $lines = Get-Content $file.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\(:test\)') {
            for ($j = $i; $j -lt [Math]::Min($i + 3, $lines.Count); $j++) {
                if ($lines[$j] -match 'function\s+(\w+)\s*\(') {
                    $names += $Matches[1]
                    break
                }
            }
        }
    }
}
Write-Host ("{0} tests" -f $names.Count)

Get-Process simulator -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Process -FilePath $simulator -ArgumentList "-d", $Device | Out-Null
Start-Sleep -Seconds 30

$results = @()
foreach ($name in $names) {
    $out = Join-Path $PWD "build\one.out"
    $err = Join-Path $PWD "build\one.err"
    $p = Start-Process -FilePath $monkeydo -ArgumentList "build\Strive-test.prg", $Device, "/t", $name `
        -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $finished = $p.WaitForExit($PerTestTimeoutSeconds * 1000)
    if (-not $finished) {
        try { $p.Kill() } catch { }
        Write-Host ("HANG  {0}" -f $name) -ForegroundColor Red
        $results += [pscustomobject]@{ Test = $name; Status = "HANG" }
        # A hang wedges the simulator too, so restart it before continuing.
        Get-Process simulator -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 3
        Start-Process -FilePath $simulator -ArgumentList "-d", $Device | Out-Null
        Start-Sleep -Seconds 25
        continue
    }
    $text = (Get-Content $out -Raw -ErrorAction SilentlyContinue) + (Get-Content $err -Raw -ErrorAction SilentlyContinue)
    $status = if ($text -match 'PASS') { "PASS" } elseif ($text -match 'FAIL') { "FAIL" } else { "NO OUTPUT" }
    $colour = if ($status -eq "PASS") { "DarkGray" } else { "Yellow" }
    Write-Host ("{0,-8} {1}" -f $status, $name) -ForegroundColor $colour
    $results += [pscustomobject]@{ Test = $name; Status = $status }
}

Write-Host ""
Write-Host "=== summary ==="
$results | Group-Object Status | ForEach-Object { Write-Host ("{0}: {1}" -f $_.Name, $_.Count) }
$results | Where-Object { $_.Status -ne "PASS" } | ForEach-Object { Write-Host ("{0}: {1}" -f $_.Status, $_.Test) }

Get-Process simulator -ErrorAction SilentlyContinue | Stop-Process -Force
