# Neon Hub on Windows — Phase 1 (compose only)

> **DEV-ONLY.** Every credential in this directory is a hardcoded placeholder
> checked into the public repo. Do not expose this stack to anything but
> `localhost` until Phase 2 lands and replaces these with generated secrets.

This directory provides a static `docker-compose.yml` and seed configs so you
can stand up the Neon Hub container stack on Windows 10/11 with **Docker
Desktop + WSL2** — no installer, no Ansible, no PowerShell. The point is to
prove out the container layer end-to-end before we build a real installer.

## Prerequisites

1. **Windows 10 21H2+ or Windows 11**, with hardware virtualization enabled
   in BIOS/UEFI.
2. **WSL2** installed: open PowerShell as Administrator and run
   `wsl --install`. Reboot when prompted.
3. **Docker Desktop** ≥ 4.x, with the **WSL2 backend** enabled
   (Settings → General → "Use the WSL 2 based engine"). Verify with:

   ```powershell
   docker version
   docker compose version
   ```

4. **A text editor that can write Unix line endings** (VS Code, Notepad++,
   anything but the default Notepad). The seed configs are LF-terminated;
   editing them with Notepad will silently break the containers.
5. **OpenSSL.** Used by `windows\scripts\new-cert.ps1` to generate the
   Hub's TLS cert. The script will find `openssl.exe` whether or not
   it's on PATH, as long as you installed to a standard location.
   Easiest install paths:
   - `winget install FireDaemon.OpenSSL` — *adds itself to PATH by default*
   - `winget install ShiningLight.OpenSSL.Light` — installer's "Add to PATH"
     checkbox is unchecked by default; the script finds it under
     `C:\Program Files\OpenSSL-Win64\bin\` regardless
   - [Git for Windows](https://gitforwindows.org/) — bundles `openssl.exe`
     under `C:\Program Files\Git\usr\bin\`; reachable from Git Bash but
     not PowerShell unless you add the dir to PATH. The script finds
     it either way.

## One-time setup

### 1. Add the hostname to your hosts file

The stack uses TLS for `neon-hub-win.local`. Windows' built-in mDNS only
resolves `.local` as a client (not as a publisher), so the simplest path
is a hosts-file entry.

Open `C:\Windows\System32\drivers\etc\hosts` in an editor running **as
Administrator** and add:

```
127.0.0.1   neon-hub-win.local config.neon-hub-win.local hana.neon-hub-win.local iris.neon-hub-win.local iris-websat.neon-hub-win.local coqui.neon-hub-win.local fasterwhisper.neon-hub-win.local rmq-admin.neon-hub-win.local skill-config.neon-hub-win.local
```

(One long line. Subdomain explosion is because nginx routes by Host header.)

### 2. Generate a self-signed TLS cert

```powershell
.\windows\scripts\new-cert.ps1 `
  -Hostname neon-hub-win.local `
  -OutDir   $env:USERPROFILE\neon-hub
```

That writes `neon-hub-win.local.crt` and `neon-hub-win.local.key` directly
into your data dir. The SAN covers the hostname, `localhost`, and
`127.0.0.1`, so the same cert works for every access pattern a local Hub
sees.

If you want to suppress the browser warning, trust the freshly-minted cert
from an Administrator PowerShell:

```powershell
Import-Certificate `
  -FilePath        $env:USERPROFILE\neon-hub\neon-hub-win.local.crt `
  -CertStoreLocation Cert:\LocalMachine\Root
