#!/bin/bash

export ANSIBLE_LOG_FILE=/var/log/neon-hub-ansible.log
export LOG_FILE=/var/log/neon-hub-installer.log
export INSTALLER_VENV_NAME="neon-hub-installer"
export OS_RELEASE=/etc/os-release
export USER_ID="$EUID"

# Parse command line arguments
NON_INTERACTIVE=false
XDG_DIR="/home/neon/xdg"
HOSTNAME="neon-hub.local"
INSTALL_NODE_VOICE_CLIENT=1
INSTALL_NODE_KIOSK=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --non-interactive)
      NON_INTERACTIVE=true
      shift
      ;;
    --xdg-dir)
      XDG_DIR="$2"
      shift 2
      ;;
    --hostname)
      HOSTNAME="$2"
      shift 2
      ;;
    --install-node)
      INSTALL_NODE_VOICE_CLIENT="$2"
      shift 2
      ;;
    --install-kiosk)
      INSTALL_NODE_KIOSK="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Enable debug/verbosity for Bash and Ansible
if [ "$DEBUG" == "true" ]; then
  set -x
  ansible_debug=(-vvv)
fi

# Function to display a message box
show_message() {
    if [ "$NON_INTERACTIVE" = true ]; then
        echo "Neon Hub Installer: $1"
    else
        whiptail --title "Neon Hub Installer" --msgbox "$1" 20 78
    fi
}

# Function to get user input
get_input() {
    if [ "$NON_INTERACTIVE" = true ]; then
        echo "$2"
    else
        whiptail --title "Neon Hub Installer" --inputbox "$1" 10 78 "$2" 3>&1 1>&2 2>&3
    fi
}

# Function to get yes/no input
get_yesno() {
    if [ "$NON_INTERACTIVE" = true ]; then
        return 0
    else
        whiptail --title "Neon Hub Installer" --yesno "$1" 10 78 3>&1 1>&2 2>&3
    fi
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

if [ "$NON_INTERACTIVE" = false ]; then
    # Welcome message
    show_message "Welcome to the Neon Hub installer! 

    Neon Hub is a central server for artificial intelligence, powered by Neon AI®. It is designed to be a private, offline, and secure alternative to cloud-based AI assistants like Alexa, Google Assistant, and Siri. 

    This installer will guide you through the process of setting up a Neon Hub on your computer. You will need to have a working internet connection and a computer running Linux. The installer will install all necessary dependencies, set up a Docker environment, and configure Neon Hub to run as services.

    If you are unsure about any of the options, you can press enter to use the default value."
fi

# Create XDG directory if it doesn't exist
if [ ! -d "$XDG_DIR" ]; then
    mkdir -p "$XDG_DIR"
fi

# Installation
echo "Installing Neon Hub. This may take some time, take a break and relax."
echo "You can find installation logs at $LOG_FILE."

hostnamectl set-hostname "$HOSTNAME"
export ANSIBLE_CONFIG=ansible.cfg
script -q -c "ansible-playbook -i 127.0.0.1 -e 'xdg_dir=$XDG_DIR common_name=$HOSTNAME install_neon_node=$INSTALL_NODE_VOICE_CLIENT install_neon_node_gui=$INSTALL_NODE_KIOSK browser_package=$BROWSER_PACKAGE' ${ansible_debug[*]} ansible/hub.yaml" "$ANSIBLE_LOG_FILE"

if [ "${PIPESTATUS[0]}" -eq 0 ]; then
    show_message "Neon Hub has been successfully installed!"
else
    cat "$ANSIBLE_LOG_FILE" >> "$LOG_FILE"
    if [ "$NON_INTERACTIVE" = true ]; then
        echo "An error occurred during installation. Please check $LOG_FILE for more details."
    else
        if ask_optin; then
            DEBUG_URL="$(curl -sF 'content=<-' https://dpaste.com/api/v2/ <"$LOG_FILE")"
            show_message "An error occurred during installation. The installer logs are available at $DEBUG_URL.
            Need help? Email us this link at support@neon.ai"
        else
            echo -e "Unable to continue the process, please check $LOG_FILE for more details."
            show_message "An error occurred during installation. Please check $LOG_FILE for more details."
        fi
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
