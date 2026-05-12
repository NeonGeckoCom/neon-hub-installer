# CO2 macOS Hub Deployment — Implementation Plan

Change Order 2, Sections 2.4 (macOS Installer Script), 2.5 (macOS Setup Guide), 2.6 (macOS Feature Validation).

## Architecture Decision

Single Ansible playbook (`hub.yaml`) with Darwin/Linux conditionals, not a separate codebase. This preserves feature parity as the installer evolves. The macOS entry point is a new `installer-macos.sh` that replaces only the bash wrapper (prerequisite checks, venv creation, Ansible invocation). The playbook, templates, secrets generation, cert generation, user seeding, and admin bootstrap are shared.

## Prerequisites

**User must have before running installer:**

- macOS (minimum version TBD during development — likely Ventura 13+ for Docker Desktop compatibility)
- Docker Desktop installed and running
- Homebrew installed

_If the user does not have these, the installer will exit with instructions to install them before retrying. The instructions should include links to the respective installation guides._

**Installer will set up automatically (via Homebrew), first asking the user's consent to install:**

- whiptail (`brew install newt` if missing)
- PulseAudio (`brew install pulseaudio` if missing, enable `module-native-protocol-tcp`, start daemon)

## Implementation Checklist

### Phase 1: installer-macos.sh (bash wrapper)

