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

export TIMESTAMP=$(date +%s)
export IMG_NAME="neon-hub-amd64_${TIMESTAMP}.img"
mv debian-uefi.img "${IMG_NAME}"
gzip "${IMG_NAME}"

echo "Image built: ${IMG_NAME}.gz"
