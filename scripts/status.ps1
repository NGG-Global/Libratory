<#
.SYNOPSIS
    Shows whether Libratory is running and responding on http://localhost:3034.
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot '_common.ps1')

if (-not (Assert-DockerReady)) { exit 1 }

$containers = @(Get-LibratoryContainers)
Write-Step 'Containers'
Write-ContainerTable $containers

if ($containers.Count -eq 0) {
    Write-Warn 'Libratory is not installed yet (no containers found).'
    Write-Hint 'Start it with:  .\scripts\start.ps1'
    exit 1
}

$app = $containers | Where-Object { $_.Service -eq 'app' } | Select-Object -First 1
$db  = $containers | Where-Object { $_.Service -eq 'postgres' } | Select-Object -First 1

Write-Step 'Health'
if (-not $app -or $app.State -ne 'running') {
    Write-Warn 'Libratory is stopped.'
    Write-Hint 'Start it with:  .\scripts\start.ps1'
    exit 1
}
if (-not $db -or $db.State -ne 'running') {
    Write-Warn 'The Libratory database container is not running; the app cannot work without it.'
    Write-Hint 'Try:  .\scripts\start.ps1   and if that fails:  .\scripts\logs.ps1 -Service postgres -NoFollow'
}

if (Test-LibratoryHealth) {
    Write-Ok "Libratory is running and responding: $LibratoryUrl"
    exit 0
}

if ($app.Health -eq 'starting') {
    Write-Warn 'Libratory is still starting up (the first start downloads the default voice).'
    Write-Hint 'Wait a minute and run this again, or watch progress with:  .\scripts\logs.ps1'
} else {
    Write-Warn "The app container is running but $HealthUrl does not answer."
    Write-Hint 'Look for errors with:  .\scripts\logs.ps1 -Service app -NoFollow'
}
exit 1
