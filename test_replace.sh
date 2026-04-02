#!/bin/bash

# Тестируем логику подмены путей из over.sh

# Тест 1: SATA -> SATA
echo "Тест 1: SATA -> SATA (sda -> sdb)"
namedisk="sdb"
old_disk="sda"
old_is_nvme="no"
new_prefix=""
old_prefix=""

echo "Исходный файл:"
cat test_sda.dump
echo ""
echo "Результат замены:"
sed -e "s|^device:.*|device: /dev/$namedisk|" \
    -e "s|/dev/${old_disk}${old_prefix}\([0-9]\)|/dev/$namedisk${new_prefix}\1|g" \
    test_sda.dump
echo ""

# Тест 2: SATA -> NVMe
echo "Тест 2: SATA -> NVMe (sda -> nvme0n1)"
namedisk="nvme0n1"
old_disk="sda"
old_is_nvme="no"
new_prefix="p"
old_prefix=""

echo "Результат замены:"
sed -e "s|^device:.*|device: /dev/$namedisk|" \
    -e "s|/dev/${old_disk}${old_prefix}\([0-9]\)|/dev/$namedisk${new_prefix}\1|g" \
    test_sda.dump
echo ""

# Тест 3: NVMe -> NVMe
echo "Тест 3: NVMe -> NVMe (nvme0n1 -> nvme1n1)"
# Создаем NVMe dump
cat > test_nvme.dump << EOF
label: gpt
label-id: 12345678-1234-1234-1234-123456789012
device: /dev/nvme0n1
unit: sectors
first-lba: 2048
last-lba: 1000214527

/dev/nvme0n1p1 : start=        2048, size=     1048576, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, uuid=11111111-2222-3333-4444-555555555555
/dev/nvme0n1p2 : start=     1050624, size=    41943040, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, uuid=66666666-7777-8888-9999-000000000000
EOF

namedisk="nvme1n1"
old_disk="nvme0n1"
old_is_nvme="yes"
new_prefix="p"
old_prefix="p"

echo "Исходный файл (NVMe):"
cat test_nvme.dump
echo ""
echo "Результат замены:"
sed -e "s|^device:.*|device: /dev/$namedisk|" \
    -e "s|/dev/${old_disk}${old_prefix}\([0-9]\)|/dev/$namedisk${new_prefix}\1|g" \
    test_nvme.dump
echo ""

# Тест 4: NVMe -> SATA
echo "Тест 4: NVMe -> SATA (nvme0n1 -> sda)"
namedisk="sda"
old_disk="nvme0n1"
old_is_nvme="yes"
new_prefix=""
old_prefix="p"

echo "Результат замены:"
sed -e "s|^device:.*|device: /dev/$namedisk|" \
    -e "s|/dev/${old_disk}${old_prefix}\([0-9]\)|/dev/$namedisk${new_prefix}\1|g" \
    test_nvme.dump