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
root=$namedisk'2'
echo '                Вы выьрали диск = '$namedisk
echo '                           boot = '$boot
echo '                           root = '$root

PS3="Выберите 1 ПРОДОЛЖИТЬ если 2 то ВЫХОД :"
select choice in "ПРОДОЛЖИТЬ" "Exit"; do
case $REPLY in
    1) break;;
    2) echo "see you next time";exit;;
    *) echo "Неправильный выбор !";;
esac
done
#################################################################
clear
t=$(date +%F-%H%M-%S)
echo '



                В текущей директории будет создана поддиректория для размещение бекапов.
                Наименование директории состоит из двух частей.
                Первая часть имени - на ваше усмотрение (можно оставить пустым и нажать "Enter").
                Вторая часть имени - текущая дата.
'
read -p "

                                                        -> Введите первую часть названия директории : " namedir
bacdir=$namedir$t
mkdir $bacdir
clear
echo "

            Напечатайте краткую информацию о создаваемом архире

"
read l
###################################################################
#----------------Запись дамп диска в файл--sda.dump----------------
damp_() { 
    sfdisk -d /dev/$namedisk >./$bacdir/sda.dump
}
#----------------------функция создания бекапа --------------------
pclgz() {
    damp_
    echo "$l" >./$bacdir/readme.txt
    echo "$(date +%F-%H%M-%S)" >>./$bacdir/readme.txt
    echo " Cжатие архива $c " >>./$bacdir/readme.txt
    partclone.vfat -c -N -s /dev/$boot | gzip -c $c>./$bacdir/sda1.pcl.gz
    partclone.btrfs -c -N -s /dev/$root | gzip -c $c>./$bacdir/sda2.pcl.gz
    echo "$(date +%F-%H%M-%S)" >>./$bacdir/readme.txt
}
#------------------------------------------------------------------
echo '


                     Выберите степень сжатия архива.
        Чем больше степень сжатие тем дольше создаётся архив.
        Без сжатия максимальная скорость создания архива.
        Среднее сжатие - оптимальные параметры по скорости и степени сжатия.

'
PS3="Выберите степень сжатия. Если 4 то выход :"
select choice in "Минимальное сжатие" "Среднее сжатие" "Максимальное сжатие" "ВЫХОД без создания becap"; do
case $REPLY in
    1) c='--fast';break;;
    2) c='-6';break;;
    3) c='--best';break;;
    4) exit;;
    *) echo "Неправильный выбор !";;
esac
done
###########################################################################
#-------------------Сам процесс Becap--------------------------------------
time -E -a -o ./$bacdir/readme.txt pclgz
###########################################################################
#-Секция создания скрипта over.sh для восстановления из бекапа на физический диск
echo "#!/bin/bash">./$bacdir/over.sh
#####---------------диалог назначения диска куда восстанавливать-----------------------------
echo "clear">>./$bacdir/over.sh
echo "lsblk">>./$bacdir/over.sh
echo "#fdisk -l">>./$bacdir/over.sh
echo "echo '                                 SELECT THE DISK TO RESTORE : sda vda sdc sdd....:)'">>./$bacdir/over.sh
echo 'read -p "                  -> ENTERING A VALUE : " namedisk'>>./$bacdir/over.sh
echo 'boot=$namedisk"1"'>>./$bacdir/over.sh
echo 'root=$namedisk"2"'>>./$bacdir/over.sh
echo 'echo "                Вы выьрали диск = "$namedisk'>>./$bacdir/over.sh
echo 'echo "                           boot = "$boot'>>./$bacdir/over.sh
echo 'echo "                           root = "$root'>>./$bacdir/over.sh
echo "sleep 3">>./$bacdir/over.sh
echo "#################################################################">>./$bacdir/over.sh
echo 'sfdisk /dev/$namedisk < sda.dump'>>./$bacdir/over.sh
echo 'zcat ./sda1.pcl.gz | partclone.vfat -r -N -o /dev/$boot'>>./$bacdir/over.sh
echo 'zcat ./sda2.pcl.gz | partclone.btrfs -r -N -o /dev/$root'>>./$bacdir/over.sh
echo "clear">>./$bacdir/over.sh
echo "reboot">>./$bacdir/over.sh
chmod +x ./$bacdir/over.sh
###################################################################
###################################################################

