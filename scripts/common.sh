#!/bin/env bash
# Functions borrowed from or inspired by https://github.com/OpenVoiceOS/ovos-installer/blob/main/utils/common.sh

# Format the "done" and "fail" strings
done_format="\e[32mdone\e[0m"
fail_format="\e[31mfail\e[0m"

# This function ask user agreement on uploading the content of
# ovos-installer.log on https://dpaste.com. Without the user
# agreement this could lead to security infringement.
function ask_optin() {
    while true; do
        read -rp "Upload the log on https://dpaste.com website? (yes/no) " yn
        case $yn in
        [Yy]*)
            return 0
            ;;
        [Nn]*)
            echo -e "Unable to continue the process, please check $LOG_FILE for more details."
            exit 1
            ;;
        *) echo -e "Please answer (y)es or (n)o." ;;
        esac
    done
}

# Detect information about the user running the installer.
# Installer must be executed with super privileges but either
# "root" or "sudo" can run this script, we need to know whom.
function detect_user() {
    if [ "$USER_ID" -ne 0 ]; then
        echo -e "[$fail_format] This script must be run as root or with sudo\n"
        exit 1
    fi

    # Check for sudo or root user
    if [ -n "$SUDO_USER" ]; then
        # sudo user
        export RUN_AS="$SUDO_USER"
        export RUN_AS_UID="$SUDO_UID"
    else
        # root user
        export RUN_AS="$USER"
        export RUN_AS_UID="$EUID"
    fi
    RUN_AS_HOME=$(eval echo ~"$RUN_AS")
    export RUN_AS_HOME
    export VENV_PATH="${RUN_AS_HOME}/.venvs/${INSTALLER_VENV_NAME}"
}

# Retrieve operating system information based on standard /etc/os-release
# and Python command. This is used to display information to the user
# about the platform where the installer is running on and where Neon Hub is
# going to be installed.
function get_os_information() {
    echo -ne "➤ Retrieving OS information... "
    if [ -f "$OS_RELEASE" ]; then
        ARCH="$(uname -m 2>>"$LOG_FILE")"
        KERNEL="$(uname -r 2>>"$LOG_FILE")"
        PYTHON="$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[0:2])))' 2>>"$LOG_FILE")"

        # shellcheck source=/etc/os-release
        source "$OS_RELEASE"

        export DISTRO_NAME="$ID"
        export ARCH KERNEL PYTHON
    else
        # Mostly if the detected system is not a Linux OS
        uname 2>>"$LOG_FILE"
    fi
    echo -e "[$done_format]"
}

# Install packages required by the installer based on retrieved information
# from get_os_information() function. If the operating system is not supported then
# the installer will exit with a message.
function required_packages() {
    echo -ne "➤ Validating installer package requirements... "

    case "$DISTRO_NAME" in
    debian | ubuntu | raspbian | linuxmint | zorin)
        UPDATE=1 apt_ensure python3 python3-dev python3-pip python3-venv whiptail jq &>>"$LOG_FILE"
        ;;
    fedora)
        echo "Neon Hub only supports Debian-based distributions at the moment." | tee -a "$LOG_FILE"
        exit 1
        # dnf install -y python3 python3-devel python3-pip python3-virtualenv newt jq &>>"$LOG_FILE"
        ;;
    almalinux | rocky | centos)
        echo "Neon Hub only supports Debian-based distributions at the moment." | tee -a "$LOG_FILE"
        exit 1
        # dnf install -y python3 python3-devel python3-pip newt jq &>>"$LOG_FILE"
        ;;
    opensuse-tumbleweed | opensuse-leap | opensuse-slowroll)
        echo "Neon Hub only supports Debian-based distributions at the moment." | tee -a "$LOG_FILE"
        exit 1 
        # zypper install --no-recommends -y python3 python3-devel python3-pip python3-rpm newt jq &>>"$LOG_FILE"
        ;;
    arch | manjaro | endeavouros)
        echo "Neon Hub only supports Debian-based distributions at the moment." | tee -a "$LOG_FILE"
        exit 1
        # pacman -Sy --noconfirm python python-pip python-virtualenv libnewt jq &>>"$LOG_FILE"
        ;;
    *)
        echo -e "[$fail_format]"
        echo "Operating system not supported." | tee -a "$LOG_FILE"
        exit 1
        ;;
    esac
    echo -e "[$done_format]"
}

# Create the installer Python virtual environment and update pip and
# setuptools package.Permissions on the virtual environment are set
# to match the target user.
function create_python_venv() {
    echo -ne "➤ Creating installer Python virtualenv... "

    python3 -m venv "$VENV_PATH" &>>"$LOG_FILE"

    # shellcheck source=/dev/null
    source "$VENV_PATH/bin/activate"

    if [ "$USE_UV" == "true" ]; then
        export PIP_COMMAND="uv pip"
        if ! command -v uv &>>"$LOG_FILE"; then
            pip3 install "uv>=0.4.10" &>>"$LOG_FILE"
        fi
    else
        export PIP_COMMAND="pip3"
    fi

    $PIP_COMMAND install --upgrade pip setuptools &>>"$LOG_FILE"
    chown "$RUN_AS":"$(id -ng "$RUN_AS")" "$VENV_PATH" "${RUN_AS_HOME}/.venvs" &>>"$LOG_FILE"
    echo -e "[$done_format]"
}

# Install Ansible into the new Python virtual environment and install the
# Ansible's collections required by the Ansible playbook as well. These
# collections will be installed under the /root/.ansible directory.
function install_ansible() {
    echo -ne "➤ Installing Ansible requirements in Python virtualenv... "
    ANSIBLE_VERSION="9.2.0"
    $PIP_COMMAND install ansible=="$ANSIBLE_VERSION" docker==7.1.0 requests==2.31.0 &>>"$LOG_FILE"
    ansible-galaxy install -r ansible/requirements.yml &>>"$LOG_FILE"
    echo -e "[$done_format]"
}

# Checks to see if apt-based packages are installed and installs them if needed.
# The main reason to use this over normal apt install is that it avoids sudo if
# we already have all requested packages.
# Args:
#     *ARGS : one or more requested packages
# Environment:
#     UPDATE : if this is populated also runs and apt update
# Example:
#     apt_ensure git curl htop
function apt_ensure() {
    # Note the $@ is not actually an array, but we can convert it to one
    # https://linuxize.com/post/bash-functions/#passing-arguments-to-bash-functions
    ARGS=("$@")
    MISS_PKGS=()
    HIT_PKGS=()
    _SUDO=""
    if [ "$(whoami)" != "root" ]; then
        # Only use the sudo command if we need it (i.e. we are not root)
        _SUDO="sudo "
    fi
    for PKG_NAME in "${ARGS[@]}"; do
        # Check if the package is already installed or not
        if dpkg-query -W -f='${Status}' "$PKG_NAME" 2>/dev/null | grep -q "install ok installed"; then
            echo "Already have PKG_NAME='$PKG_NAME'"
            HIT_PKGS+=("$PKG_NAME")
        else
            echo "Do not have PKG_NAME='$PKG_NAME'"
            MISS_PKGS+=("$PKG_NAME")
        fi
    done
    # Install the packages if any are missing
    if [ "${#MISS_PKGS[@]}" -gt 0 ]; then
        if [ "${UPDATE}" != "" ]; then
            $_SUDO apt update -y
        fi
        DEBIAN_FRONTEND=noninteractive $_SUDO apt install --no-install-recommends -y "${MISS_PKGS[@]}"
    else
        echo "No missing packages"
    fi
}
