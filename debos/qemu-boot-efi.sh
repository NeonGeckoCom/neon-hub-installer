#!/usr/bin/env bash

qemu-system-x86_64 \
    -enable-kvm -cpu host -smp 2 -m 1G \
    -bios /usr/share/qemu/OVMF.fd \
    -drive format=raw,file=${1} \
    -net nic,model=virtio \
    -net user,hostfwd=tcp::2222-:22 \
    -serial stdio \
    -monitor none \
    -nographic
