#!/bin/bash
# Тестовый скрипт для проверки логики замены имен устройств

# Используем тестовый файл
cp test_sata.dump sda.dump.test

echo "=== ТЕСТ 1: Восстановление SATA->SATA (sda -> sdb) ==="
namedisk="sdb"

# Определяем старое имя диска из файла dump
old_disk=$(grep '^device:' sda.dump.test | cut -d'/' -f3)
echo "Старое имя диска из sda.dump: $old_disk"

# Определяем, был ли исходный диск NVMe (имеет префикс p в именах разделов)
old_is_nvme=$(grep -q "/dev/${old_disk}p" sda.dump.test && echo "yes" || echo "no")
echo "Исходный диск был NVMe? $old_is_nvme"

# Определяем префикс для нового диска
new_prefix=""
if [[ "$namedisk" =~ ^nvme ]]; then
    new_prefix="p"
fi
echo "Префикс для нового диска: '$new_prefix'"

# Определяем префикс для старого диска
old_prefix=""
if [[ "$old_is_nvme" == "yes" ]]; then
    old_prefix="p"
fi
echo "Префикс для старого диска: '$old_prefix'"

# Заменяем device: и все пути к разделам с учетом префиксов
echo "Заменяем:"
echo "  Старое устройство: /dev/${old_disk}${old_prefix}"
echo "  Новое устройство: /dev/$namedisk${new_prefix}"

temp_dump=$(mktemp)
sed -e "s|^device:.*|device: /dev/$namedisk|" \
    -e "s|/dev/${old_disk}${old_prefix}\([0-9]\)|/dev/$namedisk${new_prefix}\1|g" \
    sda.dump.test > "$temp_dump"

echo "Результат замены:"
cat "$temp_dump"
rm -f "$temp_dump"

echo ""
echo "=== ТЕСТ 2: Восстановление SATA->NVMe (sda -> nvme0n1) ==="
namedisk="nvme0n1"

old_disk=$(grep '^device:' sda.dump.test | cut -d'/' -f3)
old_is_nvme=$(grep -q "/dev/${old_disk}p" sda.dump.test && echo "yes" || echo "no")
new_prefix=""
if [[ "$namedisk" =~ ^nvme ]]; then
    new_prefix="p"
fi
old_prefix=""
if [[ "$old_is_nvme" == "yes" ]]; then
    old_prefix="p"
fi

temp_dump=$(mktemp)
sed -e "s|^device:.*|device: /dev/$namedisk|" \
    -e "s|/dev/${old_disk}${old_prefix}\([0-9]\)|/dev/$namedisk${new_prefix}\1|g" \
    sda.dump.test > "$temp_dump"

echo "Результат замены:"
cat "$temp_dump"
rm -f "$temp_dump"

echo ""
echo "=== ТЕСТ 3: Восстановление NVMe->SATA (nvme0n1 -> sda) ==="
# Создаем тестовый файл для NVMe
cat > test_nvme.dump << 'EOF'
label: gpt
label-id: 1A2BFA5E-B951-4D0E-8E7E-DD6E93DB6AD5
device: /dev/nvme0n1
unit: sectors
first-lba: 34
last-lba: 2000409230
sector-size: 512

/dev/nvme0n1p1 : start=        2048, size=     2097152, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, uuid=32A48C95-B27F-4484-987D-640CFEAEC172
/dev/nvme0n1p2 : start=     2099200, size=  1998307328, type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709, uuid=629C6E02-DB4D-4801-9A2F-9A430BC7677B
EOF

cp test_nvme.dump sda.dump.test
namedisk="sda"

old_disk=$(grep '^device:' sda.dump.test | cut -d'/' -f3)
old_is_nvme=$(grep -q "/dev/${old_disk}p" sda.dump.test && echo "yes" || echo "no")
new_prefix=""
if [[ "$namedisk" =~ ^nvme ]]; then
    new_prefix="p"
fi
old_prefix=""
if [[ "$old_is_nvme" == "yes" ]]; then
    old_prefix="p"
fi

temp_dump=$(mktemp)
sed -e "s|^device:.*|device: /dev/$namedisk|" \
    -e "s|/dev/${old_disk}${old_prefix}\([0-9]\)|/dev/$namedisk${new_prefix}\1|g" \
    sda.dump.test > "$temp_dump"

echo "Результат замены:"
cat "$temp_dump"
rm -f "$temp_dump"

# Очистка
rm -f sda.dump.test test_sata.dump test_nvme.dump
echo ""
echo "Тестирование завершено"