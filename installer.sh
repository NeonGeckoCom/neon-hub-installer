#!/bin/bash

export ANSIBLE_LOG_FILE=/var/log/neon-hub-ansible.log
export LOG_FILE=/var/log/neon-hub-installer.log
export INSTALLER_VENV_NAME="neon-hub-installer"
export OS_RELEASE=/etc/os-release
export USER_ID="$EUID"

# Parse command line arguments
XDG_DIR="/home/neon/xdg"
HOSTNAME="neon-hub.local"
INSTALL_NODE_VOICE_CLIENT=0
INSTALL_NODE_KIOSK=0

# Enable debug/verbosity for Bash and Ansible
if [ "$DEBUG" == "true" ]; then
  set -x
  ansible_debug=(-vvv)
fi

# Function to display a message box
show_message() {
    whiptail --title "Neon Hub Installer" --msgbox "$1" 20 78
}

# Function to get user input
get_input() {
    whiptail --title "Neon Hub Installer" --inputbox "$1" 10 78 "$2" 3>&1 1>&2 2>&3
}

# Function to get password input (hidden). Returns the entered value,
# or an empty string if the user leaves it blank.
get_password() {
    whiptail --title "Neon Hub Installer" --passwordbox "$1" 12 78 3>&1 1>&2 2>&3
}

# Function to get yes/no input
get_yesno() {
    whiptail --title "Neon Hub Installer" --yesno "$1" 10 78 3>&1 1>&2 2>&3
}

# Set up error handling
set -eE
trap 'echo "Error on line $LINENO. Check $LOG_FILE for details." >&2; exit 1' ERR

# Source the common functions - Fix the path to be relative to the script location
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/scripts/common.sh"

# Function to run command, log output, and handle errors
run_step() {
    local step_name=$1
    local command=$2
    echo "Running: $step_name" >> "$LOG_FILE"
    if ! eval "$command" >> "$LOG_FILE" 2>&1; then
        echo "Error in $step_name. Check $LOG_FILE for details." >&2
        show_message "Error during $step_name. Please check the log file at $LOG_FILE for details."
        exit 1
    fi
}

# Run each step
run_step "User detection" detect_user
run_step "OS information gathering" get_os_information
run_step "Required packages installation" required_packages
run_step "Python virtual environment creation" create_python_venv

case $DISTRO_NAME in
ubuntu | Ubuntu)
    export BROWSER_PACKAGE="firefox"
    ;;
debian)
    export BROWSER_PACKAGE="firefox-esr"
    ;;
default)
    export BROWSER_PACKAGE="chromium"
    ;;
esac

# Source the virtualenv before installing Ansible
if [ -f "$VENV_PATH/bin/activate" ]; then
    # shellcheck source=/dev/null
    source "$VENV_PATH/bin/activate"
    run_step "Ansible installation" install_ansible
else
    echo "Error: Virtual environment not found at $VENV_PATH" >&2
    exit 1
fi

# Disable error handling after this section
set +eE
trap - ERR

# Welcome message
show_message "Welcome to the Neon Hub installer! 

Neon Hub is a central server for artificial intelligence, powered by Neon AI®. It is designed to be a private, offline, and secure alternative to cloud-based AI assistants like Alexa, Google Assistant, and Siri. 

This installer will guide you through the process of setting up a Neon Hub on your computer. You will need to have a working internet connection and a computer running Linux. The installer will install all necessary dependencies, set up a Docker environment, and configure Neon Hub to run as services.

If you are unsure about any of the options, you can press enter to use the default value."

# Ask about XDG directory
XDG_DIR_CHOICE=$(whiptail --title "Neon Hub Installer" --menu "Where would you like to store Neon Hub's persistent data?" 15 78 3 \
"1" "/home/neon/xdg (default)" \
"2" "Choose a different location" 3>&1 1>&2 2>&3)

case $XDG_DIR_CHOICE in
    1)
        XDG_DIR="/home/neon/xdg"
        ;;
    2)
        XDG_DIR=$(get_input "Please enter the path to the persistent data directory:" "$XDG_DIR")
        ;;
esac

