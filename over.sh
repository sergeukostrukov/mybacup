#!/bin/bash
clear
lsblk
echo ' Выберите целевой диск для восстановления (например: sda, vda, nvme0n1):'
read -p " -> " namedisk

# Определяем префикс для разделов
partition_prefix=""
if [[ "$namedisk" =~ ^nvme ]]; then
    partition_prefix="p"
fi

boot="${namedisk}${partition_prefix}1"
root="${namedisk}${partition_prefix}2"

echo " Выбран диск: $namedisk"
echo " boot=$boot"
echo " root=$root"
echo ""
echo " Тип диска: $(if [[ "$namedisk" =~ ^nvme ]]; then echo "NVMe"; else echo "SATA/IDE"; fi)"
sleep 3
#################################################################
# Создаем временный файл с исправленными путями к диску и разделам
temp_dump=$(mktemp)

# Определяем старое имя диска из файла dump
old_disk=$(grep '^device:' sda.dump | cut -d'/' -f3)

# Определяем, был ли исходный диск NVMe (имеет префикс p в именах разделов)
old_is_nvme=$(grep -q "^/dev/${old_disk}p" sda.dump && echo "yes" || echo "no")

# Определяем префикс для нового диска
new_prefix=""
if [[ "$namedisk" =~ ^nvme ]]; then
    new_prefix="p"
fi

# Определяем префикс для старого диска
old_prefix=""
if [[ "$old_is_nvme" == "yes" ]]; then
    old_prefix="p"
fi

# Заменяем device: и все пути к разделам с учетом префиксов
sed -e "s|^device:.*|device: /dev/$namedisk|" \
    -e "s|/dev/${old_disk}${old_prefix}|/dev/$namedisk${new_prefix}|g" \
    sda.dump > "$temp_dump"

sfdisk /dev/$namedisk < "$temp_dump"
rm -f "$temp_dump"
zcat ./sda1.pcl.gz | partclone.vfat -r -N -o /dev/$boot
zcat ./sda2.pcl.gz | partclone.btrfs -r -N -o /dev/$root
clear
reboot
