<#
.SYNOPSIS
    Updates Libratory to the latest official release and (re)starts it. Keeps all data.

.DESCRIPTION
    Runs the official upstream install/update command:
        docker compose -f oci://ghcr.io/subev/libratory-compose up -d --pull always
    with the fixed project name "libratory". Compose recreates only the containers whose image
    or configuration changed. Docker volumes are reused, so the library is preserved; database
    migrations are applied by Libratory itself at boot.

    Old image versions stay on disk afterwards. Removing unused images (Docker Desktop >
    Images) frees space and does not touch your library, but never delete volumes.

.PARAMETER TimeoutSec
    How long to wait for Libratory to respond after the update. Default 900 seconds.
#>
[CmdletBinding()]
param(
    [int]$TimeoutSec = 900
)

. (Join-Path $PSScriptRoot '_common.ps1')

Write-Step 'Checking Docker'
if (-not (Assert-DockerReady)) { exit 1 }

$before = Get-AppContainer
$beforeImage = $null
if ($before) { $beforeImage = $before.ImageId }

Write-Step 'Downloading the latest official Libratory release'
& docker @((Get-ComposeFileArgs) + @('up', '-d', '--pull', 'always'))
if ($LASTEXITCODE -ne 0) {
    Write-Fail "The update failed (exit code $LASTEXITCODE). See the messages above."
    Write-Hint 'Your data is untouched. Check your internet connection, then try again.'
    Write-Hint 'If Libratory was running before, it may still be running the old version:  .\scripts\status.ps1'
    exit 1
}

$after = Get-AppContainer
if ($after -and $beforeImage -and $after.ImageId -eq $beforeImage) {
    Write-Ok 'Libratory was already on the latest release.'
} elseif ($after -and $beforeImage) {
    Write-Ok 'Libratory was updated to a new release.'
} else {
    Write-Ok 'Libratory was installed.'
}

Write-Step 'Waiting for Libratory to respond (Ctrl+C stops waiting; Libratory keeps running)'
$healthy = Wait-LibratoryHealthy $TimeoutSec

Write-Step 'Containers'
Write-ContainerTable @(Get-LibratoryContainers)
if ($after) { Write-Hint "App image: $($after.Image)" }

if ($healthy) {
    Write-Ok "Libratory is up at $LibratoryUrl"
    exit 0
}
Write-Warn "Libratory did not respond within $TimeoutSec seconds."
Write-Hint 'See what it is doing with:  .\scripts\logs.ps1'
exit 1