while [ ! -d "$XDG_DIR" ]; do
    if (get_yesno "The directory $XDG_DIR does not exist. Would you like to create it?" ); then
        mkdir -p "$XDG_DIR"
    else
        XDG_DIR=$(get_input "Please enter the path to the persistent data directory:" "$XDG_DIR")
    fi
done

# Ask about hostname
HOSTNAME_CHOICE=$(whiptail --title "Neon Hub Installer" --menu "Choose a hostname for Neon Hub to use:" 15 78 3 \
"1" "Use default (neon-hub.local)" \
"2" "Use server's existing hostname" \
"3" "Enter a new hostname" 3>&1 1>&2 2>&3)

case $HOSTNAME_CHOICE in
    1)
        HOSTNAME="neon-hub.local"
        ;;
    2)
        HOSTNAME=$(hostname)
        ;;
    3)
        HOSTNAME=$(get_input "Please enter the new hostname:" "$HOSTNAME")
        ;;
esac

INSTALL_NODE_VOICE_CLIENT_CHOICE=$(whiptail --title "Neon Hub Installer" --menu "Install the Neon Node Voice Client? This allows you to treat your Hub as a Node, so you can speak to it directly." 15 78 3 \
"1" "Yes (default)" \
"2" "No" 3>&1 1>&2 2>&3)

case $INSTALL_NODE_VOICE_CLIENT_CHOICE in
    1)
        INSTALL_NODE_VOICE_CLIENT=1
        ;;
    2)
        INSTALL_NODE_VOICE_CLIENT=0
        ;;
esac

INSTALL_NODE_KIOSK_CHOICE=$(whiptail --title "Neon Hub Installer" --menu "Install the Neon Node Kiosk experience? A browser window with the Neon Iris Web Satellite will automatically start in fullscreen each time you boot. Can only choose if you didn't choose to install the Neon Node Voice Client." 15 78 3 \
"1" "No (default)" \
"2" "Yes" 3>&1 1>&2 2>&3)

case $INSTALL_NODE_KIOSK_CHOICE in
    1)
        INSTALL_NODE_KIOSK=0
        ;;
    2)
        INSTALL_NODE_KIOSK=1
        ;;
esac

# Ask for passwords. Empty input → auto-generate.
# Service passwords (SDM, skill-config) are in the secrets file, so we skip
# those prompts on re-runs. Admin credentials aren't in the secrets file, so
# we always prompt — but on a re-run where hub_admin.yaml already exists we
# reuse what's there.
HUB_ADMIN_USERNAME=""
HUB_ADMIN_PASSWORD=""
SDM_PASSWORD=""
SKILL_CONFIG_PASSWORD=""
SECRETS_FILE="${SCRIPT_DIR}/debos/overlays/ansible/neon_hub_secrets.yaml"
HUB_ADMIN_TOKEN_FILE="${XDG_DIR}/config/neon/hub_admin.yaml"

if [ -f "$HUB_ADMIN_TOKEN_FILE" ]; then
    # Reuse existing admin creds so Ansible re-bootstrap is a no-op refresh.
    # Values are written as JSON string scalars (JSON is a subset of YAML).
    # Parse them with stdlib json so escapes round-trip cleanly without
    # requiring PyYAML on the installer host.
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
elif [ -f "$SECRETS_FILE" ]; then
    show_message "An existing Neon Hub install was detected, but no admin credentials file was found at ${HUB_ADMIN_TOKEN_FILE}.\n\nEnter the admin username and password you set previously. If you don't remember them, enter new values — the installer will try to log in first, and if that fails, register a new admin user."
    HUB_ADMIN_USERNAME=$(get_input "Hub admin username:" "neon")
    HUB_ADMIN_PASSWORD=$(get_password "Hub admin password (required):")
