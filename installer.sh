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

# Installation
echo "Installing Neon Hub. This may take some time, take a break and relax."
echo "You can find installation logs at $LOG_FILE."

hostnamectl set-hostname "$HOSTNAME"
export ANSIBLE_CONFIG=ansible.cfg
script -q -c "ansible-playbook -i 127.0.0.1 -e 'xdg_dir=$XDG_DIR common_name=$HOSTNAME install_neon_node=$INSTALL_NODE_VOICE_CLIENT install_neon_node_gui=$INSTALL_NODE_KIOSK browser_package=$BROWSER_PACKAGE' ${ansible_debug[*]} debos/overlays/ansible/hub.yaml" "$ANSIBLE_LOG_FILE"

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
show_message "Your message queue secrets and Neon Node secret are available in ${PWD}/ansible/neon_hub_secrets.yaml. Please keep these secrets safe and do not share them with anyone. You will need these secrets to connect to your Neon Hub.

Neon Hub is ready to use! To begin, say \"Hey Neon\" and ask a question such as \"What time is it?\" or \"What's the weather like today?\"."

show_message "You can check your Neon Hub services by navigating to https://yacht.${HOSTNAME} in your preferred web browser. It is also available at http://$IP:8000. The default credentials are admin@yacht.local:pass.

Please note that the first time you access the web interface, you will need to accept the self-signed SSL certificate. You can do this in most browsers by clicking \"Advanced\" and then \"Proceed to ${HOSTNAME}\"."

show_message "Congratulations on setting up your Neon Hub! Enjoy your new AI server!"
