# Deploy to Cloud

These templates create a cloud VM and install Neon Hub on it without any prompts. For a manual install on any Linux VPS, see [Cloud VPS Deployment](cloud-vps.md).

[![Launch Stack](https://s3.amazonaws.com/cloudformation-examples/cloudformation-launch-stack.png)](https://console.aws.amazon.com/cloudformation/home#/stacks/quickcreate?stackName=neon-hub&templateURL=https://NEON_TEMPLATE_BUCKET.s3.amazonaws.com/neon-hub.yaml)
[![Deploy to DO](https://www.deploytodo.com/do-btn-blue.svg)](https://cloud.digitalocean.com/droplets/new?image=ubuntu-24-04-x64&size=s-4vcpu-8gb&region=nyc3)

## Is this for you?

A cloud Hub is a good way to try Neon Hub before you commit to hardware. Both providers bill by the hour, so a weekend trial costs a few dollars, and deleting the VM ends the charges.

For a Hub you plan to keep, your own hardware costs less. A Hub is idle most of the day, and a cloud VM bills for that idle time. A used laptop or mini PC with 4 cores and 8 GB of memory pays for itself in about 6 months at these prices, and a new one in about 9. Everything runs on the CPU, so no graphics card is needed. See [Installation](installation.md).

A cloud Hub also suits you if you cannot keep a computer running at home, or if your Nodes are spread across several locations.

## Choosing a provider

|                          | AWS                                         | DigitalOcean                             |
| ------------------------ | ------------------------------------------- | ---------------------------------------- |
| Default size             | `t3.xlarge`, 4 vCPU, 16 GB                  | `s-4vcpu-8gb`, 4 vCPU, 8 GB              |
| Disk                     | 80 GB system plus 20 GB data volume         | 160 GB included                          |
| Approximate monthly cost | $133 (instance $121, disks $8, public IP $4) | $48                                      |
| CPU                      | Burstable                                   | Shared                                   |
| Regions                  | 30+                                         | 9 cities                                 |
| Free tier                | Does not cover this size                    | None. New accounts often receive credit. |
| Static IP                | Included in the template                    | Droplet IP is kept until it is destroyed |
| Firewall                 | Security group                              | Rules on the Droplet                     |
| Steps                    | One form                                    | One form and a pasted script             |

Prices are on-demand rates in US regions as of September 2026. Both providers bill by the hour or less, so a short trial costs a few dollars.

Both defaults have 4 vCPUs because speech recognition uses about 7 CPU-seconds per request and spreads across cores. With 2 vCPUs the Hub works, but replies take several seconds longer. A Hub for one household uses about 5 GB of memory and is idle between requests, so burstable and shared CPUs are a good fit. Pick an `m6i` size on AWS or a dedicated-CPU Droplet for many Nodes in constant use.

## Before you start

Find the public IP of the network your Nodes and browser will connect from. The templates only let that network reach the Hub.

```bash
curl https://checkip.amazonaws.com
```

Add `/32` to the result, for example `203.0.113.7/32`. This value is called the allowed CIDR below. If your ISP changes your IP later, update it as described under [Changing the allowed network](#changing-the-allowed-network).

## AWS

1. Select **Launch Stack** above and sign in.
2. Choose a region in the top bar. The region needs a default VPC, which every new AWS account has.
3. Enter your allowed CIDR. Every other field has a working default.
4. Tick the box acknowledging that the stack creates IAM resources. The template adds one role so that Systems Manager can open a shell on the instance.
5. Select **Create stack**.

The stack takes 30 to 45 minutes. It reports `CREATE_COMPLETE` only after the Hub answers, so there is nothing to check by hand. The **Outputs** tab then shows:

| Output         | Use                                        |
| -------------- | ------------------------------------------ |
| `HubConfigUrl` | Hub configuration page                     |
| `NodeAddress`  | Address to enter in the Neon Node app      |
| `PublicIp`     | Static IP, for your own DNS records        |
| `InstanceId`   | Target for Systems Manager Session Manager |

If you left the admin password empty, read the generated one from the instance:

```bash
aws ssm start-session --target i-xxxxxxxx
sudo cat /root/neon-hub-credentials.txt
```

Deleting the stack removes everything except a snapshot of the data volume.

## DigitalOcean

DigitalOcean's own deploy button only targets App Platform, which cannot run the Hub's Docker Compose stack. A Droplet needs one pasted script.

### Control panel

1. Select **Deploy to DO** above and sign in. The form opens with Ubuntu 24.04 and the `s-4vcpu-8gb` size selected. If it does not, choose them by hand.
2. Choose an SSH key under **Authentication**.
3. Open **Advanced Options** and tick **Add Initialization scripts**.
4. Paste the contents of [`cloud/digitalocean/user-data.sh`](https://github.com/NeonGeckoCom/neon-hub-installer/blob/main/cloud/digitalocean/user-data.sh).
5. Put your allowed CIDR between the quotes on the `NEON_HUB_ALLOWED_CIDR` line.
6. Select **Create Droplet**.

### Command line

With [`doctl`](https://docs.digitalocean.com/reference/doctl/how-to/install/) installed and authenticated:

```bash
curl -fsSLO https://raw.githubusercontent.com/NeonGeckoCom/neon-hub-installer/main/cloud/digitalocean/user-data.sh
sed -i.bak 's|NEON_HUB_ALLOWED_CIDR=""|NEON_HUB_ALLOWED_CIDR="203.0.113.7/32"|' user-data.sh
doctl compute droplet create neon-hub --image ubuntu-24-04-x64 --size s-4vcpu-8gb --region nyc3 --ssh-keys "$(doctl compute ssh-key list --format ID --no-header | head -n 1)" --user-data-file user-data.sh --wait
```

### Finding your Hub

The install takes 30 to 45 minutes after the Droplet is created. Follow it over SSH:

```bash
ssh root@DROPLET_IP tail -f /var/log/neon-hub-cloud-deploy.log
```

When the log ends with `Neon Hub cloud deploy finished`, the addresses and admin password are in `/root/neon-hub-credentials.txt`.

## Hostnames

The Hub serves each service on its own subdomain, so a bare IP address is not enough. Without a domain, the templates use [sslip.io](https://sslip.io), a public DNS service that resolves any name containing an IP address to that address. A Hub at `203.0.113.10` becomes:

```txt
https://config.203-0-113-10.sslip.io
https://hana.203-0-113-10.sslip.io
https://iris.203-0-113-10.sslip.io
```

To use your own domain, set `HubHostname` on AWS or add `export NEON_HUB_HOSTNAME="example-hub.com"` to the DigitalOcean script. Then create A records for the domain and its `hana`, `config`, and `iris` subdomains. See [Available Services](services.md) for the full list.

## After the install

The Hub uses a self-signed certificate. Accept it in the browser on first visit. Replacing it with a Let's Encrypt certificate is a manual step and needs your own domain.

Confirm the Hub from your workstation:

```bash
curl -k https://hana.203-0-113-10.sslip.io/docs
```

A 200 confirms the stack is up. Then open the `config` address, sign in with the admin account, and add Node users. In the Neon Node app, enter the `hana` address and a Node user's credentials.

### Changing the allowed network

On AWS, update the stack and change `AllowedCidr`. The instance is not replaced.

On DigitalOcean, edit the addresses in `/usr/local/sbin/neon-hub-firewall`, then run:

```bash
sudo systemctl restart neon-hub-firewall
```

## Updating the Hub

```bash
sudo docker compose -p neon -f /home/neon/compose/neon-hub.yml pull
sudo docker compose -p neon -f /home/neon/compose/neon-hub.yml up -d
```

## Backup and restore

Hub state lives in one directory. Docker images come from the registry and do not need a backup.

| Provider     | Data directory           | Backup                                                   |
| ------------ | ------------------------ | -------------------------------------------------------- |
| AWS          | `/mnt/neon-hub-data/xdg` | Snapshot the `neon-hub-data` EBS volume                  |
| DigitalOcean | `/home/neon/xdg`         | Enable Droplet backups, or take a snapshot of the Droplet |

To restore on AWS, create a volume from the snapshot in the same availability zone as the instance. Stop the instance, detach the current data volume, attach the restored one as `/dev/sdf`, and start the instance.

To restore on DigitalOcean, create a new Droplet from the backup or snapshot. The new Droplet has a new IP, so its sslip.io hostname changes. Use your own domain if you need the address to survive a restore.

For a copy you hold yourself, archive the directory while the stack is stopped:

```bash
sudo docker compose -p neon -f /home/neon/compose/neon-hub.yml stop
sudo tar -czf neon-hub-backup.tar.gz -C /home/neon xdg
sudo docker compose -p neon -f /home/neon/compose/neon-hub.yml start
```

On AWS, replace `-C /home/neon` with `-C /mnt/neon-hub-data`.

## Troubleshooting

| Symptom                                            | Cause                                          | Fix                                                                        |
| -------------------------------------------------- | ---------------------------------------------- | -------------------------------------------------------------------------- |
| AWS stack fails with a wait condition timeout      | Install did not finish within an hour          | Open a Session Manager shell and read `/var/log/neon-hub-cloud-deploy.log` |
| Log ends with `NEON_HUB_ALLOWED_CIDR is not set`   | The DigitalOcean script was pasted unedited    | Destroy the Droplet and create it again with the CIDR filled in            |
| Hub worked yesterday and now times out             | Your public IP changed                         | [Change the allowed network](#changing-the-allowed-network)                |
| Browser warns about the certificate                | Self-signed certificate                        | Accept it, or install your own certificate                                 |
