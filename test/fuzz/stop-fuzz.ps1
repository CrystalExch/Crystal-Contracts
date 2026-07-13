Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$containers = docker ps --format "{{.Names}}" | Where-Object {
    $_ -like "crystal-medusa-*" -or $_ -like "crystal-echidna-*"
}

if (-not $containers) {
    Write-Host "No Crystal fuzz containers are running."
    return
}

foreach ($container in $containers) {
    Write-Host "Stopping $container"
    docker stop $container | Out-Null
}

Write-Host "Stopped fuzz containers."
