# Neon Hub on Windows

A static `docker-compose.yml` plus a one-shot `installer.ps1` that stand
up the Neon Hub container stack on Windows 10/11 with **Docker Desktop +
WSL2** — no Ansible, no Linux VM. Secrets are generated per-host;
nothing in `windows/seed/` is a real credential.

## Quick install

From an **Administrator PowerShell** in this directory, after installing
the prerequisites below:

```powershell
.\installer.ps1
```

That walks every step in order — hosts file, cert, data tree, .env,
Python venv, secret generation, `docker compose up`, user seeding,
admin-token bootstrap — and prompts for the Hub admin username and
password. Each step is idempotent, so re-running picks up where a
prior run left off.

Useful flags:

  - `-TrustCert` — import the self-signed cert into LocalMachine\Root
    so browsers don't warn.
  - `-EnableMdns` — register the LAN mDNS publisher so other devices on
    your network can reach `hana.<hostname>` etc. without each one
    needing its own hosts-file entry.
  - `-RotateSecrets` — mint fresh per-host secrets. Pair with
    `docker compose down -v` first if the stack has already initialised
    RabbitMQ's user database.
  - `-NonInteractive` — fail instead of prompting; useful for CI or
    scripted reinstalls. Requires `-AdminUsername` + `-AdminPassword`.

After it finishes, `https://hana.<hostname>/docs` (default
`neon-hub-win.local`) should serve the HANA OpenAPI page.

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
6. **Shawl.** A small Rust service-wrapper used so the Python mDNS
   publisher runs as a real Windows service. Install with:
   ```powershell
   winget install -e --id mtkennerly.shawl
   ```
7. **Python 3.10+.** Used by the LAN mDNS publisher
   (`mdns-publisher.py`) and the per-host secrets renderer
   (`generate-secrets.py`). The Hub install creates and manages its
   own venv under `${NEON_HOME}\venv` so dependencies don't pollute
   the system Python; see "Set up the Hub venv" below.
   ```powershell
   winget install -e --id Python.Python.3.12
   ```

## Manual install (reference)

These are the same steps `installer.ps1` walks, broken out for the
case where you want to skip some, integrate with an existing install,
or debug a failing step. Run each from an Administrator PowerShell.

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
you set `NEON_HOME`). Create it and drop the static seed files (no secrets)
into place:

```powershell
$NEON_HOME = "$env:USERPROFILE\neon-hub"
New-Item -ItemType Directory -Force -Path `
  "$NEON_HOME\compose",
  "$NEON_HOME\xdg\config\neon",
  "$NEON_HOME\xdg\config\rabbitmq",
  "$NEON_HOME\xdg\local\share\neon\users-service",
  "$NEON_HOME\xdg\share\neon" | Out-Null

Copy-Item windows\seed\rabbitmq.conf     "$NEON_HOME\xdg\config\rabbitmq\"
Copy-Item windows\seed\enabled_plugins   "$NEON_HOME\xdg\config\rabbitmq\"
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
accept backslashes in bind mounts). The Python venv and rendered configs
both key off this value, so it has to land before the next step.

### 5. Set up the Hub venv

Create an isolated Python venv under `${NEON_HOME}\venv` and install the
Hub's pip dependencies (`zeroconf`, `jinja2`, `PyYAML`):

```powershell
.\windows\scripts\setup-python.ps1
```

Idempotent — re-runs upgrade existing packages.

### 6. Render Hub config templates

Generate per-host service-user passwords + HANA token secrets and render
`rabbitmq.json`, `diana.yaml`, and `neon.yaml` from the Jinja2 templates
the Linux/macOS install uses:

```powershell
.\windows\scripts\generate-secrets.ps1 -Hostname neon-hub-win.local
```

