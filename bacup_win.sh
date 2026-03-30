#!/bin/bash
#===============================================================================
# Скрипт резервного копирования диска для Windows (LiveUSB)
# Запуск с установочного носителя Arch Linux
# Не монтируйте целевой диск к системе
#===============================================================================
# ПРИМЕЧАНИЕ: Раскладка клавиатуры остаётся EN (US).
#       Сообщения на русском (отображаются через шрифт ter-v32b).
#===============================================================================

set -euo pipefail

#------Глобальные переменные---------------------------------
namedisk=""
boot=""
root3=""
root4=""
bacdir=""
compression=""

#===============================================================================
# Функции
#===============================================================================

setup_font() {
    if command -v setfont >/dev/null 2>&1; then
        setfont ter-v32b 2>/dev/null || setfont cybercafe-narrow 2>/dev/null || true
    fi

    echo ""
    echo "=========================================="
    echo " Шрифт настроен ( кириллица включена )"
    echo " ВНИМАНИЕ: Ввод только на английском"
    echo "=========================================="
}

show_time() {
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
            2)
                echo ""
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
                break
                ;;
            *) echo "Неверный выбор!";;
        esac
    done
}

select_disk() {
    clear
    echo "=========================================="
    echo " ВЫБОР ДИСКА"
    echo "=========================================="
    echo ""

    echo "Доступные диски:"
    local disks=()
    local disk_info=()
    while IFS= read -r line; do
        local name size
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        disks+=("$name")
        disk_info+=("$name|$size")
        echo "  [$(( ${#disks[@]} ))] $name  ($size)"
    done < <(lsblk -nd -o NAME,SIZE 2>/dev/null | grep -E '^sd|vd|nvme')

    if [[ ${#disks[@]} -eq 0 ]]; then
        echo "Ошибка: диски не найдены"
        exit 1
    fi

    echo ""
    PS3="Выберите номер диска: "
    select choice in "${disks[@]}" "ВЫХОД"; do
        if [[ "$choice" == "ВЫХОД" ]]; then
            echo "Выход..."
            exit 0
        fi
        if [[ -n "$choice" ]]; then
            namedisk="$choice"
            break
        fi
        echo "Неверный выбор!"
    done

    echo "Выбран диск: $namedisk"
    sleep 1
}

select_partitions() {
    clear
    echo "=========================================="
    echo " РАЗДЕЛЫ ДИСКА: $namedisk"
    echo "=========================================="
    echo ""
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT "/dev/$namedisk" 2>/dev/null
    echo ""

    echo "Доступные разделы:"
    local partitions=()
    local part_info=()
    local num=1
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local part fstype
        part=$(echo "$line" | awk '{print $1}')
        fstype=$(echo "$line" | awk '{print $2}')
        [[ -n "$part" ]] || continue
        partitions+=("$part:$fstype")
        part_info+=("$num|$part|$fstype")
        echo "  [$num] $part  ($fstype)"
        ((num++))
    done < <(lsblk --raw -o NAME,FSTYPE "/dev/$namedisk" 2>/dev/null | awk '/p[0-9]/ || ($1 ~ /[a-z][0-9]$/ && $1 !~ /^nvme/ && $1 !~ /^vd/ && $1 !~ /^sd$/)')

    if [[ ${#partitions[@]} -eq 0 ]]; then
        echo "Ошибка: разделы не найдены"
        exit 1
    fi

    echo ""
    PS3="Выберите номер boot-раздела: "
    select choice in "${partitions[@]}" "ВЫХОД"; do
        if [[ "$choice" == "ВЫХОД" ]]; then
            echo "Выход..."
            exit 0
        fi
        if [[ -n "$choice" ]]; then
            boot="$choice"
            break
        fi
        echo "Неверный выбор!"
    done

    echo ""
    PS3="Выберите номер ntfs-раздела (система Windows): "
    select choice in "${partitions[@]}" "ВЫХОД"; do
        if [[ "$choice" == "ВЫХОД" ]]; then
            echo "Выход..."
            exit 0
        fi
        if [[ -n "$choice" ]]; then
            root3="$choice"
            break
        fi
        echo "Неверный выбор!"
    done

    echo ""
    PS3="Выберите номер ntfs-раздела (данные пользователя): "
    select choice in "${partitions[@]}" "ВЫХОД"; do
        if [[ "$choice" == "ВЫХОД" ]]; then
            echo "Выход..."
            exit 0
        fi
        if [[ -n "$choice" ]]; then
            root4="$choice"
            break
        fi
        echo "Неверный выбор!"
    done
}

confirm_selection() {
    clear
    echo "=========================================="
    echo " ПОДТВЕРЖДЕНИЕ ВЫБОРА"
    echo "=========================================="
    echo ""
    echo " Диск:          $namedisk"
    echo " boot:          $boot"
    echo " ntfs (система): $root3"
    echo " ntfs (данные): $root4"
    echo ""

    PS3="Подтвердить?: "
    select choice in "ПРОДОЛЖИТЬ" "ВЫБРАТЬ ЗАНОВО" "ВЫХОД"; do
        case $REPLY in
            1) break;;
            2)
                select_disk
                select_partitions
                confirm_selection
                return
                ;;
            3) echo "Выход..."; exit 0;;
            *) echo "Неверный выбор!";;
        esac
    done
}

create_backup_dir() {
    clear
    echo "
 В текущей директории будет создана поддиректория для бекапов.
 Формат имени: [префикс][дата]-[время]
 Префикс: необязательно (нажмите Enter для пустого)
 Дата/время: автоматически
 "
    read -p "
 -> Введите префикс директории бекапа: " namedir
    bacdir="${namedir}$(date +%F-%H%M-%S)"
    mkdir "$bacdir"

    clear
    echo "
 Введите описание для этого бекапа:
 "
    read description
    echo "$description" >"./$bacdir/readme.txt"
    echo "$(date +%F-%H%M-%S)" >>"./$bacdir/readme.txt"
}

select_compression() {
    clear
    echo '
 Выберите степень сжатия архива:
 1 - Быстрое (низкое сжатие)
 2 - Сбалансированное (среднее)
 3 - Максимальное (медленное)
 '
    PS3="Выберите сжатие: "
    select choice in "Быстрое" "Сбалансированное" "Максимальное" "Выход"; do
        case $REPLY in
            1) compression='--fast'; break;;
            2) compression='-6'; break;;
            3) compression='--best'; break;;
            4) exit;;
            *) echo "Неверный выбор!";;
        esac
    done
}