- [ ] Create `installer-macos.sh` entry point
  - [ ] Check macOS version (`sw_vers`)
  - [ ] Check Docker Desktop is installed and running (`docker info`)
  - [ ] Check Homebrew is available
  - [ ] Install whiptail if missing (`brew install newt`)
  - [ ] Install PulseAudio if missing (`brew install pulseaudio`)
  - [ ] **Fix Homebrew PulseAudio `.dylib` vs `.so` bug** — tested and confirmed (May 11, 2026). Homebrew builds PA modules as `.dylib` files but `dlopen()` looks for `.so`. All modules fail to load without this fix. Solution: create `.so` symlinks for every `.dylib` in the modules directory:
    ```bash
    MODULES_DIR="$(brew --prefix pulseaudio)/lib/pulseaudio/modules"
    for dylib in "$MODULES_DIR"/*.dylib; do
      so="${dylib%.dylib}.so"
      [ ! -e "$so" ] && ln -s "$(basename "$dylib")" "$so"
    done
    ```
  - [ ] **Fix PulseAudio cookie path** — tested and confirmed (May 11, 2026). `~/.config/pulse/cookie` may be an empty directory instead of a file (possibly from a prior install or `mkdir -p`). If it's a directory, PA can't initialize ANY protocol module and fails with "Failed to read cookie file: Is a directory". Fix: `[ -d ~/.config/pulse/cookie ] && rmdir ~/.config/pulse/cookie` before starting PA. PA will recreate it as a proper 256-byte cookie file on startup.
  - [ ] Enable PulseAudio TCP module: edit `$(brew --prefix pulseaudio)/etc/pulse/default.pa` — change `#load-module module-native-protocol-tcp` to `load-module module-native-protocol-tcp auth-anonymous=1 auth-ip-acl=127.0.0.1;192.168.0.0/16;172.16.0.0/12;10.0.0.0/8`. The `auth-anonymous=1` flag means no cookie mount is needed in the compose file, simplifying the setup. The `auth-ip-acl` restricts connections to localhost and RFC 1918 private ranges (which covers Docker bridge networks), preventing LAN exposure on port 4713.
  - [ ] Start PulseAudio daemon (`brew services start pulseaudio` or `pulseaudio --daemonize --exit-idle-time=-1`)
  - [ ] Verify PulseAudio TCP module is loaded (`pactl list modules short | grep tcp` — should show `module-native-protocol-tcp`). Also verify listening on port 4713 (`lsof -iTCP:4713 -sTCP:LISTEN`).
  - [ ] Determine data directory — default to `/opt/neon` (macOS locks `/home` via autofs; `/opt/neon` is the standard Unix location for add-on software and keeps path structure close to Linux's `/home/neon`)
  - [ ] Prompt for mDNS name (default `neon-hub-mac.local`) — used for SSL cert CN/SAN, nginx `server_name`, mDNS advertisement, and `/etc/hosts` entries. Does NOT change the machine's hostname.
  - [ ] Skip Node Voice Client and Kiosk prompts (out of scope for macOS)
  - [ ] Create Python venv, install Ansible (same as Linux minus apt packages)
  - [ ] **`common.sh` reuse strategy**: Do NOT source `scripts/common.sh` — its functions (`detect_user()`, `required_packages()`, `create_python_venv()`) are deeply Linux-specific (checks `$EUID == 0`, sources `/etc/os-release`, cases on Debian/Ubuntu). Instead, reimplement the needed functions inline in `installer-macos.sh`. The only reusable logic is `install_ansible()` (pip install commands) and `create_python_venv()` (minus the `chown` with `id -ng`). Keep it simple — a few dozen lines, not a shared abstraction.
  - [ ] **Note**: the Linux `installer.sh` wraps the Ansible call in `script -q -c "command" logfile` (GNU syntax). macOS `script` uses different syntax: `script -q logfile command`. The Mac installer must use the macOS syntax or drop the `script` wrapper entirely and redirect output directly.
  - [ ] Set `ANSIBLE_CONFIG` to point to the playbook directory's `ansible.cfg` (if one exists) or export `ANSIBLE_ROLES_PATH` so Ansible can find the downloaded `geerlingguy.docker` role. The Linux installer sets this implicitly by running from the playbook directory; the Mac installer should `cd` to the playbook directory or set the env var explicitly before invoking `ansible-playbook`.
  - [ ] Invoke `hub.yaml` with Mac-appropriate extra-vars (`common_name=<mDNS name>`, `trust_self_signed_cert=1`, etc.) and `-K` (ask-become-pass). Do NOT pass `ansible_os_family` — it is auto-detected by `gather_facts` (which is implicitly `true` in the main play). On macOS it will be `Darwin`. Do NOT pass `xdg_dir` or `neon_home` — these now auto-derive from `ansible_os_family` in the playbook's `vars:` block.

### Phase 2: hub.yaml playbook conditionals

#### Variable definitions

Add the following to hub.yaml's `vars:` block (alongside existing `xdg_dir`, `common_name`, etc.):

```yaml
neon_home: "{{ '/opt/neon' if ansible_os_family == 'Darwin' else '/home/neon' }}"
neon_user: "{{ ansible_user_id if ansible_os_family == 'Darwin' else 'neon' }}"
neon_group: "{{ 'staff' if ansible_os_family == 'Darwin' else 'neon' }}"
```

The `xdg_dir` default (`/home/neon/xdg`) should also be updated to derive from `neon_home`:
```yaml
xdg_dir: "{{ neon_home }}/xdg"
```
This keeps it overridable via `--extra-vars` while defaulting correctly per platform. The installer script can still pass `xdg_dir` explicitly if needed, but the default will now be correct without it.

`neon_group` is `staff` on macOS (the default primary group for all users) since there's no `neon` group.

#### Tasks to skip on Darwin (guard with `when: ansible_os_family != 'Darwin'`)

- [ ] `geerlingguy.docker` role — move from the `roles:` section to a conditional `include_role` task guarded by `when: ansible_os_family != 'Darwin'`. The role is currently declared at play level (`roles:` key in hub.yaml line 87), which cannot be conditionalized. Moving it to a task with `ansible.builtin.include_role: name=geerlingguy.docker` allows the `when:` guard. The `post_tasks` block that runs `systemctl enable docker` (line 91) also needs the same guard.
- [ ] Replace hardcoded apt package list with platform-conditional tasks. `ansible.builtin.package` does NOT delegate to Homebrew — it uses `macports` on Mac or fails. Use separate task blocks: `ansible.builtin.apt` with `when: ansible_os_family == 'Debian'` for Linux, and `community.general.homebrew` with `when: ansible_os_family == 'Darwin'` for Mac. **Important**: add `community.general` to `requirements.yml` — it is not currently listed. Darwin package list: `openssl`, `ffmpeg` (plus anything else needed). Linux keeps the current list.
- [ ] Create `neon` system user/group and group membership tasks
- [ ] `hostnamectl set-hostname`
- [ ] Avahi service definition copy + handler
- [ ] Avahi alias resolver helper install + systemd unit
- [ ] Node Voice Client import (`neon-node.yaml`)
- [ ] Kiosk install/teardown imports
- [ ] Reboot prompt
- [ ] Copy cert to `/usr/local/share/ca-certificates/` + `update-ca-certificates` (Linux trust store path)

#### Tasks to add for Darwin

- [x] Docker group GID / SDM — **resolved**: SDM is skipped entirely on Darwin. Docker Desktop provides its own container management GUI, making SDM redundant. This also eliminates the `docker_gid` resolution, docker.sock permissions, SDM password prompt, and `manager.<hostname>` nginx block on Mac. The `getent` + `set_fact` tasks for `docker_gid` should be skipped on Darwin.
- [ ] Create data directory at `/opt/neon` with same subdirectory structure as Linux. Owned by current user (no `neon` system account on Mac). The hub.yaml directory creation loop (lines 153-176) has 8 hardcoded `/home/neon/` paths that must ALL become `{{ neon_home }}`:
    - `{{ xdg_dir }}` and its subdirs (already use the variable — OK)
    - `/home/neon/compose` → `{{ neon_home }}/compose`
    - `/home/neon/.config/pulse` → **skip on Darwin** (PA runs on host, not in container)
    - `/home/neon/.config/systemd` → **skip on Darwin** (no systemd)
    - `/home/neon/.config/systemd/user` → **skip on Darwin**
    - `/home/neon/.local` → `{{ neon_home }}/.local`
    - `/home/neon/.local/state` → `{{ neon_home }}/.local/state`
    - `/home/neon/.local/state/mycroft` → `{{ neon_home }}/.local/state/mycroft`
    - `/home/neon/.cache` → `{{ neon_home }}/.cache`
  Split the loop into two: one with paths common to both platforms (using `{{ neon_home }}`), one with Linux-only paths guarded by `when: ansible_os_family != 'Darwin'`.
- [ ] Install launchd plist for mDNS service advertisement (`dns-sd -R`):
  - Plist at `~/Library/LaunchAgents/com.neongecko.neon-hub-mdns.plist`
  - Start with `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.neongecko.neon-hub-mdns.plist` (modern syntax; `launchctl load` is deprecated on Ventura+). Stop with `launchctl bootout gui/$(id -u)/com.neongecko.neon-hub-mdns`.
  - Tested and confirmed working on macOS (May 11, 2026). The exact command:
    ```
    dns-sd -R "Neon Hub on <short_hostname>" "_neon-hub._tcp" "local" 443 "scheme=https" "host=hana.<common_name>"
    ```
  - `dns-sd -R` is a long-running foreground process that registers the service for as long as it's alive. It deregisters automatically when killed.
  - Neon Node app successfully discovered this service in its "Scan for hubs" UI.
  - Example plist:
    ```xml
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>com.neongecko.neon-hub-mdns</string>
      <key>ProgramArguments</key>
      <array>
        <string>/usr/bin/dns-sd</string>
        <string>-R</string>
        <string>Neon Hub on HOSTNAME</string>
        <string>_neon-hub._tcp</string>
        <string>local</string>
        <string>443</string>
        <string>scheme=https</string>
        <string>host=hana.COMMON_NAME</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>KeepAlive</key>
      <true/>
    </dict>
    </plist>
    ```
  - Template the plist with Ansible, substituting `HOSTNAME` and `COMMON_NAME`.

- [ ] Install launchd plist for hana hostname alias (`dns-sd -P`):
  - Plist at `~/Library/LaunchAgents/com.neongecko.neon-hub-hana-alias.plist`
  - Start with `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.neongecko.neon-hub-hana-alias.plist`. Stop with `launchctl bootout gui/$(id -u)/com.neongecko.neon-hub-hana-alias`.
  - **IMPORTANT**: Use `_neon-hub-alias._tcp` as the service type, NOT `_neon-hub._tcp`. If you use the same type as the -R registration, Nodes will see duplicate Hub entries in browse results.
  - Tested and confirmed working on macOS (May 11, 2026). The exact command:
    ```
    dns-sd -P "hana-alias" "_neon-hub-alias._tcp" "local" 443 "hana.<common_name>" <PRIMARY_IP>
    ```
  - This publishes an A record for `hana.<common_name>` pointing at the Mac's IP. Verified resolvable via `dscacheutil`, `ping`, and from other devices on the LAN.
  - `dns-sd -P` is a long-running foreground process, same as `-R`.
  - The IP address is baked into the plist args. To handle DHCP changes, use `KeepAlive` + a wrapper script that resolves the current IP and execs dns-sd, OR accept that a DHCP renewal requires re-running the installer / reloading the plist. The Linux installer has the same limitation (avahi-alias-hana-resolve runs once at unit start).
  - Example plist:
    ```xml
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>com.neongecko.neon-hub-hana-alias</string>
      <key>ProgramArguments</key>
      <array>
        <string>/usr/bin/dns-sd</string>
        <string>-P</string>
        <string>hana-alias</string>
        <string>_neon-hub-alias._tcp</string>
        <string>local</string>
        <string>443</string>
        <string>hana.COMMON_NAME</string>
        <string>PRIMARY_IP</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>KeepAlive</key>
      <true/>
    </dict>
    </plist>
    ```
  - Template the plist with Ansible, substituting `COMMON_NAME` and `PRIMARY_IP`.
- [ ] Resolve `primary_ip` on Darwin — the Linux playbook uses `ansible_default_ipv4.address` (gathered facts), which may not populate correctly on macOS. Add a Darwin-specific task that detects the active network interface dynamically (don't hardcode `en0` — Macs may use `en1`, `en6`, etc. depending on hardware):
    ```yaml
    - name: Get default network interface (Darwin)
      shell: route get default | awk '/interface:/ {print $2}'
      register: darwin_default_iface
      when: ansible_os_family == 'Darwin'
      changed_when: false
    - name: Get primary IP address (Darwin)
      shell: "ipconfig getifaddr {{ darwin_default_iface.stdout }}"
      register: darwin_primary_ip
      when: ansible_os_family == 'Darwin'
      changed_when: false
    - name: Set primary_ip fact (Darwin)
      set_fact:
        primary_ip: "{{ darwin_primary_ip.stdout }}"
      when: ansible_os_family == 'Darwin'
    ```
    This IP is used for cert generation SAN and the dns-sd `-P` plist.
- [ ] Mac-specific `/etc/hosts` entries — same as Linux EXCEPT omit `manager.{{ common_name }}` on Darwin (SDM is skipped). Hub.yaml line 298 includes this entry; guard it with `when: ansible_os_family != 'Darwin'` or use a Jinja2 conditional in the blockinfile content. All other subdomain entries (`fasterwhisper`, `coqui`, `hana`, `iris`, `iris-websat`, `rmq-admin`, `config`, `skill-config`) are kept.

**Sudo/privilege model for macOS**: The Mac installer should NOT run as root / with `sudo`. Instead, run as the normal user and let Ansible's `become: yes` (at play level, hub.yaml line 44) handle elevation — Ansible will prompt for the sudo password once via `--ask-become-pass` (or `-K`). This avoids the "sudo-within-sudo" problem where running the entire script as root means `ansible_user_id` resolves to `root` instead of the actual user, breaking `neon_user` derivation and file ownership.

  The installer script should:
  1. Check it is NOT running as root (`$EUID != 0`). If root, warn and exit — "Run without sudo; the installer will prompt for elevation when needed."
  2. Pass `-K` (ask-become-pass) to the `ansible-playbook` invocation so Ansible can sudo for privileged tasks.
  3. Pre-sudo operations in the bash script itself (like `mkdir /opt/neon`) should use explicit `sudo` calls, not assume the whole script is elevated.
- [ ] Trust self-signed cert on Mac: **tested and confirmed (May 11, 2026)**. Command: `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain <cert>`. Verified that curl accepts the cert without `--insecure` after adding to the System keychain. Replaces Linux's `update-ca-certificates`.

### Phase 3: Docker Compose — macOS variant

The compose template needs platform-specific adjustments. Two options:

**Option A**: Single `neon-hub.yml.j2` with Jinja2 conditionals based on `ansible_os_family`
**Option B**: Separate `neon-hub-macos.yml.j2` template

Recommendation: **Option A** — less duplication, easier to maintain. The differences are small enough to inline.

#### Compose changes for Darwin

- [x] `x-podman` block — **no change needed**. Tested: Docker Desktop on Mac silently ignores podman-specific keys (`userns_mode`, `security_opt: label=disable`). Compose file works as-is.
- [ ] **`xdg` volume `driver_opts` verification**: The `xdg` named volume (neon-hub.yml.j2 lines 22-25) uses `driver_opts: { type: xdg, o: bind, device: ${NEON_XDG_PATH} }`. These are Linux bind-mount options with a custom type label. Verify Docker Desktop Mac handles this correctly — Docker Desktop uses virtiofs, not native bind mounts, so the `type: xdg` label and `o: bind` option may be silently accepted or may error. If it errors, wrap the `driver_opts` block in a Jinja2 conditional and use a simple bind mount on Darwin. Test this early in Phase 6 validation.
- [ ] Remove `/dev/snd` device mounts from `speech`, `audio`, `enclosure`, `skills`
- [ ] Remove PulseAudio unix socket mounts (`${XDG_RUNTIME_DIR}/pulse/native`)
- [ ] **PULSE_SERVER anchor conflict**: The `x-default-env-vars` YAML anchor (line 15) hardcodes `PULSE_SERVER: unix:${XDG_RUNTIME_DIR}/pulse/native`. Every service inherits this via `<<: *default-env-vars`. On Darwin, audio services need `PULSE_SERVER: host.docker.internal` instead. **Solution**: remove `PULSE_SERVER` from the anchor entirely and set it via the `.env` file (`PULSE_SERVER` is already planned as a `.env.j2` variable in Phase 4). Services that use `<<: *default-env-vars` will pick it up from the environment. Also remove `PULSE_COOKIE` from the anchor — it's unused on Darwin (no cookie auth) and should come from `.env` on Linux. This keeps the anchor platform-neutral.
- [ ] PulseAudio cookie mount is NOT needed on Mac — we use `auth-anonymous=1` on the TCP module, so no cookie auth. Remove the cookie volume mounts on Darwin.
- [ ] Remove D-Bus socket mounts (`${XDG_RUNTIME_DIR}/bus`)
- [ ] Fix RabbitMQ hardcoded volume mount: line 182 of `neon-hub.yml.j2` has `/home/neon/xdg/config/rabbitmq:/etc/rabbitmq` — should use `{{ neon_home }}/xdg/config/rabbitmq` or `${NEON_CONFIG_FOLDER}/rabbitmq`
- [ ] Remove `/etc/timezone` and `/etc/localtime` mounts on Darwin from ALL services that have them. The affected services are: `messagebus` (lines 68-69), `speech` (lines 84-85), `audio` (lines 112-113), `enclosure` (lines 136-137), `skills` (lines 160-161), and `hub_config` (lines 393-394). Don't miss `hub_config` — it's at the bottom of the file and easy to overlook. Use a Jinja2 conditional block around these volume entries.
- [ ] Remove `/etc/localtime` mounts on Darwin. Decision: remove and rely on the `TZ` env var. `/etc/localtime` exists on macOS (symlink to `/var/db/timezone/zoneinfo/...`) and would technically work as a read-only bind mount, but the `TZ` env var is the standard Docker approach and avoids platform-specific mount paths. The `TZ` value is detected by the installer (see Phase 4).
- [ ] Remove `DISPLAY` and X11 socket mounts from `enclosure`
- [ ] Introduce a `neon_home` variable (Linux: `/home/neon`, Mac: `/opt/neon`) and replace ALL hardcoded `/home/neon` paths in templates. The following are hardcoded and NOT covered by `xdg_dir`:
  - `neon-hub.yml.j2` line 182: `/home/neon/xdg/config/rabbitmq:/etc/rabbitmq`
  - `neon-hub.yml.j2` lines 240-241: `/home/neon/compose/neon-logo.png`, `/home/neon/compose/skill-config.json`
  - `neon-hub.yml.j2` lines 369-371: `/home/neon/compose/nginx.conf`, `/home/neon/{{ common_name }}.crt`, `/home/neon/{{ common_name }}.key`
  - `hub.yaml` lines 218-256: task destinations for compose dir, nginx config, logo, skill-config files
  - `hub.yaml` cert generation: `/home/neon/{{ common_name }}.crt/.key`
  - `hub.yaml` line 271: `docker_compose_v2` task has `project_src: /home/neon/compose` — must become `{{ neon_home }}/compose`
  - `hub.yaml` lines 220, 227, 234, 241, 247, 255: all `dest:` paths under compose dir tasks use `/home/neon/compose/...` — must become `{{ neon_home }}/compose/...`
  - `generate-certificate.yaml` lines 4, 10, 11, 23-24, 29, 41: all cert paths use `/home/neon/` — must become `{{ neon_home }}/`
  - All should become `{{ neon_home }}/compose/...`, `{{ neon_home }}/{{ common_name }}.crt`, etc.
- [x] Docker Manager (`simple-docker-manager`) — **skipped on Darwin**. Docker Desktop provides its own container management GUI. Skip the `docker_manager` service, `sdm-data` volume, and SDM password prompt. **Also**: add a `{% if ansible_os_family != 'Darwin' %}` conditional around the `manager.{{ common_name }}` server block in `nginx.conf.j2` — the nginx template is shared and will error if the backend service doesn't exist.

### Phase 4: .env.j2 template adjustments

**Prerequisite**: `.env.j2` is currently a static file with hardcoded values (no Jinja2 variables). It must first be converted to use variables before any platform conditionals can work. Replace hardcoded values with Jinja2 variables (e.g., `NEON_USER={{ neon_user }}`, `NEON_CONFIG_FOLDER={{ xdg_dir }}/config`, `NEON_XDG_PATH={{ xdg_dir }}`, etc.).

- [ ] `NEON_USER` — keep as `neon` on ALL platforms. This is the container-internal username, NOT the host user. The `neon_user` Ansible variable (for host file ownership) is a separate concept. See Implementation Notes for details.
- [ ] `NEON_CONFIG_FOLDER`, `NEON_SHARE_FOLDER`, `NEON_LOCAL_FOLDER` — `/opt/neon/xdg/...` paths
- [ ] `NEON_XDG_PATH` — `/opt/neon/xdg`
- [ ] `XDG_RUNTIME_DIR` — **tested and resolved**: must still be defined in `.env` to avoid compose interpolation warnings, but the value is unused on Mac (D-Bus mounts removed, PULSE_SERVER switched to TCP). Set to `/tmp` or keep `/run/user/1000` as a harmless default. **Critical**: the D-Bus and pulse socket volume mounts that reference `${XDG_RUNTIME_DIR}` MUST be removed from the Darwin compose — if they remain, compose will fail with "path is not shared from the host".
- [ ] `PULSE_SERVER` — `host.docker.internal` on Mac (NOT the deprecated `docker.for.mac.host.internal`)
- [ ] `DISPLAY` — remove or empty on Mac
- [ ] `TZ` — detect from `systemsetup -gettimezone` or `readlink /etc/localtime`
- [ ] `HOSTNAME` — currently hardcoded as `neon-hub.local`. Used by RabbitMQ's `hostname: $HOSTNAME` directive. Should become `{{ common_name }}` so it matches the user's chosen mDNS name.
- [ ] `PULSE_COOKIE` — on Linux, set to `/xdg/config/pulse/cookie` (in-container path). On Darwin, remove or leave empty — cookie auth is disabled (`auth-anonymous=1`). Move from the YAML anchor to `.env` (see Phase 3 anchor conflict fix).
- [ ] `DIANA_XDG_PATH` — currently hardcoded to `/home/neon/xdg`. Should become `{{ neon_home }}/xdg` (same as `NEON_XDG_PATH`). Used by some containers that reference the Diana config path.

### Phase 5: File ownership considerations

**Tested and resolved (May 11, 2026).** Docker Desktop Mac uses virtiofs for bind mounts, which maps all file ownership to the container's running UID. This means:

- [x] Mixed-UID containers sharing XDG volume: **works**. Root containers and non-root containers (e.g., UID 999) both read and write the same files without permission errors. Each container sees the files as owned by its own UID.
- [x] Host-written SQLite (seed-user.py) readable by container: **works**. Host writes the DB as the Mac user, containers at any UID can read and write it.
- [x] Host-side ownership: all files appear owned by the Mac user regardless of which container UID created them. No stray root-owned files.
- [x] No `chown`, `user: root` overrides, or entrypoint hacks needed on Mac. Introduce a `neon_user` variable (Linux: `neon`, Mac: current user from `ansible_user_id`) and replace hardcoded `owner: neon` / `group: neon` throughout. Specific files that need this:
  - `hub.yaml`: directory creation tasks (lines 153-176), config file tasks, cert permissions
  - `seed-hana-users.yaml` line 19: `owner: root` / `group: root` on the temp seed-user.py copy — `root` user exists on macOS but `group: root` is GID 0 (`wheel`). Ansible resolves this correctly on both platforms, so no change needed. But document the reasoning.
  - `seed-hana-users.yaml` line 52: `owner: neon` / `group: neon` on the SQLite DB — must become `{{ neon_user }}` / `{{ neon_user }}`
  - `generate-certificate.yaml` lines 17-24: cert/key file permissions
  - `bootstrap-hub-admin.yaml` lines 53-55, 63-64: hub_admin.yaml directory and file ownership

### Phase 6: Feature validation & parity table

Test each feature on macOS + Docker Desktop and document status:

| Feature                                     | Expected Status   | Notes                                       |
| ------------------------------------------- | ----------------- | ------------------------------------------- |
| Hub stack starts and all containers healthy | Should work       |                                             |
| HANA reachable at localhost:8082            | Should work       |                                             |
| nginx reverse proxy (HTTPS on 443)          | Should work       |                                             |
| Hub Config UI (config.<hostname>)           | Should work       |                                             |
| Simple Docker Manager (manager.<hostname>)  | Skipped           | Docker Desktop provides container mgmt GUI  |
| Skill Config Tool (skill-config.<hostname>) | Should work       |                                             |
| RabbitMQ Admin (rmq-admin.<hostname>)       | Should work       |                                             |
| Iris Web Satellite (iris-websat.<hostname>) | Should work       |                                             |
| mDNS Hub discovery (\_neon-hub.\_tcp)       | Confirmed working | dns-sd -R, tested 2026-05-11                |
| mDNS hana hostname alias                    | Confirmed working | dns-sd -P, tested 2026-05-11                |
| Node app connects and authenticates         | Needs testing     | TLS cert validation against hana.<hostname> |
| STT (Faster Whisper)                        | Should work       | No audio device needed, HTTP API            |
| TTS (Coqui)                                 | Should work       | No audio device needed, HTTP API            |
| Speech service (voice loop)                 | Should work       | PulseAudio TCP confirmed working 2026-05-11 |
| Audio service (playback)                    | Should work       | PulseAudio TCP confirmed, played audio from container |
| Enclosure service                           | Should work       | Works without X11/D-Bus; keep in Mac compose |
| Admin user bootstrap                        | Should work       | seed-user.py + HANA login                   |
| Self-signed cert trust                      | Confirmed working | `security add-trusted-cert`, tested 2026-05-11 |

### Phase 7: Documentation (macOS Setup Guide — CO2 2.5)

This repo hosts a MkDocs Material static site at `docs/` (served at `neongeckocom.github.io/neon-hub-installer`). macOS documentation should be added as new pages in `docs/` and wired into `mkdocs.yml` nav, not as standalone markdown files.

- [ ] Add `docs/macos-requirements.md` — macOS version, Docker Desktop, Homebrew prerequisites
- [ ] Add `docs/macos-installation.md` — step-by-step install instructions using `installer-macos.sh`; note that the installer handles PulseAudio and whiptail automatically via Homebrew
- [ ] Add `docs/macos-configuration.md` (if needed, or add a macOS section to existing `configuration.md`)
- [ ] Add `docs/macos-troubleshooting.md` — PulseAudio, launchd/mDNS, Docker Desktop specifics
- [ ] Include feature parity table from Phase 6
- [ ] Document known limitations and workarounds
- [ ] Document how to update the Hub stack on Mac
- [ ] Document how to start/stop mDNS advertisement (`launchctl bootstrap gui/$(id -u) <plist>` / `launchctl bootout gui/$(id -u)/<label>`)
- [ ] Update `mkdocs.yml` nav to include new macOS pages
- [ ] Document rollback/uninstall — full checklist:
    1. Stop containers: `docker compose -f /opt/neon/compose/neon-hub.yml down -v`
    2. Remove launchd plists: `launchctl bootout gui/$(id -u)/com.neongecko.neon-hub-mdns && rm ~/Library/LaunchAgents/com.neongecko.neon-hub-mdns.plist` (repeat for hana-alias)
    3. Remove data directory: `sudo rm -rf /opt/neon`
    4. Remove `/etc/hosts` entries: `sudo sed -i '' '/ANSIBLE MANAGED BLOCK - NEON HUB SUBDOMAINS/,/ANSIBLE MANAGED BLOCK - NEON HUB SUBDOMAINS/d' /etc/hosts`
    5. Remove cert from System keychain: `sudo security delete-certificate -c <CN> -t /Library/Keychains/System.keychain`
    6. Revert PulseAudio config: edit `$(brew --prefix pulseaudio)/etc/pulse/default.pa` — comment out `load-module module-native-protocol-tcp ...` line. Remove `.so` symlinks from `$(brew --prefix pulseaudio)/lib/pulseaudio/modules/`. Optionally `brew services stop pulseaudio` and `brew uninstall pulseaudio`.
    7. Remove Python venv: `rm -rf <venv_path>`

### Implementation Notes

- **Per-task `become` mapping**: on Linux, the play runs with `become: yes` globally (hub.yaml line 44). On Mac, this still works — Ansible uses `sudo` (via `-K` / ask-become-pass) to escalate. The global `become: yes` is fine for both platforms. Tasks that should NOT run as root (launchd plist loading, which must run in the user's GUI session) need explicit `become: no`. File ownership tasks should use `owner: {{ neon_user }}` / `group: {{ neon_group }}` instead of hardcoded `neon`.
- **Re-run idempotency on Mac**: the Linux installer handles re-runs (secrets file detection, admin creds reuse). The Mac installer inherits this via the shared playbook. Launchd plists need idempotent handling. Use this pattern in Ansible:
  ```yaml
  - name: Check if mDNS service is loaded
    shell: launchctl list | grep com.neongecko.neon-hub-mdns
    register: mdns_loaded
    failed_when: false
    changed_when: false
    become: no
  - name: Unload existing mDNS service
    shell: launchctl bootout gui/{{ ansible_user_uid }}/com.neongecko.neon-hub-mdns
    when: mdns_loaded.rc == 0
    become: no
  - name: Load mDNS service
    shell: launchctl bootstrap gui/{{ ansible_user_uid }} ~/Library/LaunchAgents/com.neongecko.neon-hub-mdns.plist
    become: no
  ```
  Repeat the same pattern for the hana-alias plist. The `become: no` is important — LaunchAgents run in the user's GUI session, not root's.
- **In-container paths vs host paths**: the compose volume `xdg` mounts `${NEON_XDG_PATH}` (host: `/opt/neon/xdg` on Mac, `/home/neon/xdg` on Linux) to `/home/neon` INSIDE the container. The in-container path is fixed and independent of the host path — containers always see `/home/neon` internally regardless of platform. This is correct and requires no changes.
- **`NEON_USER` dual meaning**: `NEON_USER` in `.env` is used for both host-side paths (e.g., `/home/${NEON_USER}/.config/pulse/cookie`) and in-container paths (e.g., `nltk:/home/${NEON_USER}/nltk_data` on line 158). On Linux both resolve to `neon`. On Mac, if we change `NEON_USER` to the Mac username, the in-container `nltk` path breaks (container has no such user). **Solution**: keep `NEON_USER=neon` in `.env` — it's the container-internal user identity. Host-side paths that vary by platform (pulse cookie, xdg paths) are already handled by other `.env` variables (`NEON_CONFIG_FOLDER`, `NEON_XDG_PATH`) or removed on Darwin (pulse cookie mount). The cookie mount at `/home/${NEON_USER}/.config/pulse/cookie` is removed on Darwin anyway (Phase 3). So `NEON_USER` stays `neon` on all platforms.
- **Update Phase 4 accordingly**: the `.env.j2` item for `NEON_USER` should NOT change to `{{ neon_user }}`. Keep it as `neon` on both platforms. The `neon_user` Ansible variable (for file ownership) and `NEON_USER` env var (for container paths) are separate concerns.

## Resolved Questions (formerly Open)

All open questions have been resolved during scoping:

1. **Data directory path**: `/opt/neon` — macOS locks `/home` via autofs.
2. **System hostname vs. mDNS name**: Installer prompts for an mDNS name used for cert/nginx/dns-sd/hosts. Does not change machine hostname.
3. **XDG_RUNTIME_DIR**: Keep in `.env` as harmless default; actual PulseAudio/D-Bus mounts removed on Darwin.
4. **Docker Desktop Mac networking**: Confirmed working — container DNS, port bindings, LAN reachability all identical to Linux (tested from localhost and from Marvin via SSH).
5. **`geerlingguy.docker` role skip**: Skip on Darwin. The role is in the `roles:` section of the play, so the cleanest approach is either (a) move it to a conditional `include_role`, (b) use the role's own skip vars, or (c) split into a Linux-setup play and a shared play. Implementation detail — the key decision is that it's skipped, since Docker Desktop is a prerequisite.
6. **Enclosure service on Mac**: Keep it. Works fine without X11 or D-Bus — those mounts are removed on Darwin but the service itself runs normally.
7. **File ownership**: Docker Desktop virtiofs maps all ownership to container's running UID. Mixed-UID containers share volumes without issues. No `chown` hacks needed.
8. **Self-signed cert trust**: `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain <cert>` — confirmed working.
9. **SDM on Mac**: Skipped — Docker Desktop provides its own container management GUI.
10. **docker_gid for SDM**: Moot since SDM is skipped, but for reference: no `docker` group on Mac, socket is `root:root 660` inside VM, `group_add: "0"` works.
11. **x-podman block**: Docker Desktop silently ignores podman-specific keys. No change needed.
12. **mDNS/Bonjour**: `dns-sd -R` for service, `dns-sd -P` with `_neon-hub-alias._tcp` for hana alias. Both confirmed working, Node app discovers the Hub.
13. **PulseAudio on Homebrew macOS**: Three issues discovered and fixed (May 11, 2026): (a) `.dylib` vs `.so` — create symlinks, (b) cookie path may be a directory — rmdir it, (c) use `auth-anonymous=1` on TCP module so no cookie mount needed. Docker container successfully connected to host PA and played audio via `host.docker.internal`.
14. **`ansible.builtin.package` on Mac**: Does NOT delegate to Homebrew. Use `community.general.homebrew` explicitly. Add `community.general` to `requirements.yml`.
15. **`script` command syntax**: macOS uses `script -q logfile command` (BSD), Linux uses `script -q -c "command" logfile` (GNU). Mac installer must use the correct syntax.
16. **PULSE_SERVER hostname**: Use `host.docker.internal` (current), NOT `docker.for.mac.host.internal` (deprecated).
17. **`NEON_USER` in `.env` stays `neon` on all platforms**: It's the container-internal username used for in-container paths (`/home/${NEON_USER}/nltk_data`, pulse cookie path). The host-side `neon_user` Ansible variable (for file ownership) is a separate concept. Don't conflate them.
18. **PulseAudio LAN exposure**: `auth-anonymous=1` alone exposes port 4713 to the LAN. Add `auth-ip-acl=127.0.0.1;192.168.0.0/16;172.16.0.0/12;10.0.0.0/8` to restrict to localhost and RFC 1918 ranges.
19. **`launchctl load/unload` deprecated**: Use `launchctl bootstrap gui/<UID>` and `launchctl bootout gui/<UID>/<label>` on Ventura+.
20. **Mac installer should NOT run as root**: Run as normal user, pass `-K` to `ansible-playbook` for sudo elevation. Running as root breaks `ansible_user_id` resolution (would return `root` instead of actual user).
21. **`PULSE_SERVER` YAML anchor conflict**: Remove `PULSE_SERVER` and `PULSE_COOKIE` from the `x-default-env-vars` anchor in the compose template. Set them via `.env` instead, making the anchor platform-neutral.
22. **`common.sh` not reusable on Mac**: Reimplement needed functions inline in `installer-macos.sh` rather than sourcing/forking the Linux-specific `common.sh`.
