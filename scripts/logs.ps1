<#
.SYNOPSIS
    Shows and follows the Libratory logs. Press Ctrl+C to exit; Libratory keeps running.

.PARAMETER Service
    Which part to show: "app" (Libratory itself), "postgres" (database), or "all" (default).

.PARAMETER Tail
    How many recent lines to show first. Default 200.

.PARAMETER NoFollow
    Print the recent lines and exit instead of following new output.
#>
[CmdletBinding()]
param(
    [ValidateSet('all', 'app', 'postgres')]
    [string]$Service = 'all',
    [int]$Tail = 200,
    [switch]$NoFollow
)

. (Join-Path $PSScriptRoot '_common.ps1')

if (-not (Assert-DockerReady)) { exit 1 }

if (@(Get-LibratoryContainers).Count -eq 0) {
    Write-Warn 'No Libratory containers exist yet, so there are no logs.'
    Write-Hint 'Start it with:  .\scripts\start.ps1'
    exit 1
}

$cmd = (Get-ComposeProjectArgs) + @('logs', '--tail', "$Tail")
if (-not $NoFollow) {
    $cmd += '--follow'
    Write-Hint 'Following logs. Press Ctrl+C to exit (Libratory keeps running).'
}
if ($Service -ne 'all') { $cmd += $Service }

& docker @cmd
