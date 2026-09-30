<#
.SYNOPSIS
    Starts Libratory (official Docker deployment) on http://localhost:3034.

.DESCRIPTION
    - If Libratory has been installed before, starts the existing containers as they are
      (works offline, does not upgrade anything).
    - On first run (no containers yet), installs Libratory with the official upstream command.
    Use update.ps1 to move to the latest release. Data in the Docker volumes is never touched.

.PARAMETER NoWait
    Return as soon as the containers are started instead of waiting for Libratory to respond.

.PARAMETER TimeoutSec
    How long to wait for Libratory to respond. Default 900 seconds (the first start downloads
    the Docker images and the default voice).
#>
[CmdletBinding()]
param(
    [switch]$NoWait,
    [int]$TimeoutSec = 900
)

. (Join-Path $PSScriptRoot '_common.ps1')

Write-Step 'Checking Docker'
if (-not (Assert-DockerReady)) { exit 1 }
Write-Ok 'Docker is running.'

$containers = @(Get-LibratoryContainers)
$app = $containers | Where-Object { $_.Service -eq 'app' } | Select-Object -First 1

if ($app -and $app.State -eq 'running' -and (Test-LibratoryHealth)) {
    Write-Ok 'Libratory is already running.'
    Write-Host ''
    Write-Host "Open: $LibratoryUrl" -ForegroundColor Green
    exit 0
}

# Only complain about port 3034 if it is not Libratory/Docker itself holding it.
if (-not ($app -and $app.State -eq 'running')) {
    $listener = Get-PortListener
    if ($listener -and -not (Test-IsDockerListener $listener)) {
        Write-Fail "Port $LibratoryPort is already in use by: $listener"
        Write-Hint 'Libratory needs this port. Close that program (or stop that service) and try again.'
        exit 1
    }
}

if ($containers.Count -gt 0 -and $app) {
    Write-Step 'Starting the existing Libratory containers'
    $cmd = (Get-ComposeProjectArgs) + @('start')
} else {
    Write-Step 'First start: installing Libratory from the official deployment'
    Write-Hint 'This downloads the Docker images (a few GB). It can take a while.'
    $cmd = (Get-ComposeFileArgs) + @('up', '-d', '--pull', 'always')
}

& docker @cmd
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Docker could not start Libratory (exit code $LASTEXITCODE). See the messages above."
    Write-Hint 'If this is the first start, check your internet connection and run:  .\scripts\check.ps1'
    exit 1
}

if ($NoWait) {
    Write-Ok 'Containers started. Libratory may need a few moments before it responds.'
    Write-Host ''
    Write-Host "Open: $LibratoryUrl" -ForegroundColor Green
    exit 0
}

Write-Step 'Waiting for Libratory to respond (Ctrl+C stops waiting; Libratory keeps running)'
if (Wait-LibratoryHealthy $TimeoutSec) {
    Write-Ok 'Libratory is up.'
    Write-Host ''
    Write-Host "Open: $LibratoryUrl" -ForegroundColor Green
    Write-Hint 'Libratory keeps running in the background after you close this window.'
    Write-Hint 'Stop it with:  .\scripts\stop.ps1'
    exit 0
}

Write-Warn "Libratory did not respond within $TimeoutSec seconds."
Write-Hint 'It may still be downloading on first start. Check progress with:  .\scripts\logs.ps1'
Write-Hint "Then check again with:  .\scripts\status.ps1   (URL: $LibratoryUrl)"
exit 1
