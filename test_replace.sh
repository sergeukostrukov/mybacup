#!/bin/bash
namedisk="sda"
temp_dump=$(mktemp)
old_disk=$(grep '^device:' test_sda.dump | cut -d'/' -f3)
echo "Старый диск: $old_disk"
echo "Новый диск: $namedisk"
sed -e "s|^device:.*|device: /dev/$namedisk|" \
    -e "s|/dev/${old_disk}|/dev/$namedisk|g" \
    test_sda.dump > "$temp_dump"
echo "Результат замены:"
cat "$temp_dump"
rm -f "$temp_dump"
