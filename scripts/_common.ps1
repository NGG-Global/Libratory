# Shared settings and helpers for the Libratory management scripts.
# Dot-sourced by every script in this folder; not meant to be run directly.
#
# Compatible with Windows PowerShell 5.1 and PowerShell 7+. Keep this file ASCII-only:
# Windows PowerShell 5.1 reads BOM-less scripts as ANSI.

# --- Settings ---------------------------------------------------------------------------------

# Official install file, published by upstream beside the image (upstream: deploy/compose.yaml).
$script:ComposeSource = 'oci://ghcr.io/subev/libratory-compose'

# Fixed project name. Matches the "name:" in the upstream install file, so the volumes are
# libratory_pgdata17, libratory_data and libratory_models.
$script:ProjectName = 'libratory'

$script:LibratoryPort = 3034
$script:LibratoryUrl  = 'http://localhost:3034'
# Health endpoint used by the image's own HEALTHCHECK. 127.0.0.1 (not "localhost") because the
# port is published on IPv4 loopback only.
$script:HealthUrl     = 'http://127.0.0.1:3034/health'

$script:OnWindows = ($env:OS -eq 'Windows_NT')

# --- Output helpers ---------------------------------------------------------------------------

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message)   { Write-Host "[ OK ] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Fail([string]$Message) { Write-Host "[FAIL] $Message" -ForegroundColor Red }
function Write-Hint([string]$Message) { Write-Host "       $Message" }

# --- Docker invocation ------------------------------------------------------------------------

# Runs docker and captures its output (stdout and stderr) without letting stderr turn into a
# PowerShell error record. Use for short commands whose output we inspect.
# Deliberately a simple function using $args: a param() block would make PowerShell try to bind
# docker flags such as -a or -q as its own parameters. Array arguments are flattened.
function Invoke-DockerCapture {
    $dockerArgs = @($args | ForEach-Object { $_ })
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & docker @dockerArgs 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    [pscustomobject]@{ ExitCode = $code; Output = @($output) }
}

# Arguments that address the official deployment. Needed for "up", which reads the install file.
function Get-ComposeFileArgs {
    @('compose', '-p', $script:ProjectName, '-f', $script:ComposeSource)
}

# Arguments that address the existing project by name only. Used for start/stop/logs so these
# work offline and never re-read (or re-download) the install file.
function Get-ComposeProjectArgs {
    @('compose', '-p', $script:ProjectName)
}

# --- Prerequisite checks ----------------------------------------------------------------------

function Test-DockerCli {
    [bool](Get-Command docker -ErrorAction SilentlyContinue)
}

function Test-DockerCompose {
    (Invoke-DockerCapture compose version).ExitCode -eq 0
}

# Returns $null when the engine is reachable, otherwise the error text from docker.
function Get-DockerEngineError {
    $r = Invoke-DockerCapture info --format '{{.ServerVersion}}'
    if ($r.ExitCode -eq 0) { return $null }
    ($r.Output -join ' ').Trim()
}

function Get-DockerOsType {
    $r = Invoke-DockerCapture info --format '{{.OSType}}'
    if ($r.ExitCode -ne 0) { return $null }
    ($r.Output -join '').Trim()
}

function Write-DockerMissingHelp {
    Write-Fail 'The "docker" command was not found.'
    Write-Hint 'Libratory runs inside Docker. Install Docker Desktop for Windows (WSL2 backend):'
    Write-Hint '  https://docs.docker.com/desktop/setup/install/windows-install/'
    Write-Hint 'After installing, start Docker Desktop once, then open a NEW PowerShell window.'
}

function Write-DockerNotRunningHelp([string]$Detail) {
    Write-Fail 'Docker is installed, but the Docker engine is not reachable.'
    Write-Hint 'Most likely Docker Desktop is not running (or is still starting up).'
    Write-Hint 'Start "Docker Desktop" from the Start menu and wait until it shows "Engine running",'
    Write-Hint 'then run this script again.'
    if ($Detail) { Write-Hint "Docker said: $Detail" }
}

# Verifies CLI, compose plugin, engine and Linux-container mode. Prints a plain-language
# explanation and returns $false if anything is missing.
function Assert-DockerReady {
    if (-not (Test-DockerCli)) { Write-DockerMissingHelp; return $false }
    if (-not (Test-DockerCompose)) {
        Write-Fail '"docker compose" is not available.'
        Write-Hint 'Update Docker Desktop to a current version; it includes Docker Compose.'
        return $false
    }
    $engineError = Get-DockerEngineError
    if ($engineError) { Write-DockerNotRunningHelp $engineError; return $false }
    $osType = Get-DockerOsType
    if ($osType -and $osType -ne 'linux') {
        Write-Fail "Docker is in '$osType' container mode; Libratory needs Linux containers."
        Write-Hint 'Right-click the Docker whale icon in the taskbar and choose "Switch to Linux containers...".'
        return $false
    }
    return $true
}

# --- Libratory state --------------------------------------------------------------------------

# Returns the containers of the libratory project (running or stopped) as objects with
# Service, Name, State, Health, Image, ImageId.
function Get-LibratoryContainers {
    $ids = Invoke-DockerCapture ps -a -q --filter "label=com.docker.compose.project=$($script:ProjectName)"
    if ($ids.ExitCode -ne 0) { return @() }
    $idList = @($ids.Output | Where-Object { $_ -and $_.Trim() })
    if ($idList.Count -eq 0) { return @() }

    $inspect = Invoke-DockerCapture (@('inspect') + $idList)
    if ($inspect.ExitCode -ne 0) { return @() }
    $parsed = ConvertFrom-Json -InputObject ($inspect.Output -join "`n")

    $result = @()
    foreach ($c in $parsed) {
        $health = ''
        if ($c.State.PSObject.Properties['Health'] -and $c.State.Health) { $health = $c.State.Health.Status }
        $result += [pscustomobject]@{
            Service = $c.Config.Labels.'com.docker.compose.service'
            Name    = $c.Name.TrimStart('/')
            State   = $c.State.Status
            Health  = $health
            Image   = $c.Config.Image
            ImageId = $c.Image
        }
    }
    return $result
}

function Get-AppContainer {
    Get-LibratoryContainers | Where-Object { $_.Service -eq 'app' } | Select-Object -First 1
}

function Write-ContainerTable($Containers) {
    if (-not $Containers -or @($Containers).Count -eq 0) {
        Write-Hint '(no Libratory containers exist yet)'
        return
    }
    foreach ($c in $Containers) {
        # A stopped container keeps its last health result; only show it while running.
        $health = ''
        if ($c.Health -and $c.State -eq 'running') { $health = " ($($c.Health))" }
        Write-Hint ('{0,-9} {1,-22} {2}{3}' -f $c.Service, $c.Name, $c.State, $health)
    }
}

# Returns $true if the health endpoint answers with HTTP 200.
function Test-LibratoryHealth([int]$TimeoutSec = 5) {
    try {
        $response = Invoke-WebRequest -Uri $script:HealthUrl -UseBasicParsing -TimeoutSec $TimeoutSec
        return ($response.StatusCode -eq 200)
    } catch {
        return $false
    }
}

# Polls the health endpoint until it answers or the timeout expires. Stops early if the app
# container exits. Returns $true when healthy.
function Wait-LibratoryHealthy([int]$TimeoutSec = 900) {
    $started  = Get-Date
    $deadline = $started.AddSeconds($TimeoutSec)
    $lastNote = $started
    while ((Get-Date) -lt $deadline) {
        if (Test-LibratoryHealth 3) { return $true }
        $app = Get-AppContainer
        if ($app -and $app.State -in @('exited', 'dead')) {
            Write-Fail "The Libratory app container stopped unexpectedly (state: $($app.State))."
            Write-Hint 'See what happened with:  .\scripts\logs.ps1 -Service app -NoFollow'
            return $false
        }
        if (((Get-Date) - $lastNote).TotalSeconds -ge 30) {
            $elapsed = [int]((Get-Date) - $started).TotalSeconds
            Write-Hint "Still starting... ($elapsed s so far). The first start downloads a voice model; this is normal."
            $lastNote = Get-Date
        }
        Start-Sleep -Seconds 5
    }
    return $false
}

# Describes who is listening on the Libratory port. Returns $null if nothing is.
function Get-PortListener([int]$Port = $script:LibratoryPort) {
    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        $conns = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
        if ($conns.Count -eq 0) { return $null }
        $names = foreach ($conn in $conns) {
            $p = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
            if ($p) { "$($p.ProcessName) (PID $($p.Id), $($conn.LocalAddress))" } else { "PID $($conn.OwningProcess)" }
        }
        return (($names | Select-Object -Unique) -join ', ')
    }
    # Fallback where Get-NetTCPConnection is unavailable: try to connect.
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync('127.0.0.1', $Port)
        if ($task.Wait(1000) -and $client.Connected) { return 'an unknown program' }
        return $null
    } catch {
        return $null
    } finally {
        $client.Dispose()
    }
}

# Docker Desktop's own processes hold published ports on Windows.
function Test-IsDockerListener([string]$Listener) {
    $Listener -match 'com\.docker|wslrelay|vpnkit|docker'
}
