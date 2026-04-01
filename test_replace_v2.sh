#!/bin/bash
# Тест 1: NVMe -> SATA
echo "=== Тест 1: NVMe -> SATA ==="
namedisk="sda"
temp_dump=$(mktemp)
old_disk="nvme0n1"
old_is_nvme="yes"
new_prefix=""
old_prefix="p"
sed -e "s|^device:.*|device: /dev/$namedisk|" \
    -e "s|/dev/${old_disk}${old_prefix}|/dev/$namedisk${new_prefix}|g" \
    test_sda.dump > "$temp_dump"
cat "$temp_dump"
echo ""
# Тест 2: SATA -> NVMe
echo "=== Тест 2: SATA -> NVMe ==="
cat > test_sata.dump << 'TEST'
label: gpt
device: /dev/sda
unit: sectors
/dev/sda1 : start=2048, size=2097152
/dev/sda2 : start=2099200, size=1998307328
TEST
namedisk="nvme0n1"
old_disk="sda"
old_is_nvme="no"
new_prefix="p"
old_prefix=""
sed -e "s|^device:.*|device: /dev/$namedisk|" \
    -e "s|/dev/${old_disk}${old_prefix}|/dev/$namedisk${new_prefix}|g" \
    test_sata.dump
rm -f "$temp_dump" test_sata.dump
