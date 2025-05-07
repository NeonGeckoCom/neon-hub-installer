#!/bin/bash

docker run \
--rm \
--device /dev/kvm \
--workdir /image_build \
--mount type=bind,source=".",destination=/image_build \
--security-opt label=disable \
--name "neon_debos_efi_build" \
--memory 20GB \
--tmpfs /tmp:exec,size=8G \
godebos/debos -vvvv -m 12G hub-efi.yaml

gzip debian-uefi.img
