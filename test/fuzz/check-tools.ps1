Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repo

function Require-Docker {
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if (-not $docker) {
        throw "Docker is not installed or is not on PATH."
    }

    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    docker info *> $null
    $dockerReady = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $oldPreference
    if (-not $dockerReady) {
        $dockerDesktop = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
        if (Test-Path -LiteralPath $dockerDesktop) {
            Start-Process -FilePath $dockerDesktop -WindowStyle Hidden
        }

        $ready = $false
        for ($i = 0; $i -lt 60; $i++) {
            $ErrorActionPreference = "Continue"
            docker info *> $null
            $dockerReady = ($LASTEXITCODE -eq 0)
            $ErrorActionPreference = $oldPreference
            if ($dockerReady) {
                $ready = $true
                break
            }
            Start-Sleep -Seconds 5
        }
        if (-not $ready) {
            throw "Docker engine did not become ready within 5 minutes."
        }
    }
}

Require-Docker

Write-Host "Docker:"
docker version --format '{{.Server.Version}}'

Write-Host "`nPulling/refreshing fuzzing images..."
docker pull ghcr.io/crytic/echidna/echidna:latest
docker pull ghcr.io/crytic/medusa:latest

Write-Host "`nBuilding local Medusa image with Foundry..."
docker build -f test/medusa/Dockerfile.medusa -t crystal-medusa-foundry:latest .

Write-Host "`nEchidna image:"
docker run --rm -v "${repo}:/src" -w /src ghcr.io/crytic/echidna/echidna:latest bash -lc "echidna --version && crytic-compile --version && forge --version"

Write-Host "`nMedusa image:"
docker run --rm -v "${repo}:/src" -w /src crystal-medusa-foundry:latest sh -lc "medusa --version && crytic-compile --version && forge --version"

Write-Host "`nFuzzing tools are ready."
