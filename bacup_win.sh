#!/bin/bash
#------Localizaciya------------------------------------------
sed -i s/'#en_US.UTF-8'/'en_US.UTF-8'/g /etc/locale.gen
sed -i s/'#ru_RU.UTF-8'/'ru_RU.UTF-8'/g /etc/locale.gen
echo 'LANG=ru_RU.UTF-8' > /etc/locale.conf
echo 'KEYMAP=ru' > /etc/vconsole.conf
echo 'FONT=cyr-sun16' >> /etc/vconsole.conf
setfont cyr-sun16
locale-gen >/dev/null 2>&1; RETVAL=$?
localectl set-x11-keymap --no-convert us,ru pc105 "" grp:alt_shift_toggle
#####---------------диалог назначения namedisk-----------------------------
clear
lsblk
#fdisk -l
echo '                                 ВВЕДИТЕ ИМЯ КОПИРУЕМОГО ДИСКА  "например: sda vda ....:)"'
read -p "
                                                              -> Введите значение : " namedisk

boot=$namedisk'1'
#root2=$namedisk'2'
root3=$namedisk'3'
root4=$namedisk'4'
echo '                Вы выьрали диск = '$namedisk
echo '                           boot = '$boot
#echo '                           root = '$root2
echo '                           root = '$root3
echo '                           root = '$root4
sleep 3
PS3="Выберите 1 ПРОДОЛЖИТЬ если 2 то ВЫХОД :"
select choice in "ПРОДОЛЖИТЬ" "Exit"; do
case $REPLY in
    1) break;;
    2) echo "see you next time";exit;;
    *) echo "Неправильный выбор !";;
esac
done
#################################################################
t=$(date +%F-%H%M-%S)
bacdir=win$t
mkdir $bacdir
clear
echo "Напечатайте примечания о копии"
read l
echo "$l" >./$bacdir/readmi.txt
echo "$(date +%F-%H%M-%S)" >>./$bacdir/readmi.txt
sfdisk -d /dev/$namedisk >./$bacdir/sda.dump
partclone.vfat -c -N -s /dev/$boot | gzip -c>./$bacdir/sda1.pcl.gz
#partclone.ntfs -c -N -s /dev/$root2 | gzip -c>./$bacdir/sda2.pcl.gz
partclone.ntfs -c -N -s /dev/$root3 | gzip -c>./$bacdir/sda3.pcl.gz
partclone.ntfs -c -N -s /dev/$root4 | gzip -c>./$bacdir/sda4.pcl.gz
###################################################################
echo "#!/bin/bash">./$bacdir/over.sh
#####---------------диалог назначения namedisk-----------------------------
echo "clear">>./$bacdir/over.sh
echo "lsblk">>./$bacdir/over.sh
echo "#fdisk -l">>./$bacdir/over.sh
echo "echo '                                SELECT THE DISK TO RESTORE : sda vda ....:)'">>./$bacdir/over.sh
echo 'read -p "                  -> Entering a value : " namedisk'>>./$bacdir/over.sh
echo 'boot=$namedisk"1"'>>./$bacdir/over.sh
#echo 'root2=$namedisk"2"'>>./$bacdir/over.sh
echo 'root3=$namedisk"3"'>>./$bacdir/over.sh
echo 'root4=$namedisk"4"'>>./$bacdir/over.sh

echo 'echo "                Вы выьрали диск = "$namedisk'>>./$bacdir/over.sh
echo 'echo "                           boot = "$boot'>>./$bacdir/over.sh
#echo 'echo "                           root = "$root2'>>./$bacdir/over.sh
echo 'echo "                           root = "$root3'>>./$bacdir/over.sh
echo 'echo "                           root = "$root4'>>./$bacdir/over.sh
echo "sleep 3">>./$bacdir/over.sh
echo "#################################################################">>./$bacdir/over.sh
echo 'sfdisk /dev/$namedisk < sda.dump'>>./$bacdir/over.sh
echo 'zcat ./sda1.pcl.gz | partclone.vfat -r -N -o /dev/$boot'>>./$bacdir/over.sh
#echo 'zcat ./sda2.pcl.gz | partclone.btrfs -r -N -o /dev/$root2'>>./$bacdir/over.sh
echo 'zcat ./sda3.pcl.gz | partclone.btrfs -r -N -o /dev/$root3'>>./$bacdir/over.sh
echo 'zcat ./sda4.pcl.gz | partclone.btrfs -r -N -o /dev/$root4'>>./$bacdir/over.sh
echo "clear">>./$bacdir/over.sh
echo "reboot">>./$bacdir/over.sh
chmod +x ./$bacdir/over.sh
###################################################################
###################################################################
echo "$(date +%F-%H%M-%S)" >>./$bacdir/readmi.txt
