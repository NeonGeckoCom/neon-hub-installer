# Cloud Setup

Neon Hub can be deployed in the cloud using a variety of platforms, including AWS, Azure, and Google Cloud. The following sections provide guidance on how to set up Neon Hub in a cloud environment.

**NOTE:** Installing Neon Hub in the cloud is considered an advanced use case and may require additional configuration and troubleshooting compared to a local installation.

These instructions assume a basic familiarity with cloud platforms and command-line interfaces. They will not include details such as ensuring the VM is accessible from your machine, which may require additional configuration such as setting up security groups or firewall rules. In general, we recommend using the cloud provider's on-demand access to a virtual machine to access it, then installing a service such as [Tailscale](https://tailscale.com/) to allow access from your local machine. This is generally more secure than opening up ports to the public internet.

!!! warning "Do not expose Neon Hub to the public internet"
Neon Hub should not have a public IP address. Reach it over a VPN (Tailscale, WireGuard) or your cloud provider's private-access service (SSM, Bastion, IAP) instead.

## On-Demand Access

### AWS

AWS offers [SSM Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-instance-profile.html), which allows you to securely access your EC2 instances without needing to open inbound ports or manage SSH keys. To use SSM Session Manager, ensure that your EC2 instance has the appropriate IAM role with permissions for SSM, and that the SSM agent is installed and running on the instance.

SSM Session Manager has no per-session charge for most use cases.

### Azure

