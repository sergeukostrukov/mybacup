#!/bin/bash
echo "=== Тест логики замены для sfdisk ==="
echo ""
echo "1. Исходный файл sda.dump (создан с диска nvme0n1):"
cat << 'DUMP'
label: gpt
label-id: 1A2BFA5E-B951-4D0E-8E7E-DD6E93DB6AD5
device: /dev/nvme0n1
unit: sectors
first-lba: 34
last-lba: 2000409230
sector-size: 512

/dev/nvme0n1p1 : start=2048, size=2097152, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
/dev/nvme0n1p2 : start=2099200, size=1998307328, type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
DUMP
echo ""
echo "2. Пользователь выбирает диск 'sda' для восстановления"
namedisk="sda"
echo "Выбран диск: $namedisk"
echo ""
echo "3. Логика замены из over.sh:"
old_disk="nvme0n1"
old_is_nvme="yes"
new_prefix=""
old_prefix="p"
echo "Старый диск: $old_disk"
echo "Новый диск: $namedisk"
echo "Старый префикс: '$old_prefix' (NVMe)"
echo "Новый префикс: '$new_prefix' (SATA)"
echo ""
echo "4. Результат после замены (что получит sfdisk):"
sed -e "s|^device:.*|device: /dev/$namedisk|" \
    -e "s|/dev/${old_disk}${old_prefix}|/dev/$namedisk${new_prefix}|g" << 'DUMP'
label: gpt
label-id: 1A2BFA5E-B951-4D0E-8E7E-DD6E93DB6AD5
device: /dev/nvme0n1
unit: sectors
first-lba: 34
last-lba: 2000409230
sector-size: 512

/dev/nvme0n1p1 : start=2048, size=2097152, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B
/dev/nvme0n1p2 : start=2099200, size=1998307328, type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
DUMP
echo ""
echo "5. Этот исправленный файл передается в sfdisk:"
echo "   sfdisk /dev/$namedisk < исправленный_файл"
echo ""
echo "Таким образом, в таблицу разделов диска sda будут записаны"
echo "правильные пути: /dev/sda1 и /dev/sda2"