Writes the secrets to `$NEON_HOME\neon_hub_secrets.yaml` and the rendered
configs under `$NEON_HOME\xdg\config\`. Idempotent — re-runs reuse the
existing secrets file. Pass `-Rotate` to mint fresh credentials, but
note that RabbitMQ persists its user database in a Docker volume on
first start, so rotating after `docker compose up` requires
`docker compose down -v` first.

### 7. Bring up the container stack

```powershell
docker compose -p neon -f windows\docker-compose.yml up -d
docker compose -p neon -f windows\docker-compose.yml ps
docker compose -p neon -f windows\docker-compose.yml logs -f rabbitmq hana
```

Expected: all containers report `running`, `neon-rabbitmq` reaches `Server
startup complete`. `neon-hub-config` will crash-loop until step 9 lands.

### 8. Seed initial users

The users-service container starts with an empty SQLite DB. HANA's
`/auth/register` only creates default-permission users (no admin-promotion
path), so the installer writes the initial rows directly, matching what
the Linux/macOS install does via
`debos/overlays/ansible/seed-hana-users.yaml`.

```powershell
.\windows\scripts\seed-users.ps1
```

Prompts for the Hub admin username + password. Also seeds `neon_node`
with the password from the rendered `diana.yaml` so a Neon Node client
can log in against HANA out of the box. The script stops `users-service`
while writing (so the DB file isn't locked) and restarts it before
exiting. Re-runnable — existing rows are updated, not duplicated.

### 9. Bootstrap the Hub admin token

`neon-hub-config` is enabled in the compose stack but starts in a
crash-loop until it finds a valid `hub_admin.yaml`. This script
authenticates as the admin user you just seeded, captures a refresh
token, writes the file, and bumps `hub_config` so it picks the token
up immediately.

```powershell
.\windows\scripts\bootstrap-hub-admin.ps1
```

Idempotent. Re-run if `hub_config` ever starts failing its HANA auth
(refresh tokens have a finite TTL set in `diana.yaml`'s
`refresh_token_ttl`). After this lands,
`https://config.neon-hub-win.local/` should serve the Hub Config UI.

### 10. (Optional) Advertise the Hub on the LAN

Install a Windows service that publishes the Hub's `_neon-hub._tcp.local.`
service record AND the A records for `hana.<hostname>` and the other Hub
subdomains. Other LAN clients can then reach
`https://hana.neon-hub-win.local/` (and friends) without their own
hosts-file edits.

```powershell
.\windows\scripts\register-mdns.ps1 -Hostname neon-hub-win.local
```

The service is wrapped in Shawl and runs `mdns-publisher.py`, which uses
`python-zeroconf` to speak mDNS directly over UDP 5353. Skip if you only
need single-machine access.

**Why not Bonjour or Microsoft's native mDNS?** Apple's Bonjour-for-Windows
`dns-sd -P` returns -65563 (`DNSServiceCreateConnection` isn't implemented
in the Windows port). Microsoft's built-in `DnsServiceRegister` registers
the service envelope but silently drops the A record (Win10/11 bug still
present on 26100). python-zeroconf bypasses both. `install-bonjour.ps1`
is still in the repo as an optional install of Apple's `dns-sd` CLI for
diagnostics; the publisher itself no longer depends on it.

## Tear down

```powershell
docker compose -p neon -f windows\docker-compose.yml down
```

To wipe the data directory too:

```powershell
docker compose -p neon -f windows\docker-compose.yml down -v
Remove-Item -Recurse -Force $env:USERPROFILE\neon-hub
```

## What's intentionally missing

- **`docker_manager` container.** Mounts `/var/run/docker.sock`, which
  Docker Desktop on Windows doesn't expose. Likely permanently disabled
  on Windows.
- **One-shot orchestrator.** Today the install is run-each-script-in-order;
  on the roadmap is a single `installer.ps1` that wraps the hosts-file
  edit, cert generation, data tree, venv setup, secrets, .env, compose
  up, seed-users, bootstrap-hub-admin, and register-mdns into one
  command.

## Troubleshooting

**`docker compose up` says "no such file or directory" for one of the seed
mounts.** You skipped step 3 or set `NEON_HOME` to a path Docker Desktop
isn't sharing. Confirm under Settings → Resources → File Sharing — your home
directory should be on the default-shared list.

**RabbitMQ crashes immediately with `failed_to_update_enabled_plugins_file`.**
The Darwin-style workaround should prevent this, but if you see it: check
that `RABBITMQ_ENABLED_PLUGINS_FILE=/var/lib/rabbitmq/enabled_plugins` is
in the container's env (`docker inspect neon-rabbitmq | grep RABBIT`).

**Nginx 502 errors after restart.** Same upstream-caching issue the Mac
install hits. `docker restart neon-nginx` after the dependent service
restarts. A future `resolver` directive in `nginx.conf` will address it
permanently.

**Browser shows cert warning.** Either trust the cert per step 2, or click
through. The cert is locally-generated and self-signed; that's expected.
