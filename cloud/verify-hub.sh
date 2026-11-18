#!/bin/bash
# Checks that each advertised Hub hostname reaches its own service.
# Sourced by bootstrap.sh, which provides log, fail, HUB_HOSTNAME and PUBLIC_IP.

readonly ROUTED_SERVICES=(hana iris)
readonly PUBLIC_DNS_URL=https://cloudflare-dns.com/dns-query
readonly VHOST_TIMEOUT_SECONDS=10

fetch_vhost_root() {
    local host="$1.${HUB_HOSTNAME}"
    curl -ks --max-time "$VHOST_TIMEOUT_SECONDS" --resolve "${host}:443:127.0.0.1" "https://${host}/"
}

# nginx sends a name that matches no server_name to its first server, the config page.
# HANA and the config page both answer /docs, so only comparing bodies shows a fall-through.
verify_vhost_routing() {
    local config_page service
    config_page=$(fetch_vhost_root config)
    [ -n "$config_page" ] || fail "https://config.${HUB_HOSTNAME} returned an empty page"
    for service in "${ROUTED_SERVICES[@]}"; do
        [ "$(fetch_vhost_root "$service")" != "$config_page" ] ||
            fail "https://${service}.${HUB_HOSTNAME} serves the config page instead of ${service}"
    done
    log "Each service hostname reaches its own service"
}

# The playbook maps every service name to 127.0.0.1 in /etc/hosts, so only a public
# resolver shows what a browser will get.
public_a_records() {
    curl -fsS --max-time "$VHOST_TIMEOUT_SECONDS" -H 'accept: application/dns-json' \
        "${PUBLIC_DNS_URL}?name=$1&type=A" |
        python3 -c 'import json, sys; print(" ".join(a["data"] for a in json.load(sys.stdin).get("Answer", []) if a["type"] == 1))' 2>/dev/null
}

warn_dns() {
    DNS_WARNINGS+="$1"$'\n'
    log "WARNING: $1"
}

# sslip.io names always resolve to the IP they contain, so a mismatch there is a wrong
# public IP. Records for a custom domain may simply not exist yet, so those only warn.
# An unreachable resolver says nothing about the records, so that only warns too.
verify_public_dns() {
    local service host records
    DNS_WARNINGS=""
    for service in config "${ROUTED_SERVICES[@]}"; do
        host="${service}.${HUB_HOSTNAME}"
        if ! records=$(public_a_records "$host"); then
            warn_dns "Could not look up ${host} at ${PUBLIC_DNS_URL}"
            continue
        fi
        case " ${records} " in
        *" ${PUBLIC_IP} "*) continue ;;
        esac
        case "$HUB_HOSTNAME" in
        *.sslip.io) fail "${host} resolves to '${records}', not the public IP ${PUBLIC_IP}" ;;
        esac
        warn_dns "${host} resolves to '${records}', not ${PUBLIC_IP}. Create an A record for it."
    done
    [ -n "$DNS_WARNINGS" ] || log "Public DNS resolves every service hostname to ${PUBLIC_IP}"
}
