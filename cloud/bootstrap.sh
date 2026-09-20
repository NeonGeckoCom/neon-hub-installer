#!/bin/bash
# Unattended Neon Hub install for a cloud VM. Runs as root from cloud-init.
# Drives the same Ansible playbook as installer.sh, without the prompts.
#
# Required environment:
#   NEON_HUB_PROVIDER       aws | digitalocean
#   NEON_HUB_ALLOWED_CIDR   Comma-separated CIDRs allowed to reach the Hub
# Optional environment:
#   NEON_HUB_HOSTNAME       Defaults to <public-ip>.sslip.io
#   NEON_HUB_PUBLIC_IP      Defaults to the provider metadata service value
#   NEON_HUB_ADMIN_USERNAME Defaults to neon
#   NEON_HUB_ADMIN_PASSWORD Generated when empty
#   NEON_HUB_DATA_DEVICE    Block device to format and mount for Hub data
#   NEON_HUB_SIGNAL_URL     CloudFormation wait condition handle

set -eEo pipefail

# cloud-init runs scripts without USER or HOME, and scripts/common.sh needs both.
export USER="${USER:-root}"
export HOME="${HOME:-/root}"

export LOG_FILE=/var/log/neon-hub-installer.log
export ANSIBLE_LOG_FILE=/var/log/neon-hub-ansible.log
export INSTALLER_VENV_NAME="neon-hub-installer"
export OS_RELEASE=/etc/os-release
export USER_ID="$EUID"

readonly DEPLOY_LOG=/var/log/neon-hub-cloud-deploy.log
readonly CREDENTIALS_FILE=/root/neon-hub-credentials.txt
readonly DATA_MOUNT=/mnt/neon-hub-data
readonly DATA_DEVICE_WAIT_SECONDS=300
readonly HEALTH_WAIT_SECONDS=1800
readonly HEALTH_POLL_SECONDS=15
readonly METADATA_HOST=169.254.169.254
readonly FIREWALL_UNIT=/etc/systemd/system/neon-hub-firewall.service
readonly FIREWALL_SCRIPT=/usr/local/sbin/neon-hub-firewall
readonly EXTRA_VARS_FILE=/root/neon-hub-extra-vars.json

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR

exec >>"$DEPLOY_LOG" 2>&1

log() {
    echo "[$(date -u +%FT%TZ)] $*"
}

signal_cloudformation() {
    local status=$1 reason=$2
    [ -n "$NEON_HUB_SIGNAL_URL" ] || return 0
    curl -sS -X PUT -H 'Content-Type:' \
        --data-binary "{\"Status\":\"${status}\",\"Reason\":\"${reason}\",\"UniqueId\":\"neon-hub\",\"Data\":\"${reason}\"}" \
        "$NEON_HUB_SIGNAL_URL" || log "Could not signal CloudFormation"
}

fail() {
    log "FAILED: $1"
    signal_cloudformation FAILURE "$1. See ${DEPLOY_LOG} on the instance."
    exit 1
}

require_settings() {
    case "$NEON_HUB_PROVIDER" in
    aws | digitalocean) ;;
    *) fail "NEON_HUB_PROVIDER must be aws or digitalocean" ;;
    esac
    # The Hub is not designed for the open internet, so an unset CIDR stops the install.
    [ -n "$NEON_HUB_ALLOWED_CIDR" ] || fail "NEON_HUB_ALLOWED_CIDR is not set"
}

public_ip_from_metadata() {
    local token
    case "$NEON_HUB_PROVIDER" in
    aws)
        token=$(curl -sf -X PUT -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' "http://${METADATA_HOST}/latest/api/token")
        curl -sf -H "X-aws-ec2-metadata-token: ${token}" "http://${METADATA_HOST}/latest/meta-data/public-ipv4"
        ;;
    digitalocean)
        curl -sf "http://${METADATA_HOST}/metadata/v1/interfaces/public/0/ipv4/address"
        ;;
    esac
}

resolve_hostname() {
    PUBLIC_IP="${NEON_HUB_PUBLIC_IP:-$(public_ip_from_metadata)}"
    [ -n "$PUBLIC_IP" ] || fail "Could not determine the public IP"
    # nginx routes by subdomain. sslip.io resolves any <name>.<dashed-ip>.sslip.io to that IP.
    HUB_HOSTNAME="${NEON_HUB_HOSTNAME:-${PUBLIC_IP//./-}.sslip.io}"
    log "Public IP ${PUBLIC_IP}, hostname ${HUB_HOSTNAME}"
}

mount_data_volume() {
    XDG_DIR=/home/neon/xdg
    [ -n "$NEON_HUB_DATA_DEVICE" ] || return 0
    local waited=0
    until [ -b "$NEON_HUB_DATA_DEVICE" ]; do
        [ "$waited" -lt "$DATA_DEVICE_WAIT_SECONDS" ] || fail "Data device ${NEON_HUB_DATA_DEVICE} never appeared"
        sleep 5
        waited=$((waited + 5))
    done
    # Format only a blank device, so a re-attached volume keeps its Hub data.
    blkid "$NEON_HUB_DATA_DEVICE" >/dev/null || mkfs.ext4 -L neon-hub-data "$NEON_HUB_DATA_DEVICE"
    mkdir -p "$DATA_MOUNT"
    grep -q "$DATA_MOUNT" /etc/fstab || echo "LABEL=neon-hub-data ${DATA_MOUNT} ext4 defaults,nofail 0 2" >>/etc/fstab
    mount "$DATA_MOUNT"
    XDG_DIR="${DATA_MOUNT}/xdg"
}

