#!/bin/bash

# Тестируем логику определения префиксов из over.sh

echo "Тестирование логики определения префиксов:"
echo "=========================================="

# Тест 1: NVMe -> SATA
echo "Тест 1: NVMe -> SATA"
namedisk="sda"
old_disk=$(grep '^device:' sda.dump | cut -d'/' -f3)
echo "Старый диск из dump: $old_disk"

old_is_nvme=$(grep -q "/dev/${old_disk}p" sda.dump && echo "yes" || echo "no")
echo "Был ли исходный диск NVMe: $old_is_nvme"

new_prefix=""
if [[ "$namedisk" =~ ^nvme ]]; then
    new_prefix="p"
fi
echo "Префикс для нового диска: '$new_prefix'"

old_prefix=""
if [[ "$old_is_nvme" == "yes" ]]; then
    old_prefix="p"
fi
echo "Префикс для старого диска: '$old_prefix'"

echo ""
echo "Результат замены:"
temp_dump=$(mktemp)
sed -e "s|^device:.*|device: /dev/$namedisk|" \
    -e "s|/dev/${old_disk}${old_prefix}\([0-9]\)|/dev/$namedisk${new_prefix}\1|g" \
    sda.dump > "$temp_dump"

cat "$temp_dump"
rm -f "$temp_dump"

echo ""
echo "=========================================="
echo "Тест 2: NVMe -> NVMe"
namedisk="nvme1n1"
new_prefix=""
if [[ "$namedisk" =~ ^nvme ]]; then
    new_prefix="p"
fi
echo "Префикс для нового диска: '$new_prefix'"

temp_dump=$(mktemp)
sed -e "s|^device:.*|device: /dev/$namedisk|" \
    -e "s|/dev/${old_disk}${old_prefix}\([0-9]\)|/dev/$namedisk${new_prefix}\1|g" \
    sda.dump > "$temp_dump"

cat "$temp_dump"
rm -f "$temp_dump"