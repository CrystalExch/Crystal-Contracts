param(
    [switch]$Background,
    [string]$Image = "ghcr.io/crytic/echidna/echidna:latest",
    [string]$Config = "echidna.yaml",
    [string]$Contract = "CryticTester",
    [string]$LogDir = "logs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$log = Join-Path $repo "$LogDir\echidna-$stamp.log"
$container = "crystal-echidna-$stamp"
$cmd = "echidna . --contract $Contract --config $Config"
$dockerArgs = @(
    "run", "--rm",
    "--name", $container,
    "-v", "${repo}:/src",
    "-w", "/src",
    $Image,
    "bash", "-lc", $cmd
)

if ($Background) {
    $argLiteral = ($dockerArgs | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ","
    $inner = @"
Set-Location '$($repo -replace "'", "''")'
& docker @($argLiteral) *>&1 | Tee-Object -FilePath '$($log -replace "'", "''")'
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))
    Start-Process powershell -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encoded)
    Write-Host "Started Echidna in background."
    Write-Host "Container: $container"
    Write-Host "Log: $log"
    return
}

Write-Host "Starting Echidna."
Write-Host "Container: $container"
Write-Host "Log: $log"
& docker @dockerArgs *>&1 | Tee-Object -FilePath $log
exit $LASTEXITCODE
