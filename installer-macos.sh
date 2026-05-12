#!/bin/bash
# installer-macos.sh — macOS entry point for Neon Hub
#
# This script prepares the macOS environment and invokes the shared Ansible
# playbook (hub.yaml) to deploy the Neon Hub stack on Docker Desktop.
#
# It does NOT source scripts/common.sh (too Linux-specific). Needed
# functionality is reimplemented inline.

set -euo pipefail

###############################################################################
# Constants
###############################################################################
NEON_HOME="/opt/neon"
VENV_PATH="${NEON_HOME}/venv"
LOG_FILE="${NEON_HOME}/install.log"
ANSIBLE_LOG_FILE="${NEON_HOME}/ansible.log"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PLAYBOOK_DIR="${SCRIPT_DIR}/debos/overlays/ansible"
SECRETS_FILE="${PLAYBOOK_DIR}/neon_hub_secrets.yaml"

# Defaults
DEFAULT_COMMON_NAME="neon-hub-mac.local"
DEFAULT_ADMIN_USER="neon"

# Enable debug/verbosity for Bash and Ansible
ansible_debug=()
if [ "${DEBUG:-}" = "true" ]; then
    set -x
    ansible_debug=(-vvv)
fi

###############################################################################
# Colors
###############################################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

done_fmt="${GREEN}done${NC}"
fail_fmt="${RED}fail${NC}"
warn_fmt="${YELLOW}warn${NC}"

###############################################################################
# Utility functions
###############################################################################

info()    { printf "${CYAN}➤${NC} %s\n" "$*"; }
success() { printf "  [${done_fmt}] %s\n" "$*"; }
warn()    { printf "  [${warn_fmt}] %s\n" "$*"; }
error()   { printf "  [${fail_fmt}] %s\n" "$*" >&2; }
fatal()   { error "$@"; exit 1; }

# Whiptail wrapper with fallback to plain read prompts
HAS_WHIPTAIL=0

show_message() {
    if [ "$HAS_WHIPTAIL" -eq 1 ]; then
        whiptail --title "Neon Hub Installer" --msgbox "$1" 20 78
    else
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        printf "%b\n" "$1"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        read -rp "Press Enter to continue... "
    fi
}

get_input() {
    local prompt="$1"
    local default="${2:-}"
    if [ "$HAS_WHIPTAIL" -eq 1 ]; then
        whiptail --title "Neon Hub Installer" --inputbox "$prompt" 10 78 "$default" 3>&1 1>&2 2>&3
    else
        local result
        if [ -n "$default" ]; then
            read -rp "$prompt [$default]: " result
            echo "${result:-$default}"
        else
            read -rp "$prompt: " result
            echo "$result"
        fi
    fi
}

get_password() {
    local prompt="$1"
    if [ "$HAS_WHIPTAIL" -eq 1 ]; then
        whiptail --title "Neon Hub Installer" --passwordbox "$prompt" 12 78 3>&1 1>&2 2>&3
    else
        local result
        read -rsp "$prompt: " result
        echo "$result"
        # Move to next line after hidden input
        >&2 echo ""
    fi
}

get_yesno() {
    local prompt="$1"
    if [ "$HAS_WHIPTAIL" -eq 1 ]; then
        if whiptail --title "Neon Hub Installer" --yesno "$prompt" 10 78 3>&1 1>&2 2>&3; then
            return 0
        else
            return 1
        fi
    else
        local yn
        while true; do
            read -rp "$prompt (y/n) " yn
            case "$yn" in
                [Yy]*) return 0 ;;
                [Nn]*) return 1 ;;
                *) echo "Please answer y or n." ;;
            esac
        done
    fi
}

###############################################################################
# Step 1: Must NOT run as root
###############################################################################
check_not_root() {
    if [ "$EUID" -eq 0 ]; then
        fatal "Run without sudo; the installer will prompt for elevation when needed.

On macOS, the installer must run as your normal user so that Ansible
correctly resolves file ownership. Privileged operations (like writing
to /opt/neon or /etc/hosts) use targeted sudo calls internally."
    fi
}

###############################################################################
# Step 2: Check prerequisites
###############################################################################
check_macos_version() {
    info "Checking macOS version..."
    local version
    version="$(sw_vers -productVersion)"
    local major
    major="$(echo "$version" | cut -d. -f1)"

    if [ "$major" -lt 13 ]; then
        warn "macOS $version detected. This installer is designed for macOS 13 (Ventura) or later."
        warn "You may encounter issues on older versions."
        echo ""
        if ! get_yesno "Continue anyway?"; then
            exit 1
        fi
    else
        success "macOS $version"
    fi
}

