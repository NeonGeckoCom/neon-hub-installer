variable "vm_name" {
  type    = string
  default = "neon-hub"
}

variable "memory_size" {
  type    = number
  default = 8192
}

variable "disk_size" {
  type    = string
  default = "60G"
}

variable "cpus" {
  type    = number
  default = 4
}

variable "hostname" {
  type    = string
  default = "neon-hub.local"
}

variable "xdg_dir" {
  type    = string
  default = "/home/neon/xdg"
}

variable "install_neon_node" {
  type    = number
  default = 0
}

variable "install_neon_node_gui" {
  type    = number
  default = 0
}

variable "browser_package" {
  type    = string
  default = "firefox-esr"
}

variable "accelerator" {
  type    = string
  default = "kvm"
  validation {
    condition     = contains(["kvm", "hvf", "none"], var.accelerator)
    error_message = "Accelerator must be one of: kvm, hvf, or none."
  }
}

source "qemu" "debian" {
  # Use the base image
  disk_image        = true
  iso_url           = "output-base/debian-base"
  iso_checksum      = "none"
  output_directory  = "output"
  vm_name          = var.vm_name
  disk_size        = var.disk_size
  memory           = var.memory_size
  cpus             = var.cpus
  headless         = true
  
  ssh_username     = "neon"
  ssh_password     = "neon"
  ssh_timeout      = "60m"
  ssh_port         = 22
  ssh_wait_timeout = "60m"
  
  shutdown_command = "echo 'neon' | sudo -S shutdown -P now"
  
  disk_interface = "virtio"
  format         = "qcow2"
  accelerator    = var.accelerator
}

build {
  sources = ["source.qemu.debian"]

  provisioner "shell" {
    inline = [
      "echo 'Setting up prerequisites for Neon Hub'",
      "sudo apt-get update && sudo apt-get install -y git python3-pip",
      "echo 'Prerequisite installation complete'"
    ]
  }

  provisioner "shell-local" {
    inline = [
      "cd ansible && ansible-galaxy install -r requirements.yml"
    ]
  }

  provisioner "ansible" {
    playbook_file = "ansible/site.yaml"
    extra_arguments = [
      "-e", "xdg_dir=/home/neon/xdg",
      "-e", "hostname=neon-hub.local",
      "-e", "install_neon_node=0",
      "-e", "install_neon_node_gui=0",
      "-e", "browser_package=firefox-esr"
    ]
    ansible_env_vars = [
      "ANSIBLE_FORCE_COLOR=1",
      "ANSIBLE_HOST_KEY_CHECKING=False"
    ]
  }

  post-processor "shell-local" {
    inline = [
      "mkdir -p dist",
      "qemu-img convert -f qcow2 -O raw output/neon-hub output/neon-hub.raw",
      "gzip -9 output/neon-hub.raw",
      "mv output/neon-hub.raw.gz dist/neon-hub.img.gz"
    ]
  }
} 