dump_partition_table() {
    echo " Сохранение таблицы разделов..."
    sfdisk -d "/dev/$namedisk" >"./$bacdir/sda.dump"
}

preview_backup() {
    local boot_part ntfs3_part ntfs4_part
    boot_part="${boot%%:*}"
    boot_part="${boot_part//[^a-zA-Z0-9]/}"
    ntfs3_part="${root3%%:*}"
    ntfs3_part="${ntfs3_part//[^a-zA-Z0-9]/}"
    ntfs4_part="${root4%%:*}"
    ntfs4_part="${ntfs4_part//[^a-zA-Z0-9]/}"

    clear
    echo "=========================================="
    echo " ПРЕДКПРОСМОТР КОПИРОВАНИЯ"
    echo "=========================================="
    echo ""
    echo " Диск:          $namedisk"
    echo " boot (исх):    [$boot]"
    echo " boot (устр):   /dev/$boot_part"
    echo " ntfs сист:     [$root3]"
    echo " ntfs сист:     /dev/$ntfs3_part"
    echo " ntfs данные:   [$root4]"
    echo " ntfs данные:   /dev/$ntfs4_part"
    echo " Сжатие:        $compression"
    echo " Директория:    $bacdir"
    echo ""

    PS3="Начать копирование?: "
    select choice in "НАЧАТЬ" "ОТМЕНА"; do
        case $REPLY in
            1) return;;
            2) echo "Отмена..."; exit 0;;
            *) echo "Неверный выбор!";;
        esac
    done
}

backup_partitions() {
    local boot_part ntfs3_part ntfs4_part
    boot_part="${boot%%:*}"
    boot_part="${boot_part//[^a-zA-Z0-9]/}"
    ntfs3_part="${root3%%:*}"
    ntfs3_part="${ntfs3_part//[^a-zA-Z0-9]/}"
    ntfs4_part="${root4%%:*}"
    ntfs4_part="${ntfs4_part//[^a-zA-Z0-9]/}"

    echo " Сжатие: $compression" >>"./$bacdir/readme.txt"

    echo " Копирование boot-раздела ($boot_part)..."
    partclone.vfat -c -N -s "/dev/$boot_part" | gzip -c $compression >"./$bacdir/sda1.pcl.gz"

    echo " Копирование ntfs-раздела ($ntfs3_part)..."
    partclone.ntfs -c -N -s "/dev/$ntfs3_part" | gzip -c $compression >"./$bacdir/sda3.pcl.gz"

    echo " Копирование ntfs-раздела ($ntfs4_part)..."
    partclone.ntfs -c -N -s "/dev/$ntfs4_part" | gzip -c $compression >"./$bacdir/sda4.pcl.gz"

    echo "$(date +%F-%H%M-%S)" >>"./$bacdir/readme.txt"
}

create_restore_script() {
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
echo " ntfs (система)=$root3"
echo " ntfs (данные)=$root4"
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
}

backup() {
    local dt_start dt_end dt_total hours minutes seconds

    preview_backup

    dt_start=$(date +%s)

    dump_partition_table
    backup_partitions

    dt_end=$(date +%s)
    dt_total=$((dt_end - dt_start))

    hours=$((dt_total / 3600))
    minutes=$(((dt_total - hours * 3600) / 60))
    seconds=$((dt_total - (hours * 3600 + minutes * 60)))

    echo "Общее время: $hours ч $minutes м $seconds с" >>"./$bacdir/readme.txt"

    create_restore_script

    clear
    echo "=========================================="
    echo " БЕКАП ЗАВЕРШЁН"
    echo "=========================================="
    echo ""
    echo " Директория: $bacdir"
    echo " Время:      $hours ч $minutes м $seconds с"
    echo ""
}

#===============================================================================
# Главная программа
#===============================================================================

main() {
    setup_font
    show_time
    select_disk
    select_partitions
    confirm_selection
    create_backup_dir
    select_compression
    backup
}

main "$@"
