<#
.SYNOPSIS
    Stops Libratory. Keeps all data.

.DESCRIPTION
    Stops the Libratory containers ("docker compose stop"). The containers and all Docker
    volumes (database, library files, audio, models, settings) are kept, so the next
    start.ps1 continues exactly where you left off.
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot '_common.ps1')

if (-not (Assert-DockerReady)) { exit 1 }

$running = @(Get-LibratoryContainers | Where-Object { $_.State -eq 'running' })
if ($running.Count -eq 0) {
    Write-Ok 'Libratory is not running. Nothing to stop.'
    exit 0
}

Write-Step 'Stopping Libratory (data is kept)'
& docker @((Get-ComposeProjectArgs) + @('stop'))
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Docker reported an error while stopping (exit code $LASTEXITCODE). See above."
    exit 1
}

Write-Ok 'Libratory is stopped. Your books, audio, models and settings are kept.'
Write-Hint 'Start it again with:  .\scripts\start.ps1'
