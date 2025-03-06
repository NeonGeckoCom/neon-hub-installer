# Installation

!!! info
    tl;dr run this script:
    ```bash
    git clone https://github.com/NeonGeckoCom/neon-hub-installer
    cd neon-hub-installer
    sudo ./neon-hub-installer/installer.sh
    ```

Clone the installer repository (`git clone https://github.com/NeonGeckoCom/neon-hub-installer`) and run `sudo ./installer.sh`. It will install prerequisites, then take you through a guided setup process.

For most users, the default settings will be sufficient.

## Neon Node

A Neon Node is a device that connects to a Neon Hub. It can be a Raspberry Pi, a computer, or any other device that can run Linux. Nodes can be used to interact with the Hub using voice commands, text, or a web interface. As of version 0.1.0, the Hub can be installed with a built-in Node. This is convenient for standalone devices, such as laptops or Mini PCs, that also have a microphone and a screen.

Installing a Node is handled automatically by the Hub installer. Note that you can optionally install a Node or Kiosk mode, but not both.

## Kiosk Mode

Kiosk mode is a special mode that allows a device to act as a standalone Neon Node. It is useful for devices that have a microphone and a screen. Your Hub in Kiosk mode is similar to a smart display, such as a Google Nest Hub or Amazon Echo Show.

Kiosk mode can be also installed automatically by the Hub installer by selecting that option in the installer.

When Kiosk mode is installed, the device will boot directly into the Neon Node interface. You will see a browser warning about an untrusted certificate. This is normal and expected. You can safely ignore it and proceed to the Node interface.
