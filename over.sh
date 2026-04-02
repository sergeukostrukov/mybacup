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
old_is_nvme=$(grep -q "/dev/${old_disk}p" sda.dump && echo "yes" || echo "no")

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
    -e "s|/dev/${old_disk}${old_prefix}\([0-9]\)|/dev/$namedisk${new_prefix}\1|g" \
    sda.dump > "$temp_dump"

# Показываем содержимое исправленного файла и спрашиваем подтверждение
echo ""
echo "=========================================="
echo "Содержимое исправленного файла sda.dump:"
echo "=========================================="
cat "$temp_dump"
echo "=========================================="
echo ""
echo "Старое имя диска: $old_disk (префикс: '$old_prefix')"
echo "Новое имя диска: $namedisk (префикс: '$new_prefix')"
echo ""
echo "Выберите действие:"
echo "1) Применить изменения таблицы разделов (рекомендуется)"
echo "2) Использовать оригинальный файл dump (без подмены путей)"
echo "3) Отменить восстановление"
read -p " -> " action_choice

case "$action_choice" in
    1)
        echo "Применяем изменения таблицы разделов..."
        sfdisk /dev/$namedisk < "$temp_dump"
        ;;
    2)
        echo "Используем оригинальный файл dump..."
        sfdisk /dev/$namedisk < sda.dump
        ;;
    *)
        echo "Восстановление отменено."
        rm -f "$temp_dump"
        exit 1
        ;;
esac

rm -f "$temp_dump"
zcat ./sda1.pcl.gz | partclone.vfat -r -N -o /dev/$boot
zcat ./sda2.pcl.gz | partclone.btrfs -r -N -o /dev/$root
clear
reboot