Azure provides the ability to run commands on your VM using `az vm run-command invoke`, which allows you to execute scripts on your VM without needing to open inbound ports or manage SSH keys. To use this feature, ensure that your Azure VM has the appropriate permissions and that the Azure VM Agent is installed and running. We recommend using this method to install [Tailscale](https://tailscale.com/) or a similar VPN service to allow secure access from your local machine, then continuing the installation process from a terminal session on the VM.

This feature has no per-invocation charge for most use cases.

### Google Cloud

Google Cloud offers [OS Login](https://cloud.google.com/compute/docs/oslogin) and [Identity-Aware Proxy (IAP)](https://cloud.google.com/iap) for secure access to your VM instances without needing to open inbound ports or manage SSH keys. To use these features, ensure that your Google Cloud VM has the appropriate IAM roles and that the necessary agents are installed and running on the instance.

OS Login and IAP have no per-session charge for most use cases.

## Accessing services

The Neon Hub installer assumes installation on a private home network and advertises services automatically using mDNS. In a cloud environment, mDNS will not work, so you will need to configure DNS or use the IP address of the instance to access services. Configuring DNS is outside the scope of this guide, but generally involves creating a custom domain name, then adding an A record that points to your instance's IP address for each service you want to access (e.g., `config.yourcooldomain.com`, `hana.yourcooldomain.com`, etc.). Alternatively, you can access services directly using the instance's IP address and the appropriate port (e.g., `https://<instance-ip>:443` for the configuration tool).

In AWS, you can use Route 53 to manage DNS records for your domain. In Azure, you can use Azure DNS, and in Google Cloud, you can use Cloud DNS. Each of these services allows you to create and manage DNS records for your domain, which can be used to point to your Neon Hub instance.

LLMs are well-trained on common cloud platforms and DNS, so you can also use them to help with any specific questions you have about setting up DNS or accessing services in your chosen cloud environment.

## AWS Installation

To deploy Neon Hub on AWS, you can use the following steps:

1. Create an EC2 instance with the appropriate specifications for your workload. We recommend:
   - Instance Type: t3.large or larger
   - Storage: At least 40 GB of SSD storage
   - The latest Debian Trixie AMI (Amazon Machine Image) for x86_64 architecture, published by the [Debian Cloud team](https://wiki.debian.org/Cloud/AmazonEC2Image).
     - The canonical AMI ID for your region can be retrieved with the AWS CLI: `aws ssm get-parameters-by-path --recursive --path /aws/service/debian/release/13/latest`
   - Networking: Ensure the instance is in a VPC with a private subnet. If a public IP is required for initial setup, ensure that it is removed after installation and that the instance is only accessible via a VPN or SSM Session Manager.
   - Security Group: Allow inbound traffic on port 443 (HTTPS) from the IP address or range that will be accessing the Neon Hub dashboard. Do not allow inbound traffic on port 80 (HTTP) or any other ports.
   - Key Pair: Create or select an existing key pair for SSH access if needed, but we recommend using SSM Session Manager instead for better security.
   - Instance Metadata Service: Set "Metadata version" to "V2 only (token required)" to enforce IMDSv2.
2. Connect to the instance
   - For better security, consider using [AWS SSM Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html) instead of SSH.
3. Run `curl -sSL https://raw.githubusercontent.com/NeonGeckoCom/neon-hub-installer/refs/heads/dev/installer.sh | bash` to install Neon Hub

## Azure Installation

To deploy Neon Hub on Azure, you can use the following steps:

1. Create a Virtual Machine with the appropriate specifications for your workload. We recommend:
   - Size: Standard_D2s_v6 or larger
   - Storage: At least 40 GB of SSD storage
   - Image: The latest Debian Trixie image for x86_64 architecture.
     - This can be obtained from the Azure Marketplace by searching for "Debian Trixie" or using the Azure CLI to find the latest image.
   - Networking: Ensure the VM is in a virtual network with a private subnet. If a public IP is required for initial setup, ensure that it is removed after installation and that the VM is only accessible via a VPN or Azure Bastion.
   - Network Security Group: Allow inbound traffic on port 443 (HTTPS) from the IP address or range that will be accessing the Neon Hub dashboard. Do not allow inbound traffic on port 80 (HTTP) or any other ports.
   - Disable password authentication; use SSH keys or Azure Bastion only.
2. Connect to the instance
   - For better security, consider using [Azure Bastion](https://learn.microsoft.com/azure/bastion/) or `az vm run-command invoke` instead of direct SSH access over the public internet.
3. Run `curl -sSL https://raw.githubusercontent.com/NeonGeckoCom/neon-hub-installer/refs/heads/dev/installer.sh | bash` to install Neon Hub

## Google Cloud Installation

To deploy Neon Hub on Google Cloud, you can use the following steps:

1. Create a Compute Engine instance with the appropriate specifications for your workload. We recommend:
   - Machine Type: n4-standard-2 or larger
   - Storage: At least 40 GB of SSD storage
   - Image: The latest Debian Trixie image for x86_64 architecture.
     - This can be obtained from the Google Cloud Console by selecting "Debian" and then choosing the latest version, or using the `gcloud` CLI to find the latest image.
   - Networking: Ensure the instance is in a VPC with a private subnet. If a public IP is required for initial setup, ensure that it is removed after installation and that the instance is only accessible via a VPN or Identity-Aware Proxy (IAP).
   - Firewall Rules: Allow inbound traffic on port 443 (HTTPS) from the IP address or range that will be accessing the Neon Hub dashboard. Do not allow inbound traffic on port 80 (HTTP) or any other ports.
   - Enable [OS Login](https://cloud.google.com/compute/docs/oslogin) and set `block-project-ssh-keys=true` on the instance to centralize SSH key management through IAM.
2. Connect to the instance
   - For better security, consider using [Identity-Aware Proxy (IAP)](https://cloud.google.com/iap) or `gcloud compute ssh` instead of direct SSH access over the public internet.
3. Run `curl -sSL https://raw.githubusercontent.com/NeonGeckoCom/neon-hub-installer/refs/heads/dev/installer.sh | bash` to install Neon Hub

## Data Persistence and Backups

Neon Hub stores all persistent state (configuration, user data, service databases) under the XDG data directory you select during installation. The default is `/home/neon/xdg`. Unlike a home-network install — where a user might clone an SD card or USB drive — cloud installs should rely on the provider's volume snapshot facilities for disaster recovery:

- **AWS:** Snapshot the EBS volume backing the instance (or use [Data Lifecycle Manager](https://docs.aws.amazon.com/ebs/latest/userguide/snapshot-lifecycle.html) for an automated schedule).
- **Azure:** Snapshot the managed disk, or enable [Azure Backup](https://learn.microsoft.com/azure/backup/backup-azure-vms-introduction) for the VM.
- **Google Cloud:** Use [persistent disk snapshots](https://cloud.google.com/compute/docs/disks/snapshots), optionally with a [snapshot schedule](https://cloud.google.com/compute/docs/disks/scheduled-snapshots).

Snapshot cadence should match your recovery point objective (RPO) requirements - in other words, how much data are you willing to lose in the event of a failure. For a fully portable backup, you can also archive the XDG data directory itself (e.g., `tar`/`rsync` to object storage mounted as a volume), but the Hub services must all be stopped to guarantee a consistent copy.

In the future, we will provide single-click deploy options where applicable, and Terraform scripts for users who want to automate deployment in their cloud environment. For now, the above instructions should allow you to get Neon Hub up and running in the cloud.
