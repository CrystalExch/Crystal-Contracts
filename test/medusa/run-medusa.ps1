param(
    [switch]$Background,
    [string]$Image = "crystal-medusa-foundry:latest",
    [string]$Config = "medusa.json",
    [string]$LogDir = "logs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$log = Join-Path $repo "$LogDir\medusa-$stamp.log"
$container = "crystal-medusa-$stamp"
$dockerArgs = @(
    "run", "--rm",
    "--name", $container,
    "-v", "${repo}:/src",
    "-w", "/src",
    $Image,
    "sh", "-lc", "medusa fuzz --config $Config"
)

if ($Background) {
    $argLiteral = ($dockerArgs | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ","
    $inner = @"
Set-Location '$($repo -replace "'", "''")'
& docker @($argLiteral) *>&1 | Tee-Object -FilePath '$($log -replace "'", "''")'
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))
    Start-Process powershell -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encoded)
    Write-Host "Started Medusa in background."
    Write-Host "Container: $container"
    Write-Host "Log: $log"
    return
}

Write-Host "Starting Medusa."
Write-Host "Container: $container"
Write-Host "Log: $log"
& docker @dockerArgs *>&1 | Tee-Object -FilePath $log
exit $LASTEXITCODE
