#!/bin/bash
# Simple Neon Hub ISO Builder
# Based on Debian Live Manual examples

set -e

# Configuration variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VERSION=$(cat ${SCRIPT_DIR}/version.txt 2>/dev/null || echo "0.1.0")
DATE=$(date +%Y%m%d)
IMAGE_NAME="neon-hub-server-${VERSION}-${DATE}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    local level=$1
    local message=$2
    local color=$NC
    
    case $level in
        INFO) color=$GREEN ;;
        WARNING) color=$YELLOW ;;
        ERROR) color=$RED ;;
    esac
    
    echo -e "${color}[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $message${NC}"
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    log "ERROR" "This script must be run as root"
    exit 1
fi

# Install required packages - matching Debian Live Manual requirements
log "INFO" "Installing required packages..."
apt-get update
apt-get install -y live-build debootstrap squashfs-tools xorriso isolinux syslinux-common

# Create build directory
BUILD_DIR="${SCRIPT_DIR}/build"
log "INFO" "Creating build directory at ${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Clean any previous build
if [ -d "config" ]; then
    log "INFO" "Cleaning previous build..."
    lb clean
fi

# Initialize the config - using a minimal configuration matching the manual
log "INFO" "Initializing live-build configuration..."
lb config \
--distribution bookworm \
--mirror-bootstrap "http://deb.debian.org/debian/" \
--mirror-chroot "http://deb.debian.org/debian/" \
--mirror-binary "http://deb.debian.org/debian/" \
--mirror-chroot-security "http://security.debian.org/debian-security/" \
--debootstrap-options "--include=coreutils,debian-archive-keyring" \
--architectures amd64 \
--binary-images iso-hybrid \
--debian-installer-distribution bookworm \
--debian-installer live \
--bootstrap-include coreutils,debian-archive-keyring

# Create directory structure
log "INFO" "Creating directory structure..."
mkdir -p config/package-lists
mkdir -p config/includes.chroot/etc/skel
mkdir -p config/includes.chroot/usr/local/bin
mkdir -p config/includes.chroot/usr/share/neon

# Create package lists
log "INFO" "Creating package lists..."
# Standard Debian system
echo '! Packages Priority standard' > config/package-lists/standard.list.chroot
echo "debian-archive-keyring" > config/package-lists/keyring.list.chroot

# KDE desktop environment
echo "task-kde-desktop" > config/package-lists/desktop.list.chroot

# Neon Hub requirements
echo "firefox-esr openssh-client rsync git curl wget whiptail jq python3 python3-dev python3-pip python3-venv python3-virtualenv build-essential libpulse-dev portaudio19-dev" > config/package-lists/neon-requirements.list.chroot

# Copy Neon Hub files
log "INFO" "Copying Neon Hub files..."
if [ -d "${SCRIPT_DIR}/ansible" ]; then
    rsync -av "${SCRIPT_DIR}/ansible" config/includes.chroot/usr/share/neon/
fi
if [ -d "${SCRIPT_DIR}/scripts" ]; then
    rsync -av "${SCRIPT_DIR}/scripts" config/includes.chroot/usr/share/neon/
fi
if [ -f "${SCRIPT_DIR}/installer.sh" ]; then
    cp "${SCRIPT_DIR}/installer.sh" config/includes.chroot/usr/local/bin/
    chmod +x config/includes.chroot/usr/local/bin/installer.sh
fi
if [ -f "${SCRIPT_DIR}/version.txt" ]; then
    cp "${SCRIPT_DIR}/version.txt" config/includes.chroot/usr/share/neon/
fi

# Create environment file with defaults
cat > config/includes.chroot/usr/share/neon/defaults.env << EOF
# Default values for Neon Hub installation
export BROWSER_PACKAGE="firefox-esr"
export XDG_DIR="/home/neon/xdg"
export HOSTNAME="neon-hub.local"
export INSTALL_NODE_VOICE_CLIENT=0
export INSTALL_NODE_KIOSK=0
EOF

# Create desktop shortcut for installer
mkdir -p config/includes.chroot/etc/skel/Desktop
cat > config/includes.chroot/etc/skel/Desktop/neon-installer.desktop << EOF
[Desktop Entry]
Name=Install Neon Hub
Comment=Install Neon Hub to your system
Exec=sudo /usr/local/bin/installer.sh
Icon=system-software-install
Terminal=true
Type=Application
Categories=System;
EOF
chmod +x config/includes.chroot/etc/skel/Desktop/neon-installer.desktop

# Create a README file
cat > config/includes.chroot/etc/skel/Desktop/README.txt << EOF
Neon Hub Installer
Version: ${VERSION}
Build Date: ${DATE}

This ISO contains the Neon Hub installation system.

To install Neon Hub:
1. Double-click the "Install Neon Hub" shortcut on the desktop
2. Follow the installation instructions

Default configuration:
- Browser: firefox-esr
- Data directory: /home/neon/xdg
- Hostname: neon-hub.local
- Voice client: Disabled
- Kiosk mode: Disabled

For more information, visit: https://neongeckocom.github.io/neon-hub-installer
EOF

# Build the image
log "INFO" "Building the image. This may take some time..."
lb build 2>&1 | tee "${SCRIPT_DIR}/build.log"

# Check if build succeeded
if [ -f "${BUILD_DIR}/live-image-amd64.hybrid.iso" ]; then
    # Create output directory and move the ISO
    mkdir -p "${SCRIPT_DIR}/output"
    mv "${BUILD_DIR}/live-image-amd64.hybrid.iso" "${SCRIPT_DIR}/output/${IMAGE_NAME}.iso"
    
    # Generate checksums
    cd "${SCRIPT_DIR}/output"
    sha256sum "${IMAGE_NAME}.iso" > "${IMAGE_NAME}.sha256sum"
    
    log "INFO" "ISO created successfully: ${SCRIPT_DIR}/output/${IMAGE_NAME}.iso"
    ls -lh "${SCRIPT_DIR}/output/${IMAGE_NAME}.iso"
else
    log "ERROR" "Failed to build ISO. Check build.log for details."
    exit 1
fi

log "INFO" "Build completed successfully."
