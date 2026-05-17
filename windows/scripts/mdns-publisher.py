#!/usr/bin/env python3
"""
Long-running mDNS publisher for the Neon Hub on Windows.

Replaces the Bonjour `dns-sd -R` advertisement that Phase 2.2 originally
shipped. Two Windows-native mDNS publishers have a known A-record bug
that makes them unusable for our case:

  - Apple's Bonjour for Windows: `dns-sd -P` returns
    `kDNSServiceErr_ServiceNotRunning` (-65563) for every invocation
    because the Windows port never implemented the connection-based
    DNSServiceRegisterRecord IPC.
  - Microsoft's built-in `DnsServiceRegister`: succeeds and broadcasts
    the SRV/TXT/PTR for the service envelope but silently drops the
    associated A record. Verified on Win11 26100 in 2026; this is the
    same bug reported against Win10 1809 and never fixed.

python-zeroconf speaks mDNS over UDP 5353 directly and sidesteps both
broken stacks.

This script publishes:

  - One `_neon-hub._tcp.local.` service record (Hub discovery, matches
    the macOS launchd plist's intent).
  - One A record for the bare hostname.
  - One A record per Hub subdomain (config, hana, iris, iris-websat,
    coqui, fasterwhisper, rmq-admin, skill-config), advertised via a
    dummy `_neon-hub-alias._tcp` service type — discovery clients
    browsing `_neon-hub._tcp` don't see the alias entries, but their
    A records broadcast as a side-effect of the registration.

Runs under the NeonHubMdnsService Windows service (wrapped by Shawl);
handles Ctrl-C / SIGBREAK to deregister cleanly before exiting.
"""
import argparse
import logging
import signal
import socket
import sys
import threading
from ipaddress import IPv4Address

try:
    from zeroconf import IPVersion, ServiceInfo, Zeroconf
except ImportError:
    sys.stderr.write(
        "ERROR: the zeroconf module is not installed for this Python.\n"
        "Install with:\n"
        "    python -m pip install zeroconf\n"
    )
    sys.exit(2)


SUBDOMAINS = (
    "config", "hana", "iris", "iris-websat",
    "coqui", "fasterwhisper", "rmq-admin", "skill-config",
)


def build_service_infos(hostname, ip):
    """Build the ServiceInfo objects zeroconf will register.

    Returns a list with the main _neon-hub._tcp service first, followed
    by one _neon-hub-alias._tcp ServiceInfo per subdomain.
    """
    ip_packed = IPv4Address(ip).packed
    instance_label = f"Neon Hub on {socket.gethostname()}"

    main = ServiceInfo(
        type_="_neon-hub._tcp.local.",
        name=f"{instance_label}._neon-hub._tcp.local.",
        addresses=[ip_packed],
        port=443,
        properties={"scheme": "https", "host": f"hana.{hostname}"},
        server=f"{hostname}.",
    )
    aliases = [
        ServiceInfo(
            type_="_neon-hub-alias._tcp.local.",
            name=f"{sub}._neon-hub-alias._tcp.local.",
            addresses=[ip_packed],
            port=443,
            server=f"{sub}.{hostname}.",
        )
        for sub in SUBDOMAINS
    ]
    return [main] + aliases


def main():
    parser = argparse.ArgumentParser(
        description="Neon Hub mDNS publisher (Windows, python-zeroconf-backed).",
    )
    parser.add_argument("--hostname", required=True,
                        help="NEON_HOSTNAME, e.g. neon-hub-win.local")
    parser.add_argument("--ip", required=True,
                        help="LAN IP to advertise in every A record")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="[publisher] %(asctime)s %(message)s",
    )
    log = logging.getLogger()
    log.info("starting (hostname=%s, ip=%s)", args.hostname, args.ip)

    zc = Zeroconf(ip_version=IPVersion.V4Only)
    infos = build_service_infos(args.hostname, args.ip)

    stop = threading.Event()

    def shutdown(signum, _frame=None):
        log.info("shutdown signal %s received", signum)
        stop.set()

    # SIGINT covers Ctrl-C, which is what Shawl sends to stop the service.
    # SIGBREAK is Ctrl-Break on Windows; SIGTERM is best-effort (the symbol
    # exists in Python's signal module on Windows but isn't actually
    # deliverable, so the registration is harmless).
    signal.signal(signal.SIGINT, shutdown)
    for name in ("SIGBREAK", "SIGTERM"):
        try:
            signal.signal(getattr(signal, name), shutdown)
        except (AttributeError, ValueError):
            pass

    try:
        for info in infos:
            log.info("registering %s -> %s", info.server.rstrip("."), args.ip)
            zc.register_service(info)
        log.info("all %d records registered; waiting for stop signal", len(infos))
        stop.wait()
    finally:
        log.info("deregistering ...")
        for info in infos:
            try:
                zc.unregister_service(info)
            except Exception as exc:  # zeroconf can throw on shutdown races
                log.warning("unregister %s failed: %s", info.name, exc)
        zc.close()
        log.info("done")


if __name__ == "__main__":
    main()
