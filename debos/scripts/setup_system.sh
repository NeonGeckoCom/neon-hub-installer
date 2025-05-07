#!/bin/bash
#set -eux

# User setup
useradd -m -s /bin/bash neon
echo 'neon:neon' | chpasswd
usermod -aG sudo neon
echo 'neon ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/neon
chmod 440 /etc/sudoers.d/neon

# Configure SSH
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin .*/#PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

# Enable services links (might show warnings if systemd isn't fully running)
systemctl enable ssh
systemctl enable NetworkManager

echo "System setup script finished."
# DO NOT RUN update-grub HERE

