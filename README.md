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

## Building the Image

This repository includes a Packer configuration to build a Neon Hub image. The image can be built on Linux or macOS systems.

### Prerequisites

- [Packer](https://www.packer.io/downloads)
- [QEMU](https://www.qemu.org/download/)
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)

### Building

The build process is split into two stages to allow for faster iteration during development:

1. Build the base Debian image (only needed once or when base configuration changes):

```bash
packer build -var="accelerator=none" base.pkr.hcl
```

2. Build the Neon Hub image (can be repeated for testing Ansible changes):

```bash
packer build -var="accelerator=none" packer.pkr.hcl
```

By default, this will use KVM acceleration on Linux systems. On macOS, the acceleration type depends on your Mac's architecture:

#### Intel Macs

Use Hypervisor.framework:

```bash
packer build -var="accelerator=hvf" packer.pkr.hcl
```

#### Apple Silicon Macs

Use the default QEMU configuration:

```bash
packer build -var="accelerator=none" packer.pkr.hcl
```

If you encounter any issues with hardware acceleration, you can build without it on any platform:

```bash
packer build -var="accelerator=none" packer.pkr.hcl
```

The built image will be available in the `dist` directory as `neon-hub.img.gz`.

### Development Workflow

1. Make changes to Ansible playbooks in the `ansible/` directory
2. Build using `packer.pkr.hcl` to test changes
3. The build will use the cached base image, making iterations much faster

### User Configuration

The image is configured with:

- Default user: `neon`
- Default password: `neon`
- Sudo access: Yes (passwordless)
- SSH: Enabled
- Default hostname: `neon-hub.local`

### Customization

You can customize the build by setting various variables:

- `memory_size`: VM memory in MB (default: 8192)
- `disk_size`: VM disk size (default: "60G")
- `cpus`: Number of CPU cores (default: 4)
- `hostname`: System hostname (default: "neon-hub.local")
- `xdg_dir`: XDG base directory (default: "/home/neon/xdg")
- `install_neon_node`: Whether to install Neon Node (default: 0)
- `install_neon_node_gui`: Whether to install Neon Node GUI (default: 0)
- `browser_package`: Browser package to install (default: "firefox-esr")
- `accelerator`: VM acceleration mode (default: "kvm")
  - Use `kvm` on Linux if available
  - Use `hvf` on macOS if available
  - Use `none` if no hardware acceleration is available

For example:

```bash
packer build -var="memory_size=16384" -var="disk_size=120G" packer.pkr.hcl
```

Variables can also be set in a `.auto.pkrvars.hcl` file for automatic loading. The repository includes a default configuration in `variables.auto.pkrvars.hcl`.