```

### 3. Lay down the data directory

The compose file expects a tree under `%USERPROFILE%\neon-hub` (or wherever
you set `NEON_HOME`). Run this once from PowerShell:

```powershell
$NEON_HOME = "$env:USERPROFILE\neon-hub"
New-Item -ItemType Directory -Force -Path `
  "$NEON_HOME\compose",
  "$NEON_HOME\xdg\config\neon",
  "$NEON_HOME\xdg\config\rabbitmq",
  "$NEON_HOME\xdg\local\share\neon\users-service",
  "$NEON_HOME\xdg\share\neon" | Out-Null

# Copy seed configs into place
Copy-Item windows\seed\rabbitmq.conf     "$NEON_HOME\xdg\config\rabbitmq\"
Copy-Item windows\seed\rabbitmq.json     "$NEON_HOME\xdg\config\rabbitmq\"
Copy-Item windows\seed\enabled_plugins   "$NEON_HOME\xdg\config\rabbitmq\"
Copy-Item windows\seed\neon.yaml         "$NEON_HOME\xdg\config\neon\"
Copy-Item windows\seed\diana.yaml        "$NEON_HOME\xdg\config\neon\"
Copy-Item windows\seed\hub_admin.yaml    "$NEON_HOME\xdg\config\neon\"
Copy-Item windows\seed\nginx.conf        "$NEON_HOME\compose\"
Copy-Item windows\seed\skill-config.json "$NEON_HOME\compose\"
Copy-Item windows\seed\neon-logo.png     "$NEON_HOME\compose\"
```

### 4. Create your `.env`

```powershell
Copy-Item windows\.env.example windows\.env
```

Open `windows\.env` and edit `NEON_HOME` to match your username, e.g.
`C:/Users/Mike/neon-hub` (forward slashes only — Docker Desktop does not
accept backslashes in bind mounts).

## Run it

```powershell
docker compose -p neon -f windows\docker-compose.yml up -d
docker compose -p neon -f windows\docker-compose.yml ps
docker compose -p neon -f windows\docker-compose.yml logs -f rabbitmq hana
```

Expected: all containers report `running`, `neon-rabbitmq` reaches `Server
startup complete`, `neon-hana` serves `https://hana.neon-hub-win.local/docs`
in the browser.

To tear down:

```powershell
docker compose -p neon -f windows\docker-compose.yml down
```

To wipe the data directory too:

```powershell
docker compose -p neon -f windows\docker-compose.yml down -v
Remove-Item -Recurse -Force $env:USERPROFILE\neon-hub
```

## What's intentionally missing in Phase 1

- **`hub_config` container.** Needs a valid `hub_admin.yaml` with a refresh
  token from HANA. Bootstrapping that is a Phase 2 problem (PowerShell
  script that POSTs to `/auth/login` and writes the file). It's commented
  out in the compose with a TODO.
- **`docker_manager` container.** Mounts `/var/run/docker.sock`, which
  doesn't exist on Windows. Will likely stay disabled on Windows.
- **mDNS advertising.** The hosts-file workaround means only this machine
  resolves `neon-hub-win.local`. Phase 2 will document installing Bonjour
  Print Services so other devices on the LAN (phones, Node app) can find
  the Hub.
- **Password rotation.** Everything in `seed/` is a static dev placeholder.
  Phase 2 PowerShell installer will generate fresh values per host. (The
  TLS cert is already per-host as of Phase 2.1 — see step 2.)

## Troubleshooting

**`docker compose up` says "no such file or directory" for one of the seed
mounts.** You skipped step 3 or set `NEON_HOME` to a path Docker Desktop
isn't sharing. Confirm under Settings → Resources → File Sharing — your home
directory should be on the default-shared list.

**RabbitMQ crashes immediately with `failed_to_update_enabled_plugins_file`.**
The Darwin-style workaround should prevent this, but if you see it: check
that `RABBITMQ_ENABLED_PLUGINS_FILE=/var/lib/rabbitmq/enabled_plugins` is
in the container's env (`docker inspect neon-rabbitmq | grep RABBIT`).

**Nginx 502 errors after restart.** Same upstream-caching issue we hit on
the Mac path. `docker restart neon-nginx` after the dependent service
restarts. Will be addressed via a `resolver` directive in Phase 2's
`nginx.conf.j2`.

**Browser shows cert warning.** Either trust the cert per step 2, or click
through. The cert is locally-generated and self-signed; that's expected.
