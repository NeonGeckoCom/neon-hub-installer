# Cloud VPS Deployment

Neon Hub runs on any Linux VPS that meets the [system requirements](requirements.md). The installer itself is the same as on bare metal. Clone the repo and run `installer.sh`. This guide covers what to do around that: picking an instance, locking down the network, and getting an admin path in without a public IP.

## Instance sizing

| Workload                               | vCPU | RAM   | Disk       | Example types                                            |
| -------------------------------------- | ---- | ----- | ---------- | -------------------------------------------------------- |
| Minimum (single user, light use)       | 4    | 8 GB  | 80 GB SSD  | AWS `m6i.xlarge`, GCP `n2-standard-4`, Azure `D4s_v5`    |
| Recommended (household / small office) | 8    | 16 GB | 150 GB SSD | AWS `m6i.2xlarge`, GCP `n2-standard-8`, Azure `D8s_v5`   |
| Heavy (multi-user, many Nodes)         | 16   | 32 GB | 300 GB SSD | AWS `m6i.4xlarge`, GCP `n2-standard-16`, Azure `D16s_v5` |

Avoid burstable families (AWS `t3`/`t4g`, Azure `B`-series). Model inference can exhaust CPU credits rapidly.

Use a general-purpose SSD (AWS `gp3`, GCP `pd-balanced`, Azure Premium SSD). The Hub reads many small model files at startup, and spinning disks add minutes to boot.

## Network posture

**Do not put the Hub on a public subnet.** It is designed for trusted-LAN use.

- **Private subnet, no public IP.** On AWS, leave "Auto-assign public IPv4" off. On GCP, pass `--no-address`. On Azure, attach no public IP to the NIC.
- **No inbound rules from `0.0.0.0/0`.** Allow only your admin path (below) and the Node devices that need to reach the Hub.
- **Outbound to the internet is required** for Docker images, OS updates, and any external APIs the Hub calls.

If you must expose the Hub publicly (e.g. Nodes outside your home network), put it behind something you control: Cloudflare Tunnel, a VPN gateway, or your own nginx + Let's Encrypt on a separate host. HANA has authentication but the surface area was not designed for the open internet.

### Ports

| Port | Service       | Source                          |
| ---- | ------------- | ------------------------------- |
| 443  | HANA, web UIs | Node devices, admin workstation |

## DNS

A cloud Hub does not have the local network around it that makes `.local` name resolution work on a LAN, so you will want a real DNS solution. Route 53, Cloud DNS, and Azure DNS all work. Setting one up is out of scope for this guide, but the records you need are straightforward.

Pick a domain you control (for example `example-hub.com`) and create A records for the apex and for the main Hub services, all pointing at the **private IP** of the Hub instance:

```txt
example-hub.com
hana.example-hub.com
config.example-hub.com
iris.example-hub.com
```

That covers the configuration UI, the HANA API, and the Iris web client. The Hub publishes a few other internal subdomains (RabbitMQ admin, container manager, model backends) that you can add later if you need to reach them directly. See [Available Services](services.md) for the full list.

For optimal security, use a private hosted zone (Route 53 private zone, Cloud DNS private zone, Azure Private DNS) so the names only resolve from inside your network. Combined with Tailscale or a VPC peering, your client devices will resolve the Hub by hostname the same way they would on a home LAN.

## Admin access

With no public IP, you need an out-of-band path in.

### Recommended: Tailscale

Install Tailscale on the Hub and add it to your tailnet. The Hub is then reachable at its Tailscale IP or MagicDNS name from any other device on the tailnet.

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh
```

`--ssh` exposes SSH only over the tailnet, so you don't need OpenSSH listening on a host port at all.

The advantage over cloud-native options is portability: the same setup works on AWS, GCP, Azure, DigitalOcean, Hetzner, or a box at home, and Nodes on the same tailnet reach the Hub without any public exposure.

### Cloud-native session managers

If you can't use Tailscale, each major provider has a session broker that opens a shell on a private instance without an inbound SSH rule:

- **AWS:** Systems Manager Session Manager. Attach an IAM instance profile with `AmazonSSMManagedInstanceCore`. The SSM agent is preinstalled on Amazon Linux and recent Ubuntu AMIs. Connect with `aws ssm start-session --target i-xxxxxxxx`.
- **GCP:** IAP TCP forwarding. Connect with `gcloud compute ssh hub --tunnel-through-iap`. Requires `roles/iap.tunnelResourceAccessor` and an inbound rule on port 22 from `35.235.240.0/20`.
- **Azure:** Azure Bastion (managed) or Just-In-Time VM access via Defender for Cloud. Bastion is simpler. JIT is cheaper for occasional access.

These get you a shell. Reaching the Hub's HTTPS endpoints from a laptop still needs a tunnel: Tailscale, an SSH local-forward (`ssh -L 8443:localhost:443 hub`), or a provider port-forward (`aws ssm start-session --target i-xxxxxxxx --document-name AWS-StartPortForwardingSession`).

### Not recommended: public bastion host

A jump box with port 22 open to a home IP works, but it's more moving parts than Tailscale and home IPs rotate. Also, attack scripts regularly target common IP ranges, like those used by cloud providers. Skip it unless you already run a hardened Bastion host.

## Reaching the Hub from Nodes

Nodes on the same network as the Hub (same tailnet, same VPC, and so on) use the Hub's private IP or MagicDNS name. mDNS does not cross the WAN, so Nodes at home talking to a cloud Hub need a manual address. The path of least resistance is putting both on Tailscale and using the Hub's tailnet name (e.g. `https://hub.tail-scale.ts.net`). This is the most widely supported option across all of the operating systems that Nodes run on.

## Running the installer

Connect to the Hub instance using whichever admin path you set up above. From there, the install is identical to a bare-metal Linux box:

```bash
git clone https://github.com/NeonGeckoCom/neon-hub-installer
cd neon-hub-installer
sudo ./installer.sh
```

The installer walks you through a guided setup. When it asks for a hostname, use the apex domain you configured in DNS (for example `example-hub.com`) rather than the default `neon-hub.local`. The HANA, config, and Iris subdomains are derived from that hostname.

See [Installation](installation.md) for what the installer prompts cover and what you can change later.

## Validating the install

After `installer.sh` finishes, hit HANA from your admin workstation:

```bash
curl -k https://hub.tail-scale.ts.net/docs
```

A 200 confirms the stack is up.

## Backup

Hub state lives under the install directory (default `/home/neon/xdg/`). Snapshot the underlying disk on a schedule that fits your data. Daily is usually plenty for home use. Docker images are reproducible from the registry, so don't bother backing them up.
