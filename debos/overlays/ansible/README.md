# Neon Hub Ansible Project

This Ansible project manages the deployment and configuration of the Neon Hub system.

## Project Structure

```
ansible/
├── inventory/
│   └── hosts              # Inventory file defining hosts and groups
├── roles/                 # Ansible roles
│   ├── neon_hub/         # Core Neon Hub role
│   │   ├── tasks/
│   │   │   ├── main.yaml
│   │   │   ├── generate-certificate.yaml
│   │   │   ├── generate-secrets.yaml
│   │   │   └── hub.yaml
│   │   └── templates/
│   ├── kiosk/           # Kiosk mode role
│   │   ├── tasks/
│   │   │   ├── main.yaml
│   │   │   ├── kiosk.yaml
│   │   │   └── kiosk-teardown.yaml
│   │   └── templates/
│   └── neon_node/       # Neon Node role
│       ├── tasks/
│       │   ├── main.yaml
│       │   └── neon-node.yaml
│       └── templates/
├── group_vars/          # Group variables
│   └── all.yaml
├── host_vars/           # Host-specific variables
│   └── localhost.yaml
├── ansible.cfg          # Ansible configuration
├── requirements.yml     # Role and collection requirements
└── site.yaml           # Main playbook orchestrating all roles
```

## Usage

1. Install required roles and collections:

   ```bash
   ansible-galaxy install -r requirements.yml
   ```

2. Run the main playbook:
   ```bash
   ansible-playbook site.yaml
   ```

## Variables

- Common variables are defined in `group_vars/all.yaml`
- Host-specific variables are defined in `host_vars/localhost.yaml`
- Role-specific variables are defined in their respective role's `vars` directory

## Roles

### neon_hub

Main role for setting up the Neon Hub system, including:

- Certificate generation
- Secrets management
- Core system configuration
- Docker setup
- Service deployment

### kiosk

Role for managing kiosk mode functionality:

- Browser installation
- User configuration
- Autostart setup
- Desktop environment configuration

### neon_node

Role for Neon Node client setup:

- Node installation
- Service configuration
- System integration
- Audio setup

## Installation Options

The installation can be configured through host variables in `host_vars/localhost.yaml`:

- `install_neon_node`: Set to "1" to install the Neon Node client
- `install_neon_node_gui`: Set to "1" to install the Neon Node GUI

Note: Only one of these options can be enabled at a time.
