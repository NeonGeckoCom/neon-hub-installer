# Windows Installation

Neon Hub runs on Windows 11 via Docker Desktop with the WSL2 backend. The Windows install uses a static `docker-compose.yml` plus a PowerShell installer, rather than Ansible. The resulting Hub is functionally close to the Linux and macOS deployments with a handful of platform-specific differences (see [Feature parity](#feature-parity) below).

## Prerequisites

You will need:

- **Windows 11.** Hardware virtualization must be enabled in BIOS/UEFI.
- **WSL2.** From an Administrator PowerShell, run `wsl --install` and reboot when prompted.
- **[Docker Desktop](https://www.docker.com/products/docker-desktop/) 4.x or newer**, with the WSL2 backend enabled (Settings → General → "Use the WSL 2 based engine"). Verify with `docker version` and `docker compose version`.
- **OpenSSL.** Used to generate the Hub's TLS cert. The installer finds `openssl.exe` automatically if it is in a standard location. The easiest install is `winget install FireDaemon.OpenSSL`, which adds itself to PATH by default.
- **[Shawl](https://github.com/mtkennerly/shawl).** A small Rust service wrapper used so the LAN mDNS publisher can run as a real Windows service. Install with `winget install -e --id mtkennerly.shawl`.
- **Python 3.11.** Used by the mDNS publisher and the per-host secrets renderer. The installer creates its own venv so dependencies do not pollute the system Python. Install with `winget install -e --id Python.Python.3.11`.
- **A text editor that writes Unix line endings.** VS Code, Notepad++, or anything other than the default Notepad. The seed config files are LF-terminated and editing them with Notepad will silently break the containers.

The installer must be run from an **Administrator PowerShell** so it can edit the hosts file, register the Windows service, and import the cert into the trust store when requested.

## Install

Clone the repo and run the PowerShell installer from inside the `windows/` directory:

```powershell
git clone https://github.com/NeonGeckoCom/neon-hub-installer
cd neon-hub-installer\windows
.\installer.ps1
```

That kicks off an interactive wizard. Press Enter to accept each default in brackets, or type a new value. It walks every step in order:

1. **Hostname prompt.** Default `neon-hub-win.local`. Used for the TLS cert, nginx server names, and mDNS advertisement.
2. **Cert generation.** Creates a self-signed cert at `%USERPROFILE%\neon-hub\<hostname>.crt`.
3. **Data directory layout.** Creates the tree under `%USERPROFILE%\neon-hub` and copies the seed config files into place.
4. **`.env` rendering.** Writes the per-host `.env` from the template.
5. **Python venv.** Sets up `${NEON_HOME}\venv` and installs the Hub's pip dependencies (`zeroconf`, `jinja2`, `PyYAML`).
6. **Per-host secrets.** Generates service-user passwords and HANA token secrets, then renders `rabbitmq.json`, `diana.yaml`, `neon.yaml`, and `nginx.conf` from the shared Jinja2 templates.
7. **`docker compose up`.** Brings up the container stack.
8. **User seeding.** Writes the admin user and the `neon_node` service user directly into the users-service SQLite DB. HANA's `/auth/register` only creates default-permission users, so this step is the only way to bootstrap an admin.
9. **Hub admin token.** Authenticates as the admin user, captures a refresh token, writes `hub_admin.yaml`, and bumps `hub-config` so it picks up the token.
10. **LAN mDNS registration.** Installs a Shawl-wrapped Windows service that publishes the Hub's `_neon-hub._tcp.local.` service record and the A records for the Hub subdomains.

Each step is idempotent. Rerunning the installer picks up where a prior run left off.

When it finishes, validate the install:

```powershell
Invoke-WebRequest -SkipCertificateCheck https://hana.neon-hub-win.local/docs
```

A 200 confirms HANA is up. The configuration UI is at `https://config.neon-hub-win.local`.

`-SkipCertificateCheck` is needed because the cert is self-signed. Drop the flag once you have imported the cert into the trust store (see [Trusting the self-signed cert](#trusting-the-self-signed-cert)).

### Useful flags

The wizard prompts are skippable by passing arguments on the command line:

- `-AdminUsername` and `-AdminPassword`. Bypass the wizard's admin-credential prompts. Pass the password as a SecureString, for example `(Read-Host -AsSecureString)` or `(ConvertTo-SecureString 'pw' -AsPlainText -Force)`. Avoid passing `-AdminPassword` on the command line in interactive sessions. It is intended for headless or scripted installs only. If you do use it that way, clear your shell history afterward so the password is not left in `ConsoleHost_history.txt`:

  ```powershell
  Clear-History
  Remove-Item (Get-PSReadlineOption).HistorySavePath
  ```

- `-TrustCert`. Import the self-signed cert into `LocalMachine\Root` so browsers do not warn.
- `-NoMdns`. Skip the mDNS publisher service.
- `-AddHostsEntry`. Append a `127.0.0.1` line to the system hosts file. Off by default. Needed only if Windows mDNS cannot reliably resolve `.local` names on your machine.
- `-RotateSecrets`. Mint fresh per-host secrets. Pair with `docker compose down -v` first if the stack has already initialised RabbitMQ's user database.
- `-NonInteractive`. Fail instead of prompting and skip the proceed-confirmation. Required for CI or scripted reinstalls. Requires `-AdminUsername` and `-AdminPassword`.

## Data directory

The Hub stores everything under `%USERPROFILE%\neon-hub`:

- `compose\` holds the rendered nginx config and TLS cert.
- `xdg\` holds Hub configuration, RabbitMQ data, the users-service SQLite DB, and model caches.
- `venv\` is the Python virtualenv used by the installer for mDNS and secret rendering.

The compose file itself (`docker-compose.yml`) lives in the cloned repo under `windows\`, not in the data directory. Compose commands have to point at it explicitly.

This path was chosen because Docker Desktop shares the user's home directory by default. Paths outside it require manual file-sharing setup in Docker Desktop and are not recommended.

## Trusting the self-signed cert

The installer generates a self-signed TLS cert at `%USERPROFILE%\neon-hub\<hostname>.crt`. To stop browsers from warning on every visit, either pass `-TrustCert` to `installer.ps1` or import the cert manually from an Administrator PowerShell:

```powershell
Import-Certificate `
  -FilePath        "$env:USERPROFILE\neon-hub\neon-hub-win.local.crt" `
  -CertStoreLocation Cert:\LocalMachine\Root
```

## Updating

To pull the latest images and restart the stack, run these from the cloned repo root:

```powershell
docker compose -p neon -f windows\docker-compose.yml --env-file windows\.env pull
docker compose -p neon -f windows\docker-compose.yml --env-file windows\.env up -d
```

The `-p neon` flag matches the project name the installer used. Omitting it makes `docker compose` pick a default project name from the current directory, which will not match the containers already running and produces confusing "no such service" errors.

To upgrade the installer itself, `git pull` in the repo and rerun `.\installer.ps1`. Existing secrets, admin credentials, and Hub config are reused unless you delete them first.

## Starting and stopping

The container stack and the mDNS publisher service are independent.

**Container stack** (run from the cloned repo root):

```powershell
docker compose -p neon -f windows\docker-compose.yml --env-file windows\.env down    # stop
docker compose -p neon -f windows\docker-compose.yml --env-file windows\.env up -d   # start
```

**mDNS publisher** (Windows service installed by the installer):

```powershell
Stop-Service neon-hub-mdns
Start-Service neon-hub-mdns
```

## Uninstalling

```powershell
# Stop and remove the container stack and its volumes (from the cloned repo root)
docker compose -p neon -f windows\docker-compose.yml --env-file windows\.env down -v

# Remove the mDNS Windows service
Stop-Service neon-hub-mdns
sc.exe delete neon-hub-mdns

# Remove the data directory
Remove-Item -Recurse -Force $env:USERPROFILE\neon-hub

# Remove the cert from the trust store (run as Administrator)
Get-ChildItem Cert:\LocalMachine\Root |
  Where-Object { $_.Subject -match 'neon-hub-win.local' } |
  Remove-Item
```

If you added the hosts-file entry manually, remove the `neon-hub-win.local` line from `C:\Windows\System32\drivers\etc\hosts`.

## Feature parity

Most Hub features work on Windows. The differences are summarized below.

| Feature                        | Status                 | Notes                                                                                                |
| ------------------------------ | ---------------------- | ---------------------------------------------------------------------------------------------------- |
| Hub stack and container health | Works                  | All containers reach `healthy`.                                                                      |
| HANA REST API                  | Works                  | `https://hana.<hostname>/docs`.                                                                      |
| nginx reverse proxy (HTTPS)    | Works                  | Port 443 on the host, TLS via the self-signed cert.                                                  |
| Hub Configuration UI           | Works                  | `https://config.<hostname>`.                                                                         |
| Skill Config Tool              | Works                  | `https://skill-config.<hostname>`.                                                                   |
| Iris Web Satellite             | Works                  | `https://iris-websat.<hostname>`.                                                                    |
| RabbitMQ admin UI              | Works                  | `https://rmq-admin.<hostname>`.                                                                      |
| mDNS Hub discovery             | Works                  | Published by a Shawl-wrapped `python-zeroconf` service. Node app discovers the Hub.                  |
| mDNS hostname alias            | Works                  | The same publisher emits A records for `hana.<hostname>` and the other Hub subdomains.               |
| TTS (Coqui)                    | Works                  | HTTP API, no audio device required.                                                                  |
| STT (Faster Whisper)           | Works                  | amd64 image runs natively on Windows.                                                                |
| Speech service (voice loop)    | Works                  | Audio flows through Docker Desktop's WSL2 audio bridge.                                              |
| Audio service (playback)       | Works                  | Same WSL2 audio path as the speech service.                                                          |
| Admin user bootstrap           | Works                  | `seed-users.ps1` writes the initial user directly into the users-service SQLite DB.                  |
| Self-signed cert trust         | Works                  | `Import-Certificate` into `LocalMachine\Root`, or pass `-TrustCert` to the installer.                |
| **Simple Docker Manager**      | **Skipped on Windows** | Docker Desktop's built-in container UI replaces it. No `manager.<hostname>` route.                   |
| **Neon Node Voice Client**     | **Not supported**      | The bundled Node Voice Client is Linux-only. Windows hosts can still pair external Nodes to the Hub. |
| **Kiosk mode**                 | **Not supported**      | Windows does not have an equivalent of the Linux kiosk launcher.                                     |

## Troubleshooting

**`docker compose up` says "no such file or directory" for one of the seed mounts.** Either you skipped a setup step, or `NEON_HOME` points to a path Docker Desktop is not sharing. Check Settings → Resources → File Sharing in Docker Desktop. Your home directory should be on the default-shared list.

**RabbitMQ crashes immediately with `failed_to_update_enabled_plugins_file`.** The default config should prevent this. If you see it, confirm `RABBITMQ_ENABLED_PLUGINS_FILE=/var/lib/rabbitmq/enabled_plugins` is in the container's env: `docker inspect neon-rabbitmq | findstr RABBIT`.

**Nginx returns 502 after restarting a backend service.** Nginx caches upstream IPs at startup, and recreated containers get new IPs on the Docker network. Bounce nginx: `docker restart neon-nginx`.

**Browser shows a cert warning.** Either trust the cert (see [Trusting the self-signed cert](#trusting-the-self-signed-cert)) or click through. The cert is locally generated and self-signed. That is expected.

**`.local` names do not resolve from other LAN devices.** Confirm the mDNS service is running: `Get-Service neon-hub-mdns`. If it is missing, rerun `installer.ps1` (it is idempotent and will reinstall the service). If the service is running but other devices still cannot resolve names, the issue is usually mDNS being blocked on the network. Pass `-AddHostsEntry` and add hosts-file entries on each client device as a workaround.

**The wizard reports OpenSSL missing even after install.** The installer searches `PATH` and a list of common install locations. If OpenSSL is installed somewhere unusual, add its `bin` directory to PATH and rerun.
