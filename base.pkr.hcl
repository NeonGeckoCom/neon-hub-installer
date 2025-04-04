packer {
  required_plugins {
    qemu = {
      version = "~> 1"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "accelerator" {
  type    = string
  default = "kvm"
  validation {
    condition     = contains(["kvm", "hvf", "none"], var.accelerator)
    error_message = "Accelerator must be one of: kvm, hvf, or none."
  }
}

variable "iso_url" {
  type    = string
  default = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.10.0-amd64-netinst.iso"
}

variable "iso_checksum" {
  type    = string
  default = "file:https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/SHA256SUMS"
}

source "qemu" "debian-base" {
  iso_url           = var.iso_url
  iso_checksum      = var.iso_checksum
  output_directory  = "output-base"
  vm_name          = "debian-base"
  disk_size        = "60G"
  memory           = 8192
  cpus             = 4
  headless         = true
  boot_wait        = "10s"
  boot_command     = [
    "<esc><wait>",
    "auto preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg ",
    "debian-installer=en_US.UTF-8 auto locale=en_US.UTF-8 kbd-chooser/method=us ",
    "hostname=debian-base ",
    "fb=false debconf/frontend=noninteractive ",
    "keyboard-configuration/modelcode=SKIP keyboard-configuration/layout=USA ",
    "keyboard-configuration/variant=USA console-setup/ask_detect=false ",
    "net.ifnames=0 ",
    "interface=auto ",
    "vga=788 ",
    "<enter><wait>"
  ]
  http_directory   = "http"
  shutdown_command = "echo 'neon' | sudo -S shutdown -P now"
  ssh_username     = "neon"
  ssh_password     = "neon"
  ssh_timeout      = "60m"
  ssh_port         = 22
  ssh_wait_timeout = "60m"
  
  disk_interface = "virtio"
  format         = "qcow2"
  accelerator    = var.accelerator
}

build {
  sources = ["source.qemu.debian-base"]

  provisioner "shell" {
    inline = [
      "echo 'neon ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/neon",
      "sudo chmod 440 /etc/sudoers.d/neon",
      "sudo apt-get update",
      "sudo apt-get install -y openssh-server sudo curl wget git build-essential python3 python3-pip python3-venv ca-certificates gnupg lsb-release apt-transport-https software-properties-common",
      "sudo systemctl enable sddm",
      "sudo systemctl set-default graphical.target"
    ]
  }
} 