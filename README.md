# Libratory – local management scripts

This repository holds a few PowerShell scripts for running [Libratory](https://github.com/subev/libratory) (a local PDF-to-audiobook workbench) on a Windows PC using its **official Docker deployment**.

**GitHub stores this management project; Libratory itself runs on your own laptop.** Only the scripts and this documentation live in the repository. The application, its database, your books, the generated audio and the downloaded models all stay on the PC, inside Docker volumes, and are never uploaded anywhere.

It does not contain Libratory itself. The scripts wrap the upstream install command:

```
docker compose -f oci://ghcr.io/subev/libratory-compose up -d --pull always
```

They always use the fixed project name `libratory`, so every command addresses the same installation. Libratory is reachable **only from this PC** at http://localhost:3034. Upstream binds the port to `127.0.0.1` because Libratory has no login.

## Prerequisites

- Windows 10/11
- [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/) with the **WSL2** backend (the installer's default), in **Linux containers** mode
- Internet access for the first start and for updates
- Several GB of free disk space for the images and voice models

The scripts do not install Docker for you. `check.ps1` tells you exactly what is missing.

## First-time setup

1. Install Docker Desktop, start it, and wait until it shows **Engine running**.
2. Get this repository onto the PC and open PowerShell in its folder:
   ```powershell
   git clone https://github.com/NGG-Global/Libratory.git
   cd Libratory
   ```
3. Allow local scripts to run (one-time, affects only your user account):
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
   ```
   If you downloaded the repo as a ZIP instead of cloning it, also run `Get-ChildItem .\scripts\*.ps1 | Unblock-File`.
4. Run the prerequisite check:
   ```powershell
   .\scripts\check.ps1
   ```

## Everyday commands

Run these from the repository folder:

| Task | Command |
| --- | --- |
| Start | `.\scripts\start.ps1` |
| Open Libratory | http://localhost:3034 |
| Stop (keeps all data) | `.\scripts\stop.ps1` |
| Update to the latest release | `.\scripts\update.ps1` |
| Is it running? | `.\scripts\status.ps1` |
| Watch the logs (Ctrl+C to exit) | `.\scripts\logs.ps1` |
| Check prerequisites | `.\scripts\check.ps1` |

Useful options: `.\scripts\logs.ps1 -Service app -NoFollow` prints recent app logs and exits. `.\scripts\start.ps1 -NoWait` returns without waiting for Libratory to respond.

**What start and update do:**

- `start.ps1` starts the existing installation as it is. It works offline and does not upgrade. On the very first run it installs Libratory using the official command.
- `update.ps1` runs the official command again, which is upstream's documented way to update. It downloads the latest release and recreates the containers. Your data stays in place, and Libratory applies any database migrations on its own when it starts.

## Good to know

- **The first start is slow.** Docker downloads the images (a few GB), and on its first boot Libratory downloads its default Kokoro voice (about 350 MB). Additional voices and models download the first time you use them. Later starts take seconds. `start.ps1` waits up to 15 minutes and reports progress.
- **Closing PowerShell does not stop Libratory.** It runs in the background inside Docker until you run `stop.ps1` or quit Docker Desktop. If Libratory was running when Docker Desktop quit, it starts again the next time Docker Desktop starts. After `stop.ps1`, it stays stopped.
- **Only this PC can reach it.** If you work from a tablet through remote access, open the browser *inside the remote session on the PC*. The tablet's own browser cannot reach `localhost:3034`. This is intentional.
- **Optional cloud providers** (ElevenLabs, OpenAI, etc.) are configured in Libratory's own ⚙️ Settings page. Nothing in this repository needs API keys.

## Where your data lives

Your data is **not** stored in this folder. It lives in three Docker volumes that Docker Desktop keeps inside its WSL2 disk:

| Volume | Contents | Can it be re-created? |
| --- | --- | --- |
| `libratory_pgdata17` | The database: books, chapters, notes, search index | **No** |
| `libratory_data` | Library files: uploads, generated audio, exports, and API keys entered in Settings (`/data/.env`) | **No** |
| `libratory_models` | Downloaded TTS and other models | Yes, they download again |

Stopping, starting, and updating never touch these volumes.

> ⚠️ **These actions permanently delete your library:**
> - `docker compose down -v` (the `-v` removes the volumes)
> - `docker volume rm ...` / `docker volume prune` / `docker system prune --volumes`
> - Deleting the volumes in Docker Desktop's **Volumes** tab
> - Docker Desktop **Troubleshoot → Clean / Purge data** or **Reset to factory defaults**
> - Uninstalling Docker Desktop, or unregistering its WSL distributions
>
> Removing old *images* (Docker Desktop → Images) is safe and frees space after updates.

## Troubleshooting

**"Docker engine is not reachable" / Docker not running.** Start Docker Desktop from the Start menu and wait for **Engine running** (it can take a minute after login). Then run the script again. If Docker reports Windows containers mode, right-click the Docker tray icon and choose **Switch to Linux containers...**.

**"docker command was not found".** Install Docker Desktop, or open a *new* PowerShell window after installing it so the updated PATH takes effect.

**Port 3034 is in use.** Another program is using the port. `check.ps1` names the program where Windows allows it. Close that program, or run `Get-NetTCPConnection -LocalPort 3034 -State Listen` to find it. The scripts deliberately do not move Libratory to another port.

**First start seems stuck.** It is usually still downloading. Watch progress with `.\scripts\logs.ps1`, and check with `.\scripts\status.ps1`. "Still starting" is normal for several minutes on the first run over a slow connection.

**"Running scripts is disabled on this system".** Repeat step 3 of the first-time setup.

**Anything else.** Run `.\scripts\check.ps1` and `.\scripts\logs.ps1 -Service app -NoFollow`. For Libratory bugs, see the [upstream issue tracker](https://github.com/subev/libratory/issues). Upstream describes the Windows route as new.
