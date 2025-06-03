#!/bin/sh
set -e

FLAG_FILE="/etc/.resized_root"

if [ -f "$FLAG_FILE" ]; then
    echo "Root filesystem already resized. Flag file $FLAG_FILE exists."
    exit 0
fi

echo "First boot: attempting to resize root partition and filesystem."

# Determine the root device and partition number dynamically
ROOT_DEV=$(findmnt -n -o SOURCE /)
if [ -z "$ROOT_DEV" ]; then
    echo "Error: Could not determine root device." >&2
    exit 1
fi

ROOT_DISK=$(lsblk -n -o PKNAME "$ROOT_DEV")
if [ -z "$ROOT_DISK" ]; then
    echo "Error: Could not determine root disk for $ROOT_DEV." >&2
    exit 1
fi

# Ensure ROOT_DEV is in a format like /dev/sda1 or /dev/nvme0n1p1
# Handle cases like /dev/mapper/vg-lv by not attempting to get a partition number,
# as growpart might not be suitable or needed.
# This simple regex tries to find a digit at the end, optionally preceded by 'p'.
ROOT_PART_NUM=$(echo "$ROOT_DEV" | grep -oE '[p]?[0-9]+$')

echo "Root device: $ROOT_DEV"
echo "Root disk: /dev/$ROOT_DISK"
if [ -n "$ROOT_PART_NUM" ]; then
    echo "Root partition number: $ROOT_PART_NUM"
    echo "Attempting to grow /dev/$ROOT_DISK partition $ROOT_PART_NUM..."
    if /usr/bin/growpart "/dev/$ROOT_DISK" "$ROOT_PART_NUM"; then
        echo "growpart successful for /dev/$ROOT_DISK partition $ROOT_PART_NUM."
    else
        echo "growpart failed for /dev/$ROOT_DISK partition $ROOT_PART_NUM. Continuing to resize2fs as the partition might have been grown by other means or already at max size." >&2
        # We don't exit here as resize2fs might still be needed if growpart reported no change.
    fi
else
    echo "Could not determine partition number from $ROOT_DEV. Skipping growpart. This might be a logical volume or a disk image without a partition table an OS is directly installed on."
fi

echo "Attempting to resize filesystem on $ROOT_DEV..."
if /sbin/resize2fs "$ROOT_DEV"; then
    echo "resize2fs successful for $ROOT_DEV."
else
    echo "Error: resize2fs failed for $ROOT_DEV." >&2
    exit 1
fi

echo "Root partition and filesystem resize successful."
echo "Creating flag file $FLAG_FILE to prevent re-running."
if ! touch "$FLAG_FILE"; then
    echo "Error: Failed to create flag file $FLAG_FILE." >&2
    # Exiting with 0 because the primary task (resize) was successful.
    # Failure to create the flag file is a secondary issue, might cause re-run but won't break boot.
    exit 0
fi

exit 0 