check_docker() {
    info "Checking Docker Desktop..."
    if ! command -v docker &>/dev/null; then
        fatal "Docker is not installed.

Please install Docker Desktop for Mac:
  https://www.docker.com/products/docker-desktop/

After installing, launch Docker Desktop and wait for it to finish starting,
then re-run this installer."
    fi

    if ! docker info &>/dev/null; then
        fatal "Docker Desktop is not running.

Please start Docker Desktop (look for it in Applications or the menu bar),
wait for the whale icon to stop animating, then re-run this installer."
    fi
    success "Docker Desktop is installed and running"
}

check_homebrew() {
    info "Checking Homebrew..."
    if ! command -v brew &>/dev/null; then
        fatal "Homebrew is not installed.

Please install Homebrew first:
  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"

For more information: https://brew.sh

Then re-run this installer."
    fi
    success "Homebrew is available"
}

###############################################################################
# Step 3: Install optional dependencies
###############################################################################
install_whiptail() {
    if command -v whiptail &>/dev/null; then
        HAS_WHIPTAIL=1
        success "whiptail is available"
        return
    fi

    info "whiptail provides a nicer dialog experience for the installer."
    if get_yesno "Install whiptail via Homebrew? (brew install newt)"; then
        info "Installing whiptail (newt)..."
        if brew install newt &>/dev/null; then
            HAS_WHIPTAIL=1
            success "whiptail installed"
        else
            warn "Failed to install whiptail — falling back to plain prompts"
        fi
    else
        warn "Skipping whiptail — using plain text prompts"
    fi
}

install_pulseaudio() {
    if command -v pulseaudio &>/dev/null; then
        success "PulseAudio is already installed"
        return 0
    fi

    info "PulseAudio is needed for audio playback from Neon Hub containers."
    if get_yesno "Install PulseAudio via Homebrew? (brew install pulseaudio)"; then
        info "Installing PulseAudio..."
        if brew install pulseaudio; then
            success "PulseAudio installed"
        else
            fatal "Failed to install PulseAudio. Please install it manually:
  brew install pulseaudio"
        fi
    else
        warn "Skipping PulseAudio — audio playback from containers will not work"
        return 1
    fi
    return 0
}

