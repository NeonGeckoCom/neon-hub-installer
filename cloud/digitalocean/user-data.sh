#!/bin/bash
# Neon Hub on a DigitalOcean Droplet. Paste into "Advanced Options > Add Initialization scripts".

# REQUIRED: who may reach the Hub. Your public IP as a CIDR, for example 203.0.113.7/32.
# Separate several with commas. The install stops if this is empty.
export NEON_HUB_ALLOWED_CIDR=""

export NEON_HUB_PROVIDER=digitalocean
apt-get update -y
apt-get install -y git
git clone --depth 1 --branch main https://github.com/NeonGeckoCom/neon-hub-installer /opt/neon-hub-installer
/opt/neon-hub-installer/cloud/bootstrap.sh
