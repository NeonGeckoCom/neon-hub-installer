# Neon Hub Debos Image Builder

This repository contains the configuration files to build a custom Debian Bookworm image for the "Neon Hub" using `debos`. The resulting image is configured for UEFI boot on amd64 architectures.

## Prerequisites

*   **`debos`**: The Debian OS builder tool. Installation instructions can be found in the [debos documentation](https://github.com/go-debos/debos).
*   **(Optional) `qemu-system-x86_64` & OVMF**: For running or testing the generated image in a virtual machine. `OVMF` provides UEFI firmware for QEMU.

## Building the Image

1.  Clone this repository.
2.  Ensure you have `debos` installed and its dependencies met.
3.  Run `debos` using the provided YAML configuration file:

    ```bash
    sudo debos hub-efi.yaml # sudo can be omitted if your user is in the kvm group
    ```

    This command will:
    *   Download the base Debian system (`debootstrap`).
    *   Install necessary packages (`apt`).
    *   Apply custom overlays (`overlay`).
    *   Partition and format a disk image (`image-partition`).
    *   Deploy the filesystem to the image (`filesystem-deploy`).
    *   Install and configure the GRUB UEFI bootloader.
    *   Perform system configuration (user setup, SSH, services).

4.  The resulting image file (`neon-hub-amd64_{timestamp}.img` by default) will be created in the current directory.

## Image Features

The generated image includes:

*   **OS**: Debian Bookworm (amd64)
*   **Bootloader**: GRUB for UEFI systems
*   **Kernel**: Standard Debian `linux-image-amd64`
*   **Networking**: `NetworkManager` enabled for network configuration.
*   **Services**:
    *   `sshd`: OpenSSH server enabled (Password authentication allowed).
    *   `systemd-resolved`: For DNS resolution.
    *   `systemd-timesyncd`: For time synchronization.
*   **Default User**:
    *   Username: `neon`
    *   Password: `neon`
    *   Has `sudo` privileges without requiring a password.
*   **Auto-login**: Configured for automatic login for the `neon` user on the serial console.
*   **Hostname**: Set to `neon-hub`.
*   **Filesystem**: EXT4 root filesystem with a VFAT EFI System Partition (ESP).
*   **Installed Packages**: Includes `sudo`, `openssh-server`, `vim`, `bash-completion`, `curl`, `wget`, `htop`, etc.

## Running/Testing with QEMU (Example)

To test the image using QEMU with UEFI firmware (OVMF), you might use a command like this (ensure you have `qemu-system-x86_64` and an OVMF firmware file installed, e.g., `/usr/share/OVMF/OVMF_CODE.fd`):

```bash
qemu-system-x86_64 \
    -m 2G \
    -machine q35,accel=kvm \
    -cpu host \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
    -drive if=pflash,format=raw,file=OVMF_VARS.fd \ # Create an empty file first: dd if=/dev/zero of=OVMF_VARS.fd bs=1M count=64
    -drive file=debian-uefi.img,format=raw,if=virtio \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0 \
    -nographic # Or use -serial stdio depending on your needs
```

*Note: Create a writable copy of the OVMF variables file (`OVMF_VARS.fd`) for QEMU.*
*You can then SSH into the running VM using `ssh neon@localhost -p 2222`.*

## Configuration

The main configuration is defined in `hub-efi.yaml`. You can modify this file to change packages, image size, partitioning, user setup, and other aspects of the build process. Overlays in the `overlays/` directory provide custom files and configurations applied during the build.
