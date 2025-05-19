# Neon Hub Debos Image Builder

This repository contains the configuration files to build a custom Debian Bookworm image for the "Neon Hub" using `debos`. The resulting image is configured for UEFI boot on amd64 architectures.
The build process is defined in `hub-efi.yaml` and utilizes a series of recipes located in the `recipes/` directory for modularity.

## Prerequisites

- **Docker**: The build script uses Docker to run `debos` in a containerized environment. Ensure Docker is installed and running.
- **`build.sh` script**: The provided `build.sh` script in this directory handles the Docker execution and image preparation.
- **(Optional) `qemu-system-x86_64` & OVMF**: For running or testing the generated image in a virtual machine. `OVMF` provides UEFI firmware for QEMU. _You will need to adjust the recipes to send GUI output to the serial console for this to work properly_.

## Building the Image

1.  Clone this repository.
2.  Ensure you have Docker installed and running.
3.  Make the `build.sh` script executable: `chmod +x build.sh`.
4.  Run the `build.sh` script:

    ```bash
    ./build.sh
    ```

    This script will:

    - Pull the `godebos/debos` Docker image if not already present.
    - Run `debos` inside a Docker container using the `hub-efi.yaml` configuration.
    - The `debos` process (running in Docker) will execute a series of actions defined in `hub-efi.yaml`, including:
      - Downloading the base Debian system (via `recipes/base-debian.yaml`).
      - Installing necessary packages, including KDE Plasma Desktop and common firmware (via recipes like `recipes/kde-plasma.yaml` and `recipes/firmware-common.yaml`).
      - Applying custom overlays from the `overlays/` directory at various stages.
      - Partitioning and formatting a disk image (via `recipes/efi-boot.yaml`).
      - Deploying the filesystem to the image.
      - Installing and configuring the GRUB UEFI bootloader.
      - Performing system configuration, including user setup (via `recipes/neon-user-config.yaml`), SSH, services, and installing Neon Hub specific components (via `recipes/neon-hub.yaml`).
      - Cleaning up the image (via `recipes/cleanup.yaml`).
    - Rename the output image to `neon-hub-amd64_{timestamp}.img`.
    - Compress the image using gzip, resulting in `neon-hub-amd64_{timestamp}.img.gz`.

5.  The resulting compressed image file (`neon-hub-amd64_{timestamp}.img.gz`) will be created in the current directory.

## Image Features

The generated image includes:

- **OS**: Debian Bookworm (amd64)
- **Desktop Environment**: KDE Plasma
- **Bootloader**: GRUB for UEFI systems
- **Kernel**: Standard Debian `linux-image-amd64`
- **Networking**: `NetworkManager` enabled for network configuration.
- **Services**:
  - `sshd`: OpenSSH server enabled (Password authentication allowed).
  - `sddm`: Simple Desktop Display Manager for KDE Plasma.
  - `systemd-resolved`: For DNS resolution.
  - `systemd-timesyncd`: For time synchronization.
- **Default User**:
  - Username: `neon` (configurable in `hub-efi.yaml`)
  - Password: `neon` (configurable in `hub-efi.yaml`)
  - Has `sudo` privileges without requiring a password.
- **Auto-login**: Configured for automatic login for the `neon` user on the serial console (via `overlays/auto-login`).
- **Hostname**: Set to `neon-hub` (configurable in `hub-efi.yaml`).
- **Filesystem**: EXT4 root filesystem with a VFAT EFI System Partition (ESP).
- **Key Installed Packages**: Includes `sudo`, `openssh-server`, KDE Plasma desktop environment, `vim`, `bash-completion`, `curl`, `wget`, `htop`, common firmware packages, and Neon Hub specific applications.
- **Neon Hub**: Includes specific configurations and applications for the Neon Hub.

## Running/Testing with QEMU (Example)

To test the image using QEMU with UEFI firmware (OVMF), you first need to decompress the image:

```bash
gunzip neon-hub-amd64_*.img.gz
```

Then, you might use a command like this (ensure you have `qemu-system-x86_64` and an OVMF firmware file installed, e.g., `/usr/share/OVMF/OVMF_CODE.fd`):

```bash
qemu-system-x86_64 \
    -m 2G \
    -machine q35,accel=kvm \
    -cpu host \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
    -drive if=pflash,format=raw,file=OVMF_VARS.fd \ # Create an empty file first: dd if=/dev/zero of=OVMF_VARS.fd bs=1M count=64
    -drive file=neon-hub-amd64_*.img,format=raw,if=virtio \ # Replace * with the actual timestamp
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0 \
    -nographic # Or use -serial stdio depending on your needs
```

_Note: Create a writable copy of the OVMF variables file (`OVMF_VARS.fd`) for QEMU._
_The image name will be `neon-hub-amd64_{timestamp}.img`after decompression. You can then SSH into the running VM using`ssh neon@localhost -p 2222`.\_

## Configuration

The main configuration is defined in `hub-efi.yaml`. This file orchestrates the build by including various recipes from the `recipes/` directory and applying overlays from the `overlays/` directory. You can modify `hub-efi.yaml` and the individual recipe files to change packages, image size, partitioning, user setup, and other aspects of the build process. Overlays in the `overlays/` directory provide custom files and configurations applied during the build.
