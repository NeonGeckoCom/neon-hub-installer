# Windows Installation

Neon Hub can be installed on Windows 10 (21H2 or newer) and Windows 11.
The Windows install runs the same container stack as the Linux and macOS
installs, on top of [Docker Desktop](https://www.docker.com/products/docker-desktop/)
with the WSL2 backend. A one-shot PowerShell installer handles everything
end-to-end.

!!! info
    tl;dr from an **Administrator PowerShell**:
    ```powershell
    git clone https://github.com/NeonGeckoCom/neon-hub-installer
    cd neon-hub-installer\windows
    .\installer.ps1
    ```

The installer walks an interactive wizard that prompts for the Hub
hostname, the admin user, and a few optional features (LAN mDNS, cert
trust, hosts-file fallback). Press Enter to accept each default in
brackets, then confirm the plan summary at the end.

## Prerequisites

| Component       | Version            | Notes                                                                  |
| --------------- | ------------------ | ---------------------------------------------------------------------- |
| Windows         | 10 21H2+ or 11     | Hardware virtualization enabled in BIOS/UEFI                           |
| WSL2            | Latest             | `wsl --install` from an Administrator PowerShell, then reboot          |
| Docker Desktop  | 4.x or newer       | WSL2 backend enabled in Settings → General                             |
| OpenSSL         | Any recent build   | Used once to mint the Hub's self-signed TLS cert                       |
| Shawl           | Latest             | Wraps the Hub's Python mDNS publisher as a Windows service             |
| Python          | 3.10 or newer      | Renders config templates and runs the mDNS publisher                   |

The installer expects all of these to be present before it starts.
The easiest way to install OpenSSL, Shawl, and Python is via
[`winget`](https://learn.microsoft.com/windows/package-manager/winget/):

```powershell
winget install -e --id FireDaemon.OpenSSL
winget install -e --id mtkennerly.shawl
winget install -e --id Python.Python.3.12
```

!!! note
    The installer's cert script tries OpenSSL on `PATH` first, then falls
    back to well-known install dirs (`Program Files\OpenSSL-Win64\bin\`,
    `Program Files\Git\usr\bin\`, etc.), so the
    `ShiningLight.OpenSSL.Light` and Git-for-Windows distributions also
    work even though neither adds itself to `PATH` by default.

## What the installer does

In order:

1. Generates a self-signed TLS cert for the Hub's hostname and every
   subdomain (`hana.<hostname>`, `iris.<hostname>`, and so on).
2. Lays down the Hub's data tree under `%USERPROFILE%\neon-hub` (or
   wherever you set `NEON_HOME`).
3. Creates an isolated Python venv under `${NEON_HOME}\venv` so the
   Hub's helper scripts don't pollute the system Python.
4. Generates per-host service-user passwords and HANA token secrets,
   then renders the Hub's config files from the same Jinja2 templates
   the Linux and macOS installs share.
5. `docker compose up -d` to bring up the container stack.
6. Seeds the admin user and the `neon_node` user directly into the
   users-service SQLite database.
7. Authenticates as the admin, captures a refresh token, and writes
   the `hub_admin.yaml` file that lets `neon-hub-config` reach HANA.
8. (Optional, default on) Registers a Windows service that advertises
   the Hub and all its subdomains over mDNS so other LAN devices can
   resolve `https://hana.neon-hub-win.local/` (and friends) without
   their own hosts-file edits.

Every step is idempotent: re-running the installer picks up where a
prior run left off, skipping work that's already done. Pass `-Force`
or `-RotateSecrets` if you need to redo a step.

!!! info
    First-boot can take a couple of minutes after `docker compose up`
    while RabbitMQ initializes its user database and the users-service
    container warms up its MQ consumer. The admin-token bootstrap step
    retries automatically for the first ~4 minutes.

## Accessing the Hub

After the installer finishes, the URLs printed at the end are also
available at:

| Service       | URL                                       |
| ------------- | ----------------------------------------- |
| Hub Config UI | `https://config.neon-hub-win.local/`      |
| HANA OpenAPI  | `https://hana.neon-hub-win.local/docs`    |
| Iris          | `https://iris.neon-hub-win.local/`        |
| Iris-Websat   | `https://iris-websat.neon-hub-win.local/` |
| Coqui (TTS)   | `https://coqui.neon-hub-win.local/`       |
| Fasterwhisper | `https://fasterwhisper.neon-hub-win.local/` |
| RMQ Admin     | `https://rmq-admin.neon-hub-win.local/`   |
| Skill Config  | `https://skill-config.neon-hub-win.local/` |

Browsers will warn about the self-signed certificate. To suppress the
warning on the install machine, run the installer with `-TrustCert` (or
import the cert into `LocalMachine\Root` manually).

!!! note
    Firefox uses its own certificate store and ignores
    `LocalMachine\Root`. If you use Firefox, trust the cert from
    inside Firefox's Settings → Privacy & Security → Certificates.

## Differences from the Linux install

The Windows install matches the Linux and macOS installs feature-for-
feature with a couple of exceptions:

- **No Simple Docker Manager.** The container needs `/var/run/docker.sock`,
  which Docker Desktop on Windows doesn't expose. Use Docker Desktop's
  own UI or `docker compose` commands directly.
- **mDNS publisher is opt-out, not opt-in.** Windows' built-in mDNS
  publisher has [a known bug](https://github.com/dotnet/runtime/issues/26410)
  where A records aren't broadcast reliably, so the Hub ships its own
  publisher (using `python-zeroconf`) and registers it as a Windows
  service. Bonjour-for-Windows is *not* required.
- **Hosts-file edits are opt-in.** With the mDNS publisher running, most
  machines on the LAN resolve `https://hana.neon-hub-win.local/` cleanly
  without any local DNS setup. If your machine sits behind a strict
  resolver order (some enterprise builds, certain VPN clients), pass
  `-AddHostsEntry` to also write a `127.0.0.1` mapping to
  `C:\Windows\System32\drivers\etc\hosts`.

## Manual install and troubleshooting

The Windows install lives under
[`windows/`](https://github.com/NeonGeckoCom/neon-hub-installer/tree/dev/windows)
in the installer repo. The
[`windows/README.md`](https://github.com/NeonGeckoCom/neon-hub-installer/blob/dev/windows/README.md)
documents each step the installer takes as a standalone PowerShell
command, which is the right reference if you want to skip parts, debug
a failure, or extend the install. The same README's troubleshooting
section covers the common Windows-specific failure modes (Docker
Desktop file sharing, RabbitMQ ownership, nginx 502 after restarts).

For broader configuration topics (`neon.yaml`, skill settings, external
API keys), see the cross-platform [Configuration](configuration.md) page.
