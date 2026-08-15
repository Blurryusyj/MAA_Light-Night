$ErrorActionPreference = 'Stop'

$projectPath = $PSScriptRoot
$mumuRoot = 'E:\MuMu Player 12'
$managerPath = Join-Path $mumuRoot 'nx_main\MuMuManager.exe'
$adbPath = Join-Path $mumuRoot 'nx_main\adb.exe'
$configPaths = @(
    (Join-Path $projectPath 'config\maa_pi_config.json'),
    (Join-Path $projectPath 'maafw\config\maa_pi_config.json')
)

if (-not (Test-Path -LiteralPath $managerPath)) {
    throw "MuMuManager.exe not found: $managerPath"
}
if (-not (Test-Path -LiteralPath $adbPath)) {
    throw "adb.exe not found: $adbPath"
}

$managerOutput = & $managerPath info --vmindex all 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Failed to query MuMu instance information: $managerOutput"
}

$managerInfo = ($managerOutput -join [Environment]::NewLine) | ConvertFrom-Json
$instance = $managerInfo.'0'
if ($null -eq $instance -or $instance.error_code -ne 0) {
    throw 'MuMu instance 0 was not found.'
}
if (-not $instance.is_process_started -or -not $instance.is_android_started) {
    throw 'MuMu instance 0 is not fully started.'
}

$adbHost = [string]$instance.adb_host_ip
$adbPort = [int]$instance.adb_port
if ([string]::IsNullOrWhiteSpace($adbHost) -or $adbPort -le 0) {
    throw 'MuMu did not return a valid ADB address.'
}
$address = '{0}:{1}' -f $adbHost, $adbPort

Write-Host "MuMu ADB address: $address" -ForegroundColor Cyan
$connectOutput = & $adbPath connect $address 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "adb connect failed: $connectOutput"
}
Write-Host ($connectOutput -join [Environment]::NewLine)

$deviceState = (& $adbPath -s $address get-state 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $deviceState -ne 'device') {
    throw "ADB device is not ready: $deviceState"
}

$androidId = (& $adbPath -s $address shell settings get secure android_id 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($androidId)) {
    throw "Failed to read Android ID: $androidId"
}

$addressPattern = '("address"\s*:\s*")[^"]+("\s*)'
$utf8NoBom = [Text.UTF8Encoding]::new($false)
foreach ($configPath in $configPaths) {
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Config not found: $configPath"
    }
    $raw = [IO.File]::ReadAllText($configPath)
    $updated = [regex]::Replace(
        $raw,
        $addressPattern,
        { param($match) $match.Groups[1].Value + $address + $match.Groups[2].Value },
        1
    )
    if ($updated -eq $raw -and $raw -notmatch [regex]::Escape($address)) {
        throw "ADB address field was not found in: $configPath"
    }
    [IO.File]::WriteAllText($configPath, $updated, $utf8NoBom)
    Write-Host "Updated: $configPath" -ForegroundColor Green
}

Write-Host "Connected. Android ID: $androidId" -ForegroundColor Green
Write-Host 'If VS Code is already open, reload its window before using the screenshot tool.'