# Docker publishes container ports ahead of ufw, so the limit has to live in DOCKER-USER.
# The chain is created before Docker is installed so no port is ever open to the world.
restrict_inbound() {
    local iface cidr
    apt_ensure iptables
    iface=$(ip -4 route show default | awk '{print $5; exit}')
    {
        echo '#!/bin/bash'
        echo "iptables -N DOCKER-USER 2>/dev/null"
        echo "iptables -F DOCKER-USER"
        echo "iptables -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN"
        for cidr in ${NEON_HUB_ALLOWED_CIDR//,/ }; do
            echo "iptables -A DOCKER-USER -i ${iface} -s ${cidr} -j RETURN"
        done
        echo "iptables -A DOCKER-USER -i ${iface} -j DROP"
    } >"$FIREWALL_SCRIPT"
    chmod 700 "$FIREWALL_SCRIPT"
    "$FIREWALL_SCRIPT"
}

persist_inbound_rules() {
    cat >"$FIREWALL_UNIT" <<EOF
[Unit]
Description=Limit inbound access to Neon Hub containers
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=${FIREWALL_SCRIPT}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now neon-hub-firewall.service
}

prepare_ansible() {
    # shellcheck source=scripts/common.sh
    source "${REPO_DIR}/scripts/common.sh"
    cd "$REPO_DIR"
    detect_user
    get_os_information
    required_packages
    create_python_venv
    # shellcheck source=/dev/null
    source "${VENV_PATH}/bin/activate"
    install_ansible
}

generate_password() {
    python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32)))"
}

# Extra vars go through a root-only JSON file so passwords stay out of the process list
# and survive quoting. Blank service passwords make the playbook generate them.
write_extra_vars() {
    umask 077
    XDG_DIR="$XDG_DIR" HUB_HOSTNAME="$HUB_HOSTNAME" \
        ADMIN_USERNAME="$ADMIN_USERNAME" ADMIN_PASSWORD="$ADMIN_PASSWORD" \
        python3 - >"$EXTRA_VARS_FILE" <<'PY'
import json, os
print(json.dumps({
    "xdg_dir": os.environ["XDG_DIR"],
    "common_name": os.environ["HUB_HOSTNAME"],
    "install_neon_node": "0",
    "install_neon_node_gui": "0",
    "browser_package": "firefox",
    "hub_admin_username_input": os.environ["ADMIN_USERNAME"],
    "hub_admin_password_input": os.environ["ADMIN_PASSWORD"],
    "sdm_password": "",
    "skill_config_password": "",
}))
PY
}

run_playbook() {
    ADMIN_USERNAME="${NEON_HUB_ADMIN_USERNAME:-neon}"
    ADMIN_PASSWORD="${NEON_HUB_ADMIN_PASSWORD:-$(generate_password)}"
    mkdir -p "$XDG_DIR"
    hostnamectl set-hostname "$HUB_HOSTNAME"
    write_extra_vars
    export ANSIBLE_CONFIG=ansible.cfg
    ansible-playbook -i 127.0.0.1 -e "@${EXTRA_VARS_FILE}" \
        debos/overlays/ansible/hub.yaml >>"$ANSIBLE_LOG_FILE" 2>&1 || fail "Ansible playbook failed. See ${ANSIBLE_LOG_FILE}"
    rm -f "$EXTRA_VARS_FILE"
}

wait_for_hana() {
    local waited=0
    until curl -ksf --resolve "hana.${HUB_HOSTNAME}:443:127.0.0.1" "https://hana.${HUB_HOSTNAME}/docs" >/dev/null; do
        [ "$waited" -lt "$HEALTH_WAIT_SECONDS" ] || fail "HANA did not answer within ${HEALTH_WAIT_SECONDS} seconds"
        sleep "$HEALTH_POLL_SECONDS"
        waited=$((waited + HEALTH_POLL_SECONDS))
    done
    log "HANA is answering"
}

write_credentials() {
    umask 077
    cat >"$CREDENTIALS_FILE" <<EOF
Neon Hub
  Hub configuration:  https://config.${HUB_HOSTNAME}
  HANA (Node address): https://hana.${HUB_HOSTNAME}
  Iris web client:    https://iris.${HUB_HOSTNAME}

Hub admin account:    ${ADMIN_USERNAME} / ${ADMIN_PASSWORD}
Service passwords:    ${REPO_DIR}/debos/overlays/ansible/neon_hub_secrets.yaml
Admin token:          ${XDG_DIR}/config/neon/hub_admin.yaml
EOF
}

main() {
    trap 'fail "Error on line $LINENO"' ERR
    log "Neon Hub cloud deploy starting"
    require_settings
    resolve_hostname
    mount_data_volume
    prepare_ansible
    restrict_inbound
    run_playbook
    persist_inbound_rules
    wait_for_hana
    write_credentials
    signal_cloudformation SUCCESS "Neon Hub is running at https://config.${HUB_HOSTNAME}"
    log "Neon Hub cloud deploy finished"
}

main "$@"
