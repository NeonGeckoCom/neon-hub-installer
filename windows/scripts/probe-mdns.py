"""Probe what the Neon Hub mDNS publisher is broadcasting on the
local segment.

Use when subdomain resolution misbehaves (e.g. the bare hostname
resolves via mDNS but `hana.<hostname>` returns NXDOMAIN). The
script browses both service types the publisher registers and
prints every instance + its server + parsed addresses, so we can
tell whether the publisher is actually broadcasting the alias
records or whether the resolver is the side dropping them.

Run via the Hub venv (which already has zeroconf installed):

    & ${NEON_HOME}\venv\Scripts\python.exe windows\scripts\probe-mdns.py

Output expectations:

    [_neon-hub._tcp.local.] Neon Hub on <pc>._neon-hub._tcp.local.
        server=<hostname>. addrs=['<ip>']
    [_neon-hub-alias._tcp.local.] hana._neon-hub-alias._tcp.local.
        server=hana.<hostname>. addrs=['<ip>']
    ... one alias entry per subdomain (config, hana, iris, ...) ...

If the alias lines are missing, the publisher isn't actually
registering them and the bug is on the publisher side. If all
entries are present but Resolve-DnsName for the subdomain still
returns NXDOMAIN, the bug is on the Windows resolver side.
"""
import time

from zeroconf import Zeroconf, ServiceBrowser

SERVICE_TYPES = (
    "_neon-hub._tcp.local.",
    "_https._tcp.local.",
)


class Listener:
    def add_service(self, zc, type_, name):
        info = zc.get_service_info(type_, name, timeout=2000)
        if info:
            addrs = info.parsed_addresses()
            print(f"  [{type_}] {name}")
            print(f"      server={info.server} addrs={addrs}")
        else:
            print(f"  [{type_}] {name}  (no SRV/A returned within 2s)")

    def remove_service(self, zc, type_, name):
        pass

    def update_service(self, zc, type_, name):
        pass


def main():
    zc = Zeroconf()
    try:
        for stype in SERVICE_TYPES:
            print(f"Browsing {stype}:")
            ServiceBrowser(zc, stype, Listener())
        # Give responders 5s to answer. mDNS startup convergence can be
        # slow over multicast, especially in a VM, so don't shave this.
        time.sleep(5)
    finally:
        zc.close()


if __name__ == "__main__":
    main()
