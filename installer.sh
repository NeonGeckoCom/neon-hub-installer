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

# Ask for passwords. Empty input → auto-generate at install time.
# Skipped entirely on re-runs where the secrets file already exists.
HUB_ADMIN_USERNAME=""
HUB_ADMIN_PASSWORD=""
SDM_PASSWORD=""
SKILL_CONFIG_PASSWORD=""
SECRETS_FILE="${SCRIPT_DIR}/debos/overlays/ansible/neon_hub_secrets.yaml"
HUB_ADMIN_TOKEN_FILE="${XDG_DIR}/config/neon/hub_admin.yaml"
if [ ! -f "$SECRETS_FILE" ]; then
    HUB_ADMIN_USERNAME=$(get_input "Choose a username for the Hub admin account.\n\nThis is used to log in to the Hub Config UI and manage users." "neon")
    HUB_ADMIN_PASSWORD=$(get_password "Set a password for the Hub admin account (${HUB_ADMIN_USERNAME}).\n\nLeave blank to auto-generate a random password.")
    SDM_PASSWORD=$(get_password "Set a password for the Simple Docker Manager UI (https://manager.${HOSTNAME}).\n\nLeave blank to auto-generate a random password.")
    SKILL_CONFIG_PASSWORD=$(get_password "Set a password for the Skill Config Tool UI (https://skill-config.${HOSTNAME}).\n\nLeave blank to auto-generate a random password.")
fi

# Installation
echo "Installing Neon Hub. This may take some time, take a break and relax."
echo "You can find installation logs at $LOG_FILE."

hostnamectl set-hostname "$HOSTNAME"
export ANSIBLE_CONFIG=ansible.cfg
script -q -c "ansible-playbook -i 127.0.0.1 -e 'xdg_dir=$XDG_DIR common_name=$HOSTNAME install_neon_node=$INSTALL_NODE_VOICE_CLIENT install_neon_node_gui=$INSTALL_NODE_KIOSK browser_package=$BROWSER_PACKAGE hub_admin_username=\"$HUB_ADMIN_USERNAME\" hub_admin_password=\"$HUB_ADMIN_PASSWORD\" sdm_password=\"$SDM_PASSWORD\" skill_config_password=\"$SKILL_CONFIG_PASSWORD\"' ${ansible_debug[*]} debos/overlays/ansible/hub.yaml" "$ANSIBLE_LOG_FILE"

if [ "${PIPESTATUS[0]}" -eq 0 ]; then
    # Register the Hub admin user with HANA now that services are running.
    # Uses the admin username/password from the earlier prompt (or generated).
    # Generates a password if the user left it blank.
    if [ -z "$HUB_ADMIN_PASSWORD" ]; then
        HUB_ADMIN_PASSWORD=$(python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32)))")
    fi
    if [ -z "$HUB_ADMIN_USERNAME" ]; then
        HUB_ADMIN_USERNAME="neon"
    fi

    HANA_URL="http://localhost:8082"
    ADMIN_REGISTER_OK=false

    # Wait for HANA to be ready (up to 60 seconds)
    for i in $(seq 1 12); do
        if curl -sf "${HANA_URL}/status" > /dev/null 2>&1; then
            break
        fi
        sleep 5
    done

    # Register the admin user
    REGISTER_RESPONSE=$(curl -sf -X POST "${HANA_URL}/auth/register" \
        -H "Content-Type: application/json" \
        -d "{\"username\": \"${HUB_ADMIN_USERNAME}\", \"password\": \"${HUB_ADMIN_PASSWORD}\"}" 2>&1) && ADMIN_REGISTER_OK=true

    if [ "$ADMIN_REGISTER_OK" = true ]; then
        # Log in to get tokens
        LOGIN_RESPONSE=$(curl -sf -X POST "${HANA_URL}/auth/login" \
            -H "Content-Type: application/json" \
            -d "{\"username\": \"${HUB_ADMIN_USERNAME}\", \"password\": \"${HUB_ADMIN_PASSWORD}\", \"token_name\": \"hub-admin\"}")

        ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null)
        REFRESH_TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['refresh_token'])" 2>/dev/null)

        if [ -n "$ACCESS_TOKEN" ] && [ -n "$REFRESH_TOKEN" ]; then
            # Grant admin permissions
            USER_DATA=$(curl -sf -X POST "${HANA_URL}/user/get" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                -d "{\"username\": \"${HUB_ADMIN_USERNAME}\"}")

            UPDATED_USER=$(echo "$USER_DATA" | python3 -c "
import sys, json
user = json.load(sys.stdin)
user['permissions'] = {'klat': 20, 'core': 30, 'diana': 30, 'users': 30, 'node': 20, 'hub': 30, 'llm': 20}
json.dump({'user': user}, sys.stdout)
" 2>/dev/null)

            curl -sf -X POST "${HANA_URL}/user/update" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                -d "$UPDATED_USER" > /dev/null 2>&1

            # Re-login to get tokens with updated permissions
            LOGIN_RESPONSE=$(curl -sf -X POST "${HANA_URL}/auth/login" \
                -H "Content-Type: application/json" \
                -d "{\"username\": \"${HUB_ADMIN_USERNAME}\", \"password\": \"${HUB_ADMIN_PASSWORD}\", \"token_name\": \"hub-admin\"}")

            REFRESH_TOKEN=$(echo "$LOGIN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['refresh_token'])" 2>/dev/null)

            # Save the admin refresh token
            mkdir -p "$(dirname "$HUB_ADMIN_TOKEN_FILE")"
            python3 -c "
import yaml
with open('${HUB_ADMIN_TOKEN_FILE}', 'w') as f:
    yaml.dump({'username': '${HUB_ADMIN_USERNAME}', 'refresh_token': '${REFRESH_TOKEN}'}, f)
" 2>/dev/null
            chmod 600 "$HUB_ADMIN_TOKEN_FILE"
            echo "Hub admin user '${HUB_ADMIN_USERNAME}' registered with HANA." >> "$LOG_FILE"
        else
            echo "Warning: Failed to obtain admin tokens from HANA." >> "$LOG_FILE"
        fi
    else
        echo "Warning: Failed to register admin user with HANA. You may need to register manually." >> "$LOG_FILE"
    fi

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

# Extract the web UI passwords to show them to the user.
SDM_PW_DISPLAY="(see ${SECRETS_FILE})"
SKILL_CONFIG_PW_DISPLAY="(see ${SECRETS_FILE})"
if [ -f "$SECRETS_FILE" ]; then
    SDM_PW_DISPLAY=$(python3 -c "import yaml; print(yaml.safe_load(open('${SECRETS_FILE}'))['users']['simple_docker_manager']['password'])" 2>/dev/null || echo "(see ${SECRETS_FILE})")
    SKILL_CONFIG_PW_DISPLAY=$(python3 -c "import yaml; print(yaml.safe_load(open('${SECRETS_FILE}'))['users']['neon_skill_config']['password'])" 2>/dev/null || echo "(see ${SECRETS_FILE})")
fi

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
