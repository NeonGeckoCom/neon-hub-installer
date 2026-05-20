# macOS Installation

Neon Hub runs on macOS via Docker Desktop. The installer is a thin Bash wrapper around the same Ansible playbook the Linux installer uses, so the resulting Hub is functionally close to a Linux deployment with a handful of platform-specific differences (see [Feature parity](#feature-parity) below).

## Prerequisites

You will need:

- **macOS Ventura (13) or newer.** Older versions are untested and may fail, although any version that is still supported by Docker Desktop should work.
- **A container runtime.** [Docker Desktop](https://www.docker.com/products/docker-desktop/) is the default and best-tested option. [Podman Desktop](https://podman-desktop.io/) (or `podman machine` from the CLI) also works, provided you have the `docker` and `docker compose` shims on your PATH so the installer's `docker info` and `docker compose` calls resolve to Podman. Whichever runtime you choose must be installed and running before you start the installer.
- **[Homebrew](https://brew.sh).** Used to install `whiptail` (for the TUI prompts) and PulseAudio (for the voice stack). The installer prompts before installing either.
- **Apple Silicon notes.** The Hub is x86_64-first. Most services run natively on ARM Macs, but `stt_fasterwhisper` currently has no ARM64 image and will fall back to Rosetta emulation. See [Feature parity](#feature-parity).

The installer does not run as `root`. It uses `sudo -K` (ask-become-pass) to elevate individual Ansible tasks. Running the script with `sudo` will fail intentionally.

## Install

Clone the repo and run the macOS entry point:

```bash
git clone https://github.com/NeonGeckoCom/neon-hub-installer
cd neon-hub-installer
./installer-macos.sh
```

The installer walks you through an interactive setup:

1. **Prerequisite checks.** macOS version, Docker Desktop running, Homebrew available.
2. **Homebrew dependencies.** Installs `whiptail` and PulseAudio if missing. Asks before each.
3. **PulseAudio configuration.** Enables the TCP module restricted to localhost and RFC 1918 ranges, then starts the daemon. Audio services in Docker reach the host over `host.docker.internal:4713`.
4. **Hostname prompt.** Default `neon-hub-mac.local`. Used for the TLS cert, nginx server names, mDNS advertisement, and `/etc/hosts` entries. Does not change your machine's hostname.
5. **Admin credentials prompt.** Username and password for the Hub admin user.
6. **Ansible playbook.** Generates secrets, renders configs, brings up the container stack, seeds the admin user, and registers two `launchd` services for mDNS advertisement.

Total install time is roughly 15 to 30 minutes on a first run, mostly Docker image pulls.

When it finishes, validate the install from a browser or terminal:

```bash
curl -k https://hana.neon-hub-mac.local/docs
```

A 200 confirms HANA is up. The configuration UI is at `https://config.neon-hub-mac.local`.

## Data directory

The Hub stores everything under `~/neon-hub`:

- `~/neon-hub/compose/` holds the rendered `docker-compose.yml`, nginx config, and TLS cert.
- `~/neon-hub/xdg/` holds Hub configuration, RabbitMQ data, the users-service SQLite DB, and model caches.
- `~/neon-hub/venv/` is the Python virtualenv used by the installer for Ansible.

This path was chosen because Docker Desktop shares `/Users` by default. Paths under `/opt/neon` (the Linux convention) require manual file-sharing setup in Docker Desktop and are not recommended.

## Trusting the self-signed cert

The installer generates a self-signed TLS cert at `~/neon-hub/<hostname>.crt`. To stop browsers from warning on every visit, add it to the System keychain:

```bash
sudo security add-trusted-cert \
  -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  ~/neon-hub/neon-hub-mac.local.crt
```

You can also accept the warning in the browser once per host. The cert is regenerated on rerun if the hostname changes, so you may need to repeat this step.

## Updating

To pull the latest images and restart the stack:

```bash
docker compose -p neon -f ~/neon-hub/compose/neon-hub.yml pull
docker compose -p neon -f ~/neon-hub/compose/neon-hub.yml up -d
```

The `-p neon` flag matches the project name the installer used. Omitting it makes `docker compose` pick a default project name from the current directory, which will not match the containers already running and produces confusing "no such service" errors.

To upgrade the installer itself, `git pull` in the repo and rerun `./installer-macos.sh`. The install is idempotent. Existing secrets, admin credentials, and Hub config are reused unless you delete them first.

## Starting and stopping

The Hub stack and its mDNS advertisement are independent.

**Container stack:**

```bash
docker compose -p neon -f ~/neon-hub/compose/neon-hub.yml down   # stop
docker compose -p neon -f ~/neon-hub/compose/neon-hub.yml up -d  # start
```

**mDNS advertisement** (so Nodes on the LAN can discover the Hub):

```bash
launchctl bootout gui/$(id -u)/com.neongecko.neon-hub-mdns       # stop
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.neongecko.neon-hub-mdns.plist  # start
```

A second plist (`com.neongecko.neon-hub-hana-alias`) publishes the `hana.<hostname>` A record. Manage it the same way.

## Uninstalling

```bash
# Stop and remove the container stack and its volumes
docker compose -p neon -f ~/neon-hub/compose/neon-hub.yml down -v

# Unload and remove the launchd plists
launchctl bootout gui/$(id -u)/com.neongecko.neon-hub-mdns
launchctl bootout gui/$(id -u)/com.neongecko.neon-hub-hana-alias
rm ~/Library/LaunchAgents/com.neongecko.neon-hub-*.plist

# Remove the data directory
rm -rf ~/neon-hub

# Remove the /etc/hosts entries
sudo sed -i '' '/ANSIBLE MANAGED BLOCK - NEON HUB SUBDOMAINS/,/END ANSIBLE MANAGED BLOCK - NEON HUB SUBDOMAINS/d' /etc/hosts

# Remove the cert from the System keychain
sudo security delete-certificate -c neon-hub-mac.local -t /Library/Keychains/System.keychain
```

PulseAudio and `whiptail` are left installed. To remove them and revert the installer's PulseAudio changes:

```bash
# Stop the PulseAudio daemon
brew services stop pulseaudio

# Comment out the TCP module line in PulseAudio's default config
sed -i '' 's|^load-module module-native-protocol-tcp|#load-module module-native-protocol-tcp|' "$(brew --prefix pulseaudio)/etc/pulse/default.pa"

# Remove the .so symlinks the installer created to work around Homebrew's .dylib naming
find "$(brew --prefix pulseaudio)/lib/pulseaudio/modules" -name '*.so' -type l -delete

# Uninstall the Homebrew packages if you don't use them elsewhere
brew uninstall pulseaudio newt
```

## Feature parity

Most Hub features work on macOS. The differences are summarized below.

| Feature                        | Status               | Notes                                                                                              |
| ------------------------------ | -------------------- | -------------------------------------------------------------------------------------------------- |
| Hub stack and container health | Works                | All containers reach `healthy`.                                                                    |
| HANA REST API                  | Works                | `https://hana.<hostname>/docs`.                                                                    |
| nginx reverse proxy (HTTPS)    | Works                | Port 443 on the host, TLS via the self-signed cert.                                                |
| Hub Configuration UI           | Works                | `https://config.<hostname>`.                                                                       |
| Skill Config Tool              | Works                | `https://skill-config.<hostname>`.                                                                 |
| Iris Web Satellite             | Works                | `https://iris-websat.<hostname>`.                                                                  |
| RabbitMQ admin UI              | Works                | `https://rmq-admin.<hostname>`.                                                                    |
| mDNS Hub discovery             | Works                | Published via `dns-sd -R` from a launchd agent. Node app discovers the Hub.                        |
| mDNS hostname alias            | Works                | `dns-sd -P` publishes `hana.<hostname>` so off-host clients resolve the cert subject.              |
| TTS (Coqui)                    | Works                | HTTP API, no audio device required.                                                                |
| STT (Faster Whisper)           | **Limited on ARM64** | Upstream image is amd64-only. Runs under Rosetta on Apple Silicon, slower than native.             |
| Speech service (voice loop)    | Works                | Audio reaches the host PulseAudio daemon over TCP on `host.docker.internal:4713`.                  |
| Audio service (playback)       | Works                | Same PulseAudio path as the speech service.                                                        |
| Enclosure service              | Works                | Runs without X11 or D-Bus. Those mounts are skipped on Darwin.                                     |
| Admin user bootstrap           | Works                | `seed-user.py` writes the initial user directly into the users-service SQLite DB.                  |
| Self-signed cert trust         | Works                | Via `security add-trusted-cert`.                                                                   |
| **Simple Docker Manager**      | **Skipped on macOS** | Docker Desktop's built-in container UI replaces it. No `manager.<hostname>` route.                 |
| **Neon Node Voice Client**     | **Not supported**    | The bundled Node Voice Client is Linux-only. macOS hosts can still pair external Nodes to the Hub. |
| **Kiosk mode**                 | **Not supported**    | macOS does not have an equivalent of the Linux kiosk launcher.                                     |

## Troubleshooting

**The installer exits with "Docker Desktop is not running."** Open Docker Desktop and wait until its status icon shows "Docker Desktop is running" before rerunning.

**`launchctl bootstrap` returns "Bootstrap failed: 5: Input/output error."** A previous instance of the plist is still loaded. Bootout first: `launchctl bootout gui/$(id -u)/<label>`, then rerun bootstrap.

**Audio services log "Connection refused" to PulseAudio.** Verify PulseAudio is listening on 4713: `lsof -iTCP:4713 -sTCP:LISTEN`. If nothing is listening, start the daemon: `brew services start pulseaudio`. If it still fails, check that the cookie path is a file and not a directory: `ls -la ~/.config/pulse/cookie`. If it is a directory, remove it (`rmdir ~/.config/pulse/cookie`) and restart PulseAudio.

**Nginx returns 502 after restarting a backend service.** Nginx caches upstream IPs at startup, and recreated containers get new IPs on the Docker network. Bounce nginx: `docker restart neon-nginx`.

**HANA is reachable from the host but not from Nodes on the LAN.** Confirm the mDNS launchd agents are loaded: `launchctl list | grep neongecko`. If they are missing, reload from `~/Library/LaunchAgents/`. Confirm port 443 is open in macOS Firewall.

**`stt_fasterwhisper` fails to pull on Apple Silicon.** Tracked upstream. The current workaround is to force `linux/amd64` for that one service and let Rosetta emulate it. Performance is acceptable for short utterances but noticeably slower than native.
