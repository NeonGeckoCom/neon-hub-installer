#!/bin/bash

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

# shellcheck source=scripts/common.sh
source scripts/common.sh

set -eE
detect_user
get_os_information
required_packages
create_python_venv
install_ansible
set +eE

# Welcome message
show_message "Welcome to the Neon Hub installer! 

Neon Hub is central server for artificial intelligence, powered by Neon.AI. It is designed to be a private, offline, and secure alternative to cloud-based AI assistants like Alexa, Google Assistant, and Siri. 

This installer will guide you through the process of setting up a Neon Hub on your computer. You will need to have a working internet connection and a computer running Linux. The installer will install all necessary dependencies, set up a Docker environment, and configure Neon Hub to run as services.

If you are unsure about any of the options, you can press enter to use the default value."

# Set default values
XDG_DIR=""
HOSTNAME=""

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
        mkdir -p $XDG_DIR
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

# # Simulating installation process
# {
#     for i in {1..100}; do
#         sleep 0.1
#         echo $i
#     done
# } | whiptail --gauge "Installing Neon Hub... Please wait." 6 50 0

# Installation
echo "Installing Neon Hub. This may take some time, take a break and relax."
export ANSIBLE_CONFIG=ansible.cfg
ansible-playbook -i 127.0.0.1 -e "xdg_dir=$XDG_DIR common_name=$HOSTNAME" "${ansible_debug[@]}" playbook.yml

if [ "${PIPESTATUS[0]}" -eq 0 ]; then
    show_message "Neon Hub has been successfully installed!"
else
    cat "$ANSIBLE_LOG_FILE" >> "$LOG_FILE"
    if [ "$(ask_optin)" -eq 0 ]; then
        DEBUG_URL="$(curl -sF 'content=<-' https://dpaste.com/api/v2/ <"$LOG_FILE")"
        show_message "An error occurred during installation. The installer logs are available at $DEBUG_URL.
        Need help? Email us this link at support@neon.ai"
    else
        show_message "An error occurred during installation. Please check $LOG_FILE for more details."
    fi

    exit 1
fi

IP=$(hostname -I | awk '{print $1}')

# Final message
show_message "Your message queue secrets and Neon Node secret are available in ${PWD}/neon_hub_secrets.yaml. Please keep these secrets safe and do not share them with anyone. You will need these secrets to connect to your Neon Hub.

Neon Hub is ready to use! To begin, say \"Hey Neon\" and ask a question such as \"What time is it?\" or \"What's the weather like today?\". 

You can customize your Neon Hub by navigating to https://${HOSTNAME} in your preferred web browser. It is also available at https://$IP.

Please note that the first time you access the web interface, you will need to accept the self-signed SSL certificate. You can do this in most browsers by clicking \"Advanced\" and then \"Proceed to ${HOSTNAME}\".

Congratulations on setting up your Neon Hub! Enjoy your new AI server!"
