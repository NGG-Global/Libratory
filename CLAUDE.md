# CLAUDE.md

## What this repository is

A small management layer for a **local** Libratory deployment on the owner's Windows PC (Docker Desktop + WSL2). It contains PowerShell scripts and documentation only.

**Libratory itself is an upstream dependency**, not code maintained here: https://github.com/subev/libratory. Do not clone, vendor, fork, or patch its source into this repo, and do not recreate its deployment by hand.

## How the deployment works (verified against upstream, 2026-09)

- Official install/update command: `docker compose -f oci://ghcr.io/subev/libratory-compose up -d --pull always`. The OCI artifact is upstream's `deploy/compose.yaml` published with image digests pinned.
- Every script uses the project name `libratory` (it matches `name:` in the upstream file).
- Services: `postgres` (pgvector/pgvector:pg17) and `app` (ghcr.io/subev/libratory:latest).
- Port: `127.0.0.1:3034:3034`. It is loopback-only by upstream design because Libratory has no login.
- Health endpoint: `GET /health` returns `{"ok":true,...}`. The image's own HEALTHCHECK uses it.
- Volumes: `libratory_pgdata17` (database), `libratory_data` (library files, audio, `/data/.env` with keys entered in the UI), `libratory_models` (re-downloadable models).

**Before changing any Docker behavior**, re-read upstream's README (sections "Quick start" and "Docker: volumes, ports, and exposing it beyond localhost") and `deploy/compose.yaml`. Prefer the official instructions over local inventions.

## Script layout

- `scripts/_common.ps1`: shared settings and helpers, dot-sourced by every script.
- `start.ps1`: `docker compose -p libratory start` if containers already exist (offline, no upgrade). Otherwise it runs the official `up` command. It then waits for `/health`.
- `update.ps1`: the official `up -d --pull always` command, then a health wait and status.
- `stop.ps1`: `docker compose -p libratory stop`. Containers and volumes are kept.
- `status.ps1`, `logs.ps1`, `check.ps1`: read-only.

Project-name-only compose calls (`-p libratory` without `-f`) are used where the install file is not needed, so they work offline.

## Rules

- **Never delete Docker volumes or run destructive cleanup** without explicit approval from the user in the current conversation. That includes `docker compose down -v`, `docker volume rm/prune`, `docker system prune`, and removing containers in a way that drops volumes. Do not add such commands to scripts.
- **Keep networking localhost-only.** Do not publish 3034 on `0.0.0.0`, add ports, or add reverse proxies, Tailscale, auth, domains, or cloud deployment unless the user explicitly asks.
- **Never commit secrets or runtime data**: `.env` files, API keys, books (PDF/EPUB), audio (M4B/MP3/WAV), models, database dumps, logs. Check `git status` before committing. Do not add cloud-provider credentials to this repo; those are configured in Libratory's UI.
- **Keep scripts Windows/PowerShell friendly:**
  - They must run on Windows PowerShell 5.1 and PowerShell 7+. Avoid `??`, ternaries, `&&`/`||` and `$IsWindows`; use `$env:OS -eq 'Windows_NT'`.
  - Keep `.ps1` files ASCII-only, because 5.1 reads BOM-less files as ANSI. `.gitattributes` checks them out with CRLF.
  - Capture docker output through `Invoke-DockerCapture`. It stops stderr from becoming PowerShell errors, and it uses `$args` so flags like `-a` are not bound as PowerShell parameters.
  - Avoid embedded double quotes in native arguments (5.1 mangles them). Parse `docker inspect` JSON instead of using Go templates that need quotes.
  - Failure messages should tell a non-Docker-expert what to do next.
- Keep the repo small. Add files only with a clear reason.

## Verifying changes

- Parse every script: `[System.Management.Automation.Language.Parser]::ParseFile(...)` via `pwsh`, or run PSScriptAnalyzer (its Write-Host warnings are expected).
- Run `.\scripts\check.ps1` and `.\scripts\status.ps1`. They are safe and change nothing.
