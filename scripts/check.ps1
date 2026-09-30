<#
.SYNOPSIS
    Checks the prerequisites for running Libratory. Changes nothing.

.PARAMETER Offline
    Skip the check that downloads the official install file from ghcr.io.
#>
[CmdletBinding()]
param(
    [switch]$Offline
)

. (Join-Path $PSScriptRoot '_common.ps1')

$failures = 0
function Add-Failure([string]$Message) { Write-Fail $Message; $script:failures++ }

Write-Step 'Environment'
if ($OnWindows) {
    Write-Ok "Windows detected ($([Environment]::OSVersion.VersionString))."
} else {
    Write-Warn 'This is not Windows. The scripts should still work, but this repo targets Windows + Docker Desktop.'
}
Write-Ok "PowerShell $($PSVersionTable.PSVersion)."

if ($OnWindows) {
    if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
        Write-Ok 'WSL is available.'
    } else {
        Write-Warn 'wsl.exe was not found. Docker Desktop needs WSL2; its installer can set it up.'
    }
    $drive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue
    if ($drive -and $drive.Free) {
        $freeGb = [math]::Round($drive.Free / 1GB, 1)
        if ($freeGb -lt 15) {
            Write-Warn "Only $freeGb GB free on $($env:SystemDrive). Images, voices and models need several GB."
        } else {
            Write-Ok "$freeGb GB free on $($env:SystemDrive)."
        }
    }
}

Write-Step 'Docker'
$dockerReady = $false
if (-not (Test-DockerCli)) {
    Write-DockerMissingHelp
    $failures++
} else {
    Write-Ok "docker command found: $((Get-Command docker).Source)"

    $composeVersion = Invoke-DockerCapture compose version --short
    if ($composeVersion.ExitCode -eq 0) {
        Write-Ok "docker compose available (version $(($composeVersion.Output -join '').Trim()))."
    } else {
        Add-Failure '"docker compose" is not available. Update Docker Desktop.'
    }

    if ($OnWindows -and -not (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)) {
        Write-Warn 'The Docker Desktop application does not appear to be running.'
    }

    $engineError = Get-DockerEngineError
    if ($engineError) {
        Write-DockerNotRunningHelp $engineError
        $failures++
    } else {
        $info = Invoke-DockerCapture info --format '{{.ServerVersion}}|{{.OSType}}|{{.OperatingSystem}}|{{.KernelVersion}}'
        $parts = (($info.Output -join '').Trim()) -split '\|'
        Write-Ok "Docker engine reachable (server $($parts[0]), $($parts[2]))."
        if ($parts[1] -ne 'linux') {
            Add-Failure "Docker is in '$($parts[1])' container mode. Switch Docker Desktop to Linux containers."
        } else {
            Write-Ok 'Linux containers mode.'
            $dockerReady = $true
        }
        if ($OnWindows) {
            if ($parts[3] -match 'WSL2') { Write-Ok 'Docker Desktop uses the WSL2 backend.' }
            else { Write-Warn "Could not confirm the WSL2 backend (kernel: $($parts[3]))." }
        }
    }

    if ($dockerReady -and -not $Offline) {
        $cfg = Invoke-DockerCapture (@('compose', '-p', $ProjectName, '-f', $ComposeSource, 'config', '--quiet'))
        if ($cfg.ExitCode -eq 0) {
            Write-Ok "Official install file is reachable ($ComposeSource)."
        } else {
            Add-Failure "Could not read the official install file $ComposeSource."
            Write-Hint 'Needs internet access to ghcr.io and a Docker Compose version that supports oci:// files.'
            Write-Hint ("Docker said: " + (($cfg.Output | Select-Object -Last 3) -join ' '))
        }
    }
}

Write-Step 'Libratory'
$app = $null
if ($dockerReady) {
    $containers = @(Get-LibratoryContainers)
    $app = $containers | Where-Object { $_.Service -eq 'app' } | Select-Object -First 1
    if ($containers.Count -eq 0) {
        Write-Ok 'Libratory is not installed yet (start.ps1 will install it).'
    } else {
        Write-ContainerTable $containers
    }
}

$listener = Get-PortListener
$appRunning = ($app -and $app.State -eq 'running')
if (-not $listener) {
    if ($appRunning) { Write-Warn "Libratory's container runs, but nothing listens on port $LibratoryPort yet." }
    else { Write-Ok "Port $LibratoryPort is free." }
} elseif ($appRunning) {
    Write-Ok "Port $LibratoryPort is held by Libratory (via Docker)."
} elseif (Test-IsDockerListener $listener) {
    Write-Warn "Port $LibratoryPort is held by Docker ($listener), but not by Libratory. Another container may use it."
} else {
    Add-Failure "Port $LibratoryPort is already used by: $listener. Libratory cannot start until it is freed."
}

if ($appRunning) {
    if (Test-LibratoryHealth) { Write-Ok "Libratory is running and responding: $LibratoryUrl" }
    else { Write-Warn 'Libratory is running but not responding yet (it may still be starting).' }
}

Write-Host ''
if ($failures -gt 0) {
    Write-Fail "$failures problem(s) found. Fix the items marked [FAIL] above, then run this check again."
    exit 1
}
Write-Ok 'Ready to start Libratory. Run:  .\scripts\start.ps1'
exit 0
