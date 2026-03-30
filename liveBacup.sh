#!/bin/bash
#===============================================================================
# Скрипт резервного копирования диска для Arch Linux (LiveUSB)
# Запуск с установочного носителя Arch Linux
# Не монтируйте целевой диск к системе
#===============================================================================
# ПРИМЕЧАНИЕ: Раскладка клавиатуры остаётся EN (US).
#       Сообщения на русском (отображаются через шрифт ter-v32b).
#===============================================================================

#------Настройка шрифта (для отображения кириллицы)--------------------
# setfont обеспечивает кириллические глифы для вывода; ввод остаётся английским
if command -v setfont >/dev/null 2>&1; then
    setfont ter-v32b 2>/dev/null || setfont cybercafe-narrow 2>/dev/null || true
fi

echo ""
echo "=========================================="
echo " Шрифт настроен ( кириллица включена )"
echo " ВНИМАНИЕ: Ввод только на английском"
echo "=========================================="

#------Уточнение системного времени-----------------------------
echo ""
echo "=========================================="
echo " ТЕКУЩЕЕ СИСТЕМНОЕ ВРЕМЯ:"
echo "$(date '+%A, %d %B %Y  %H:%M:%S')"
echo "=========================================="
echo ""
PS3="Уточнить время?: "
select choice in "Оставить как есть" "Ввести вручную"; do
case $REPLY in
    1) break;;
    2) echo ""
        echo "Введите дату и время в формате:"
        echo "ГГГГ-ММ-ДД ЧЧ:ММ:СС"
        echo "Пример: 2025-03-30 15:45:00"
        read -p " -> " newdate newtime
        if [[ -n "$newdate" && -n "$newtime" ]]; then
            date -s "${newdate} ${newtime}" 2>/dev/null && \
                echo "Время установлено: $(date '+%H:%M:%S')" || \
                echo "Ошибка установки времени"
        else
            echo "Время не изменено"
        fi
        break;;
    *) echo "Неверный выбор!";;
esac
done

#####---------------Выбор исходного диска-----------------------------
clear
lsblk
echo ' Введите имя копируемого диска (например: sda, vda, sdb):'
read -p " -> " namedisk

boot="${namedisk}1"
root="${namedisk}2"
echo " Выбран диск: $namedisk"
echo " boot=$boot"
echo " root=$root"

PS3="Выбор: 1=ПРОДОЛЖИТЬ, 2=ВЫХОД:"
select choice in "ПРОДОЛЖИТЬ" "ВЫХОД"; do
case $REPLY in
    1) break;;
    2) echo "Выход..."; exit;;
    *) echo "Неверный выбор!";;
esac
done
#################################################################
clear
t=$(date +%F-%H%M-%S)
echo '
 В текущей директории будет создана поддиректория для бекапов.
 Формат имени: [префикс][дата]-[время]
 Префикс: необязательно (нажмите Enter для пустого)
 Дата/время: автоматически
'
read -p "
 -> Введите префикс директории бекапа: " namedir
bacdir="${namedir}${t}"
mkdir "$bacdir"
clear
echo "
 Введите описание для этого бекапа:
"
read l
###################################################################
#------Дамп таблицы разделов---------------------------------------
dump_partition_table() {
    sfdisk -d "/dev/$namedisk" >"./$bacdir/sda.dump"
}
#------Создание сжатого бекапа----------------------------------
backup_partitions() {
    dump_partition_table
    echo "$l" >"./$bacdir/readme.txt"
    echo "$(date +%F-%H%M-%S)" >>"./$bacdir/readme.txt"
    echo " Сжатие: $c" >>"./$bacdir/readme.txt"
    partclone.vfat -c -N -s "/dev/$boot" | gzip -c $c >"./$bacdir/sda1.pcl.gz"
    partclone.btrfs -c -N -s "/dev/$root" | gzip -c $c >"./$bacdir/sda2.pcl.gz"
    echo "$(date +%F-%H%M-%S)" >>"./$bacdir/readme.txt"
}
#------------------------------------------------------------------
echo '

 Выберите степень сжатия архива:
 1 - Быстрое (низкое сжатие)
 2 - Сбалансированное (среднее)
 3 - Максимальное (медленное)
 4 - Выход без создания бекапа

'
PS3="Выберите сжатие (4=выход):"
select choice in "Быстрое" "Сбалансированное" "Максимальное" "Выход"; do
case $REPLY in
    1) c='--fast'; break;;
    2) c='-6'; break;;
    3) c='--best'; break;;
    4) exit;;
    *) echo "Неверный выбор!";;
esac
done
###########################################################################
#------Процесс бекапа с измерением времени-------------------------

DT_START=$(date +%s)

backup_partitions

DT_END=$(date +%s)
DT_TOTAL=$(expr $DT_END - $DT_START)

Hours=$(( DT_TOTAL / 3600 ))
Minutes=$(( (DT_TOTAL - Hours * 3600) / 60 ))
Seconds=$(( DT_TOTAL - (Hours * 3600 + Minutes * 60) ))
echo "Общее время: $Hours ч $Minutes м $Seconds с" >>"./$bacdir/readme.txt"

###########################################################################
#------Создание скрипта восстановления over.sh-------------------------------
cat > "./$bacdir/over.sh" <<'OVER_EOF'
#!/bin/bash
clear
lsblk
echo ' Выберите целевой диск для восстановления (например: sda, vda, sdb):'
read -p " -> " namedisk
boot="${namedisk}1"
root="${namedisk}2"
echo " Выбран диск: $namedisk"
echo " boot=$boot"
echo " root=$root"
sleep 3
#################################################################
sfdisk /dev/$namedisk < sda.dump
zcat ./sda1.pcl.gz | partclone.vfat -r -N -o /dev/$boot
zcat ./sda2.pcl.gz | partclone.btrfs -r -N -o /dev/$root
clear
reboot
OVER_EOF
chmod +x "./$bacdir/over.sh"
###################################################################
