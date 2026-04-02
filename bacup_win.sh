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

#------Проверка зависимостей---------------------------------
check_dependencies() {
    local missing_deps=()
    
    # Проверяем необходимые команды
    for cmd in sfdisk gzip lsblk; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Проверяем команды partclone
    if ! command -v partclone.vfat >/dev/null 2>&1; then
        missing_deps+=("partclone.vfat")
    fi
    
    if ! command -v partclone.ntfs >/dev/null 2>&1; then
        missing_deps+=("partclone.ntfs")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "ОШИБКА: Не найдены необходимые команды:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        echo ""
        echo "Установите зависимости командой:"
        echo "  pacman -S partclone util-linux gzip"
        echo ""
        echo "Или проверьте установку пакетов:"
        echo "  pacman -Q partclone util-linux gzip"
        exit 1
    fi
    
    echo "Все зависимости проверены успешно"
    echo ""
}

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
    echo " ВЫБОР ДИСКА ДЛЯ КОПИРОВАНИЯ (WINDOWS)"
    echo "=========================================="
    echo ""

    echo "ВСЕ ДОСТУПНЫЕ УСТРОЙСТВА И РАЗДЕЛЫ:"
    echo "===================================="
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL,MODEL 2>/dev/null
    echo ""

    echo "Доступные диски для копирования:"
    local disks=()
    local disk_info=()
    while IFS= read -r line; do
        local name size model
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        model=$(echo "$line" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
        disks+=("$name")
        disk_info+=("$name|$size|$model")
        echo "  [$(( ${#disks[@]} ))] $name  ($size)  $model"
    done < <(lsblk -nd -o NAME,SIZE,MODEL 2>/dev/null | grep -E '^sd|vd|nvme')

    if [[ ${#disks[@]} -eq 0 ]]; then
        echo "Ошибка: диски не найдены"
        exit 1
    fi

    echo ""
    PS3="Выберите номер диска для копирования: "
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

    echo ""
    echo "Выбран диск: $namedisk"
    echo ""
    echo "ПОДРОБНАЯ ИНФОРМАЦИЯ О ВЫБРАННОМ ДИСКЕ:"
    echo "======================================"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL "/dev/$namedisk" 2>/dev/null
    echo ""
    
    sleep 2
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
echo ' Выберите целевой диск для восстановления (например: sda, vda, nvme0n1):'
read -p " -> " namedisk

# Определяем префикс для разделов
partition_prefix=""
if [[ "$namedisk" =~ ^nvme ]]; then
    partition_prefix="p"
fi

boot="${namedisk}${partition_prefix}1"
root3="${namedisk}${partition_prefix}3"
root4="${namedisk}${partition_prefix}4"

echo " Выбран диск: $namedisk"
echo " boot=$boot"
echo " ntfs (система)=$root3"
echo " ntfs (данные)=$root4"
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
    zcat ./sda3.pcl.gz | partclone.ntfs -r -N -o /dev/$root3
    zcat ./sda4.pcl.gz | partclone.ntfs -r -N -o /dev/$root4
    clear
    echo "=========================================="
    echo " ВОССТАНОВЛЕНИЕ ЗАВЕРШЕНО"
    echo "=========================================="
    echo ""
    echo " Все разделы успешно восстановлены на диск /dev/$namedisk"
    echo ""
    echo " Выберите дальнейшее действие:"
    echo " 1) Перезагрузить систему"
    echo " 2) Выйти из скрипта"
    echo ""
    read -p " -> " final_choice
    
    case "$final_choice" in
        1)
            echo "Перезагрузка системы..."
            reboot
            ;;
        *)
            echo "Выход из скрипта."
            echo "Не забудьте перезагрузить систему для загрузки с восстановленного диска."
            exit 0
            ;;
    esac
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
    clear
    check_dependencies
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
