#!/bin/bash
#===============================================================================
# Скрипт резервного копирования диска для Windows (LiveUSB)
# Запуск с установочного носителя Arch Linux
# Не монтируйте целевой диск к системе
#===============================================================================
# ПРИМЕЧАНИЕ: Раскладка клавиатуры остаётся EN (US).
#       Сообщения на русском (отображаются через шрифт ter-v32b).
#===============================================================================

#------Настройка шрифта (для отображения кириллицы)--------------------
if command -v setfont >/dev/null 2>&1; then
    setfont ter-v32b 2>/dev/null || setfont cybercafe-narrow 2>/dev/null || true
fi

#####---------------Выбор исходного диска-----------------------------
clear
lsblk
echo ' Введите имя копируемого диска (например: sda, vda, sdb):'
read -p " -> " namedisk

boot="${namedisk}1"
root3="${namedisk}3"
root4="${namedisk}4"
echo " Выбран диск: $namedisk"
echo " boot=$boot"
echo " root3=$root3"
echo " root4=$root4"
sleep 3

PS3="Выбор: 1=ПРОДОЛЖИТЬ, 2=ВЫХОД:"
select choice in "ПРОДОЛЖИТЬ" "ВЫХОД"; do
case $REPLY in
    1) break;;
    2) echo "Выход..."; exit;;
    *) echo "Неверный выбор!";;
esac
done
#################################################################
t=$(date +%F-%H%M-%S)
bacdir="win${t}"
mkdir "$bacdir"
clear
echo "Введите описание для этого бекапа:"
read l
echo "$l" >"./$bacdir/readmi.txt"
echo "$(date +%F-%H%M-%S)" >>"./$bacdir/readmi.txt"
sfdisk -d "/dev/$namedisk" >"./$bacdir/sda.dump"
partclone.vfat -c -N -s "/dev/$boot" | gzip -c >"./$bacdir/sda1.pcl.gz"
partclone.ntfs -c -N -s "/dev/$root3" | gzip -c >"./$bacdir/sda3.pcl.gz"
partclone.ntfs -c -N -s "/dev/$root4" | gzip -c >"./$bacdir/sda4.pcl.gz"
###################################################################
#------Создание скрипта восстановления over.sh-------------------------------
cat > "./$bacdir/over.sh" <<'OVER_EOF'
#!/bin/bash
clear
lsblk
echo ' Выберите целевой диск для восстановления (например: sda, vda, sdb):'
read -p " -> " namedisk
boot="${namedisk}1"
root3="${namedisk}3"
root4="${namedisk}4"
echo " Выбран диск: $namedisk"
echo " boot=$boot"
echo " root3=$root3"
echo " root4=$root4"
sleep 3
#################################################################
sfdisk /dev/$namedisk < sda.dump
zcat ./sda1.pcl.gz | partclone.vfat -r -N -o /dev/$boot
zcat ./sda3.pcl.gz | partclone.ntfs -r -N -o /dev/$root3
zcat ./sda4.pcl.gz | partclone.ntfs -r -N -o /dev/$root4
clear
reboot
OVER_EOF
chmod +x "./$bacdir/over.sh"
###################################################################
###################################################################
echo "$(date +%F-%H%M-%S)" >>"./$bacdir/readmi.txt"