else
    HUB_ADMIN_USERNAME=$(get_input "Choose a username for the Hub admin account.\n\nThis is used to log in to the Hub Config UI and manage users." "neon")
    HUB_ADMIN_PASSWORD=$(get_password "Set a password for the Hub admin account (${HUB_ADMIN_USERNAME}).\n\nLeave blank to auto-generate a random password.")
    SDM_PASSWORD=$(get_password "Set a password for the Simple Docker Manager UI (https://manager.${HOSTNAME}).\n\nLeave blank to auto-generate a random password.")
    SKILL_CONFIG_PASSWORD=$(get_password "Set a password for the Skill Config Tool UI (https://skill-config.${HOSTNAME}).\n\nLeave blank to auto-generate a random password.")
fi

# Fill in defaults/generated values up-front so the final dialog can show them
# and so Ansible receives concrete values (not blanks) as extra-vars.
if [ -z "$HUB_ADMIN_USERNAME" ]; then
    HUB_ADMIN_USERNAME="neon"
fi
if [ -z "$HUB_ADMIN_PASSWORD" ]; then
    HUB_ADMIN_PASSWORD=$(python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32)))")
fi

# Installation
echo "Installing Neon Hub. This may take some time, take a break and relax."
echo "You can find installation logs at $LOG_FILE."

hostnamectl set-hostname "$HOSTNAME"
export ANSIBLE_CONFIG=ansible.cfg
script -q -c "ansible-playbook -i 127.0.0.1 -e 'xdg_dir=$XDG_DIR common_name=$HOSTNAME install_neon_node=$INSTALL_NODE_VOICE_CLIENT install_neon_node_gui=$INSTALL_NODE_KIOSK browser_package=$BROWSER_PACKAGE hub_admin_username_input=\"$HUB_ADMIN_USERNAME\" hub_admin_password_input=\"$HUB_ADMIN_PASSWORD\" sdm_password=\"$SDM_PASSWORD\" skill_config_password=\"$SKILL_CONFIG_PASSWORD\"' ${ansible_debug[*]} debos/overlays/ansible/hub.yaml" "$ANSIBLE_LOG_FILE"

if [ "${PIPESTATUS[0]}" -eq 0 ]; then
    show_message "Neon Hub has been successfully installed!"
else
    cat "$ANSIBLE_LOG_FILE" >> "$LOG_FILE"
    if ask_optin; then
        DEBUG_URL="$(curl -sF 'content=<-' https://dpaste.com/api/v2/ <"$LOG_FILE")"
        show_message "An error occurred during installation. The installer logs are available at $DEBUG_URL.
        Need help? Email us this link at support@neon.ai"
    else
        echo -e "Unable to continue the process, please check $LOG_FILE for more details."
        show_message "An error occurred during installation. Please check $LOG_FILE for more details."
    fi
    exit 1
fi

IP=$(hostname -I | awk '{print $1}')

# Final message
show_message "Your secrets are stored in ${SECRETS_FILE}. Please keep this file safe and do not share it. You will need these secrets to connect to your Neon Hub.

Neon Hub is ready to use! To begin, say \"Hey Neon\" and ask a question such as \"What time is it?\" or \"What's the weather like today?\"."

# Web UI passwords to show the user. If they typed one, show it. If they
# left the prompt blank (or it's a re-run where prompts were skipped),
# Ansible wrote a generated value to the secrets file — point them there.
SDM_PW_DISPLAY="${SDM_PASSWORD:-(see ${SECRETS_FILE})}"
SKILL_CONFIG_PW_DISPLAY="${SKILL_CONFIG_PASSWORD:-(see ${SECRETS_FILE})}"

show_message "Your Neon Hub ships with these web interfaces:

- https://config.${HOSTNAME} — Hub configuration
- https://manager.${HOSTNAME} — container management
- https://skill-config.${HOSTNAME} — skill settings

Hub Config:  ${HUB_ADMIN_USERNAME} / ${HUB_ADMIN_PASSWORD}
Docker Mgr:  neon / ${SDM_PW_DISPLAY}
Skill Config: neon / ${SKILL_CONFIG_PW_DISPLAY}

Service passwords are in ${SECRETS_FILE}.
Admin token is in ${HUB_ADMIN_TOKEN_FILE}."

show_message "The first time you access a web interface, you will need to accept the self-signed SSL certificate. In most browsers, click \"Advanced\" then \"Proceed to ${HOSTNAME}\".

Congratulations on setting up your Neon Hub!"
