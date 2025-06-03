# Neon Hub

Neon Hub is a central server for artificial intelligence, powered by Neon AI®. It is designed to be a private, offline, and secure alternative to cloud-based AI assistants like Alexa, Google Assistant, and Siri. A Neon Hub can run on any consumer computer built within the last 5 years, running the Linux operating system, and can be accessed from any device on the same network. Neon Hub is designed to be easy to set up and use, with a web interface for managing services and a RESTful API for developers. A GPU is not required and is currently not supported, but future versions will support GPU acceleration.

A Neon Hub can be used with any number of Neon Nodes, which can be as small as a Raspberry Pi Zero W. Nodes can be placed throughout a home or office, and can be used to interact with the Hub using voice commands, text, or a web interface. The Hub can be used to control smart home devices, answer questions, play music, and more.

Neon Hub is perfect for:

- Privacy-conscious individuals
- Retail kiosks
- Municipalities
- Educational institutions
- Hospitals
- Hotels

## Documentation

Detailed documentation is available at [https://neongeckocom.github.io/neon-hub-installer](https://neongeckocom.github.io/neon-hub-installer).

It can be accessed locally by [installing mkdocs](https://www.mkdocs.org/getting-started/) and running `mkdocs serve` in the root of the repository.

## Neon Hub Image

Official Neon Hub images can be built using the [`build.sh`](./debos/build.sh) script in the `debos` folder of the repository.

```bash
cd debos
./build.sh
```

You will need to have Docker installed to build the image, and the user you run the script with needs to have access to the Docker socket and the `sudo` command. Alternately, your user can be in the `kvm` group to avoid the need for `sudo`.

The script will build the image and save it as `neon-hub-amd64_<date>.img.gz`. The image can only be used with UEFI secure boot disabled at this time.

Some users have reported errors on first boot, specifically: `startkde: Could not start Plasma session.` This can be worked around by rebooting the system.

The Hub image is a fairly minimal Debian 12 image with KDE Plasma installed. It is simpler to load your preferred version of Ubuntu or Debian and use the installer tool to create a Hub, and _this is the recommended approach_.

If you choose to build the image yourself, it will be a bootable image that can be burned to a USB drive using a tool like [balenaEtcher](https://www.balena.io/etcher/). This can be a great way to test Neon Hub before installing on your preferred hardware.

To install on your preferred hardware, Neon recommends [a Debian live install image](https://www.debian.org/CD/live/) along with the Hub image. Boot from the live image and use `dd` to write the Hub image to your preferred hardware's primary storage device.

**WARNING:** Improperly using `dd` can result in data loss on your preferred hardware. Please ensure you have made proper backups of any data on the hardware before proceeding. Again, for most users, it is recommended to use the installer tool to create a Hub or purchase hardware with Neon Hub pre-installed (not yet available).