###############################################################################
# Step 4: Fix PulseAudio issues
###############################################################################
fix_pulseaudio() {
    info "Configuring PulseAudio for container audio..."

    # 4a: .dylib vs .so symlink fix
    local modules_dir
    modules_dir="$(brew --prefix pulseaudio)/lib/pulseaudio/modules"
    if [ -d "$modules_dir" ]; then
        local created=0
        for dylib in "$modules_dir"/*.dylib; do
            [ -f "$dylib" ] || continue
            local so="${dylib%.dylib}.so"
            if [ ! -e "$so" ]; then
                ln -s "$(basename "$dylib")" "$so"
                created=$((created + 1))
            fi
        done
        if [ "$created" -gt 0 ]; then
            success "Created $created .so symlinks for PulseAudio modules"
        else
            success "PulseAudio .so symlinks already in place"
        fi
    else
        warn "PulseAudio modules directory not found at $modules_dir"
    fi

    # 4b: Cookie path fix — directory instead of file
    if [ -d "$HOME/.config/pulse/cookie" ]; then
        rmdir "$HOME/.config/pulse/cookie" 2>/dev/null || true
        success "Removed stale pulse cookie directory"
    fi

    # 4c: Enable TCP module in default.pa
    local default_pa
    default_pa="$(brew --prefix pulseaudio)/etc/pulse/default.pa"
    if [ -f "$default_pa" ]; then
        local tcp_line="load-module module-native-protocol-tcp auth-anonymous=1 auth-ip-acl=127.0.0.1;192.168.0.0/16;172.16.0.0/12;10.0.0.0/8"

        if grep -qF "$tcp_line" "$default_pa"; then
            success "TCP module already configured in default.pa"
        elif grep -q "^#.*load-module module-native-protocol-tcp" "$default_pa"; then
            # There's a commented-out line — add our configured line after it
            # Use a temp file for BSD sed compatibility
            local tmpfile
            tmpfile="$(mktemp)"
            sed '/^#.*load-module module-native-protocol-tcp/a\
'"$tcp_line" "$default_pa" > "$tmpfile"
            mv "$tmpfile" "$default_pa"
            success "Enabled TCP module in default.pa"
        elif grep -q "^load-module module-native-protocol-tcp" "$default_pa"; then
            # There's an uncommented line but with different options — replace it
            local tmpfile
            tmpfile="$(mktemp)"
            sed 's|^load-module module-native-protocol-tcp.*|'"$tcp_line"'|' "$default_pa" > "$tmpfile"
            mv "$tmpfile" "$default_pa"
            success "Updated TCP module configuration in default.pa"
        else
            # No existing line — append
            echo "" >> "$default_pa"
            echo "# Added by Neon Hub installer" >> "$default_pa"
            echo "$tcp_line" >> "$default_pa"
            success "Added TCP module to default.pa"
        fi
    else
        warn "PulseAudio default.pa not found at $default_pa"
    fi

    # 4d: Start (or restart) PulseAudio daemon
    info "Starting PulseAudio daemon..."
    if brew services list | grep -q "pulseaudio.*started"; then
        brew services restart pulseaudio &>/dev/null
        success "PulseAudio restarted"
    else
        brew services start pulseaudio &>/dev/null
        success "PulseAudio started"
    fi

    # 4e: Verify TCP module and port
    sleep 2  # Give PA a moment to load modules
    local tcp_ok=0
    local port_ok=0

    if pactl list modules short 2>/dev/null | grep -q "module-native-protocol-tcp"; then
        tcp_ok=1
    fi
    if lsof -iTCP:4713 -sTCP:LISTEN &>/dev/null; then
        port_ok=1
    fi

    if [ "$tcp_ok" -eq 1 ] && [ "$port_ok" -eq 1 ]; then
        success "PulseAudio TCP module loaded, listening on port 4713"
    elif [ "$tcp_ok" -eq 1 ]; then
        warn "TCP module loaded but port 4713 is not listening yet (may need a moment)"
    else
        warn "TCP module not detected — audio may not work from containers"
        warn "Try: brew services restart pulseaudio"
    fi
}

###############################################################################
# Step 5: Prompt for configuration
###############################################################################
prompt_configuration() {
    info "Gathering configuration..."

    # -- mDNS name / common name --
    COMMON_NAME=$(get_input \
        "Choose an mDNS hostname for your Neon Hub.\n\nThis is used for the SSL certificate, nginx, and service discovery.\nIt does NOT change your Mac's hostname." \
        "$DEFAULT_COMMON_NAME")
    if [ -z "$COMMON_NAME" ]; then
        COMMON_NAME="$DEFAULT_COMMON_NAME"
    fi
    success "Hostname: $COMMON_NAME"

    # -- Admin credentials --
    HUB_ADMIN_TOKEN_FILE="${NEON_HOME}/xdg/config/neon/hub_admin.yaml"
    HUB_ADMIN_USERNAME=""
    HUB_ADMIN_PASSWORD=""

    if [ -f "$HUB_ADMIN_TOKEN_FILE" ]; then
        # Reuse existing admin creds so Ansible re-bootstrap is a no-op refresh.
        _admin_creds=$(python3 - "$HUB_ADMIN_TOKEN_FILE" <<'PY'
import json, re, sys
out = {}
with open(sys.argv[1]) as f:
    for line in f:
        m = re.match(r'^(username|password):\s*(.*)\s*$', line)
        if m:
            try: out[m.group(1)] = json.loads(m.group(2))
            except Exception: out[m.group(1)] = m.group(2)
print(out.get('username', ''))
print(out.get('password', ''))
PY
)
        HUB_ADMIN_USERNAME=$(printf '%s\n' "$_admin_creds" | sed -n '1p')
        HUB_ADMIN_PASSWORD=$(printf '%s\n' "$_admin_creds" | sed -n '2p')
        success "Reusing existing admin credentials (${HUB_ADMIN_USERNAME})"
    elif [ -f "$SECRETS_FILE" ]; then
        show_message "An existing Neon Hub install was detected, but no admin credentials file was found at ${HUB_ADMIN_TOKEN_FILE}.

Enter the admin username and password you set previously. If you don't remember them, enter new values — the installer will try to log in first, and if that fails, register a new admin user."
        HUB_ADMIN_USERNAME=$(get_input "Hub admin username:" "$DEFAULT_ADMIN_USER")
        HUB_ADMIN_PASSWORD=$(get_password "Hub admin password (required):")
    else
        HUB_ADMIN_USERNAME=$(get_input \
            "Choose a username for the Hub admin account.\n\nThis is used to log in to the Hub Config UI and manage users." \
            "$DEFAULT_ADMIN_USER")
        HUB_ADMIN_PASSWORD=$(get_password \
            "Set a password for the Hub admin account (${HUB_ADMIN_USERNAME}).\n\nLeave blank to auto-generate a random password.")
    fi

    # Fill defaults
    if [ -z "$HUB_ADMIN_USERNAME" ]; then
        HUB_ADMIN_USERNAME="$DEFAULT_ADMIN_USER"
    fi
    if [ -z "$HUB_ADMIN_PASSWORD" ]; then
        HUB_ADMIN_PASSWORD=$(python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32)))")
        warn "Generated random admin password (will be shown at the end)"
    fi

    # -- Trust self-signed cert --
    TRUST_SELF_SIGNED_CERT="1"
    if get_yesno "Trust the self-signed SSL certificate in the macOS System keychain?\n\nThis lets browsers and curl accept https://*.${COMMON_NAME} without warnings.\n\nYou will be prompted for your password by macOS."; then
        TRUST_SELF_SIGNED_CERT="1"
        success "Will trust self-signed cert in System keychain"
    else
        TRUST_SELF_SIGNED_CERT="0"
        warn "Skipping cert trust — browsers will show SSL warnings"
    fi
}

###############################################################################
# Step 6: Detect timezone
###############################################################################
detect_timezone() {
    info "Detecting timezone..."
    TIMEZONE=""
    if [ -L /etc/localtime ]; then
        TIMEZONE="$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')"
    fi
    if [ -z "$TIMEZONE" ]; then
        TIMEZONE="America/Chicago"
        warn "Could not detect timezone, defaulting to $TIMEZONE"
    else
        success "Timezone: $TIMEZONE"
    fi
}

###############################################################################
# Step 7: Create data directory
###############################################################################
create_data_directory() {
    info "Creating data directory at ${NEON_HOME}..."
    if [ ! -d "$NEON_HOME" ]; then
        sudo mkdir -p "$NEON_HOME"
        sudo chown "$(whoami):staff" "$NEON_HOME"
        success "Created $NEON_HOME"
    else
        # Ensure ownership is correct even if directory exists
        sudo chown "$(whoami):staff" "$NEON_HOME"
        success "$NEON_HOME already exists"
    fi
}

###############################################################################
# Step 8: Create Python venv and install Ansible
###############################################################################
setup_ansible() {
    info "Setting up Python virtual environment..."

    if [ ! -d "$VENV_PATH" ]; then
        python3 -m venv "$VENV_PATH"
        success "Created venv at $VENV_PATH"
    else
        success "Venv already exists at $VENV_PATH"
    fi

    info "Installing Ansible and dependencies..."
    "$VENV_PATH/bin/pip" install --upgrade pip setuptools &>/dev/null
    "$VENV_PATH/bin/pip" install \
        ansible==9.2.0 \
        docker==7.1.0 \
        requests==2.31.0 &>/dev/null
    success "Python packages installed"

    info "Installing Ansible Galaxy requirements..."
    "$VENV_PATH/bin/ansible-galaxy" install -r "${PLAYBOOK_DIR}/requirements.yml" &>/dev/null
    success "Ansible Galaxy roles and collections installed"
}

###############################################################################
# Step 9: Run Ansible playbook
###############################################################################
run_ansible() {
    info "Running Ansible playbook..."
    echo ""
    printf "${BOLD}Installing Neon Hub. This may take some time — take a break and relax.${NC}\n"
    printf "Logs: ${LOG_FILE}\n"
    echo ""

    # Ensure log file exists and is writable
    touch "$LOG_FILE" 2>/dev/null || sudo touch "$LOG_FILE"
    touch "$ANSIBLE_LOG_FILE" 2>/dev/null || sudo touch "$ANSIBLE_LOG_FILE"

    # Build the ansible-playbook command
    local ansible_cmd=(
        "$VENV_PATH/bin/ansible-playbook"
        -i 127.0.0.1,
        -e "common_name=${COMMON_NAME}"
        -e "trust_self_signed_cert=${TRUST_SELF_SIGNED_CERT}"
        -e "hub_admin_username_input=${HUB_ADMIN_USERNAME}"
        -e "hub_admin_password_input=${HUB_ADMIN_PASSWORD}"
        -e "timezone=${TIMEZONE}"
        -e "start_neon_hub_services=1"
        "${ansible_debug[@]}"
        -K
        "${PLAYBOOK_DIR}/hub.yaml"
    )

    export ANSIBLE_CONFIG="${PLAYBOOK_DIR}/ansible.cfg"
    export ANSIBLE_LOG_PATH="$ANSIBLE_LOG_FILE"

    # Use macOS (BSD) script syntax to capture output while showing it live.
    # BSD script: script -q <logfile> <command...>
    # The command is passed as remaining arguments (not via -c like GNU).
    local rc=0
    script -q "$LOG_FILE" "${ansible_cmd[@]}" || rc=$?

    if [ "$rc" -eq 0 ]; then
        echo ""
        success "Neon Hub installed successfully!"
        return 0
    else
        echo ""
        error "Ansible playbook failed (exit code $rc)"
        error "Check logs at: $LOG_FILE"
        error "Ansible log: $ANSIBLE_LOG_FILE"
        return 1
    fi
}

###############################################################################
# Step 10: Post-install summary
###############################################################################
post_install_summary() {
    # Skill-config password: either from secrets file or note it's auto-generated
    local skill_config_pw_display="(see ${SECRETS_FILE})"

    show_message "Your Neon Hub is installed and running!

Web interfaces:

  https://config.${COMMON_NAME}      — Hub Configuration
  https://skill-config.${COMMON_NAME} — Skill Settings
  https://rmq-admin.${COMMON_NAME}   — RabbitMQ Admin
  https://iris-websat.${COMMON_NAME}  — Iris Web Satellite
  https://hana.${COMMON_NAME}        — HANA API

Hub Admin:  ${HUB_ADMIN_USERNAME} / ${HUB_ADMIN_PASSWORD}
Skill Config: neon / ${skill_config_pw_display}

Service passwords are in:
  ${SECRETS_FILE}
Admin token is in:
  ${NEON_HOME}/xdg/config/neon/hub_admin.yaml"

    if [ "$TRUST_SELF_SIGNED_CERT" != "1" ]; then
        show_message "Note: You chose not to trust the self-signed certificate.

The first time you access a web interface, you will need to accept the
SSL warning. In most browsers, click \"Advanced\" then \"Proceed to
${COMMON_NAME}\"."
    fi

    show_message "Congratulations on setting up your Neon Hub on macOS!

To say hello, open https://iris-websat.${COMMON_NAME} and type a message,
or connect a Neon Node app — it will auto-discover this Hub via mDNS.

To stop the stack:
  docker compose -f ${NEON_HOME}/compose/neon-hub.yml down

To start it again:
  docker compose -f ${NEON_HOME}/compose/neon-hub.yml up -d"
}

###############################################################################
# Main
###############################################################################
main() {
    echo ""
    printf "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${NC}\n"
    printf "${BOLD}${CYAN}║          Neon Hub Installer for macOS                ║${NC}\n"
    printf "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${NC}\n"
    echo ""

    # Step 1: Root check
    check_not_root

    # Step 2: Prerequisites
    check_macos_version
    check_docker
    check_homebrew

    # Step 3: Optional dependencies (whiptail first, so PA prompts can use it)
    install_whiptail

    # Welcome message (now that whiptail may be available)
    show_message "Welcome to the Neon Hub installer for macOS!

Neon Hub is a central server for artificial intelligence, powered by
Neon AI. It is designed to be a private, offline, and secure
alternative to cloud-based AI assistants.

This installer will:
  1. Install PulseAudio for container audio
  2. Configure your Hub hostname and admin credentials
  3. Set up a Python environment with Ansible
  4. Deploy the full Neon Hub stack via Docker Compose

Prerequisites (you should already have these):
  - macOS 13 (Ventura) or later
  - Docker Desktop installed and running
  - Homebrew

If you are unsure about any option, press Enter for the default."

    local pa_installed=0
    if install_pulseaudio; then
        pa_installed=1
    fi

    # Step 4: Fix PulseAudio (only if installed)
    if [ "$pa_installed" -eq 1 ] && command -v pulseaudio &>/dev/null; then
        fix_pulseaudio
    fi

    # Step 5: Configuration prompts
    prompt_configuration

    # Step 6: Timezone
    detect_timezone

    # Step 7: Data directory
    create_data_directory

    # Step 8: Python venv + Ansible
    setup_ansible

    # Step 9: Run Ansible
    if run_ansible; then
        # Step 10: Summary
        post_install_summary
    else
        show_message "Installation encountered errors. Please check the logs:

  Install log: ${LOG_FILE}
  Ansible log: ${ANSIBLE_LOG_FILE}

Common issues:
  - Docker Desktop not running or out of disk space
  - Network issues downloading container images
  - Incorrect sudo password when prompted by Ansible

You can re-run this installer after fixing the issue."
        exit 1
    fi
}

main "$@"
