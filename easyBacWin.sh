#!/bin/bash
#===============================================================================
# Упрощенный скрипт резервного копирования диска для Windows (LiveUSB)
# Автоматически определяет разделы: №1 boot (vfat), №3 системная NTFS
# Запуск с установочного носителя Arch Linux
#===============================================================================
# ПРИМЕЧАНИЕ: Раскладка клавиатуры остаётся EN (US).
#       Сообщения на русском (отображаются через шрифт ter-v32b).
#===============================================================================

set -euo pipefail

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo "Ошибка: для работы скрипта требуются права root."
    echo "Запустите скрипт с sudo: sudo ./easyBacWin.sh"
    exit 1
fi

#------Глобальные переменные---------------------------------
namedisk=""
boot=""
system=""
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
    
    # Определяем префикс для разделов
    local partition_prefix=""
    if [[ "$namedisk" =~ ^nvme ]]; then
        partition_prefix="p"
    fi
    
    # Автоматически определяем разделы (Windows схема с 2 разделами)
    boot="${namedisk}${partition_prefix}1"
    system="${namedisk}${partition_prefix}2"
    
    echo "Разделы определены автоматически (Windows схема с 2 разделами):"
    echo "  boot (vfat):    $boot"
    echo "  system (ntfs):  $system"
    
    # Проверяем существование разделов
    if [[ ! -b "/dev/$boot" ]]; then
        echo "Ошибка: раздел /dev/$boot не найден"
        exit 1
    fi
    
    if [[ ! -b "/dev/$system" ]]; then
        echo "Ошибка: раздел /dev/$system не найден"
        exit 1
    fi
    
    # Проверяем тип файловой системы разделов
    echo ""
    echo "Проверка типов файловых систем:"
    local boot_fstype system_fstype
    boot_fstype=$(lsblk -no FSTYPE "/dev/$boot" 2>/dev/null || echo "")
    system_fstype=$(lsblk -no FSTYPE "/dev/$system" 2>/dev/null || echo "")
    
    echo "  $boot: $boot_fstype"
    echo "  $system: $system_fstype"
    
    if [[ "$boot_fstype" != "vfat" ]] && [[ "$boot_fstype" != "fat32" ]]; then
        echo "Предупреждение: boot раздел имеет тип '$boot_fstype', ожидается vfat/fat32"
    fi
    
    if [[ "$system_fstype" != "ntfs" ]]; then
        echo "Предупреждение: system раздел имеет тип '$system_fstype', ожидается ntfs"
    fi
    
    echo "Разделы проверены и готовы к копированию"
    
    sleep 2
}

confirm_selection() {
    clear
    echo "=========================================="
    echo " ПОДТВЕРЖДЕНИЕ ВЫБОРА (WINDOWS)"
    echo "=========================================="
    echo ""
    echo " Диск:      $namedisk"
    echo " boot:      $boot"
    echo " system:    $system"
    echo ""
    echo " Тип диска: $(if [[ "$namedisk" =~ ^nvme ]]; then echo "NVMe"; else echo "SATA/IDE"; fi)"
    echo ""
    echo " ПРОВЕРЬТЕ ПРАВИЛЬНОСТЬ ВЫБОРА!"
    echo ""

    PS3="Подтвердить?: "
    select choice in "ПРОДОЛЖИТЬ" "ВЫБРАТЬ ЗАНОВО" "ВЫХОД"; do
        case $REPLY in
            1) break;;
            2)
                select_disk
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
    clear
    echo "=========================================="
    echo " ПРЕДПРОСМОТР КОПИРОВАНИЯ (WINDOWS)"
    echo "=========================================="
    echo ""
    echo " Диск:         $namedisk"
    echo " boot:         /dev/$boot"
    echo " system:       /dev/$system"
    echo " Сжатие:       $compression"
    echo " Директория:   $bacdir"
    echo ""
    echo " Файлы бекапа:"
    echo "  $bacdir/sda.dump"
    echo "  $bacdir/sda1.pcl.gz"
    echo "  $bacdir/sda2.pcl.gz"
    echo "  $bacdir/readme.txt"
    echo "  $bacdir/over.sh"
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
    echo " Сжатие: $compression" >>"./$bacdir/readme.txt"

    echo " Копирование boot-раздела ($boot)..."
    partclone.vfat -c -N -s "/dev/$boot" | gzip -c $compression >"./$bacdir/sda1.pcl.gz"

    echo " Копирование system-раздела ($system)..."
    partclone.ntfs -c -N -s "/dev/$system" | gzip -c $compression >"./$bacdir/sda2.pcl.gz"

    echo "$(date +%F-%H%M-%S)" >>"./$bacdir/readme.txt"
}

create_restore_script() {
    cat > "./$bacdir/over.sh" <<'OVER_EOF'
#!/bin/bash

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo "Ошибка: для работы скрипта требуются права root."
    echo "Запустите скрипт с sudo: sudo ./over.sh"
    exit 1
fi

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
system="${namedisk}${partition_prefix}2"

echo " Выбран диск: $namedisk"
echo " boot=$boot"
echo " system=$system"
echo ""
echo " Тип диска: $(if [[ "$namedisk" =~ ^nvme ]]; then echo "NVMe"; else echo "SATA/IDE"; fi)"
echo " ВНИМАНИЕ: Восстанавливаются только boot и system разделы!"
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
    zcat ./sda2.pcl.gz | partclone.ntfs -r -N -o /dev/$system
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
    echo " БЕКАП WINDOWS ЗАВЕРШЁН"
    echo "=========================================="
    echo ""
    echo " Директория: $bacdir"
    echo " Время:      $hours ч $minutes м $seconds с"
    echo ""
    echo " Скопированы разделы:"
    echo "  boot (vfat):   $boot"
    echo "  system (ntfs): $system"
    echo ""
    echo " Файлы бекапа:"
    echo "  sda.dump      - таблица разделов"
    echo "  sda1.pcl.gz   - boot раздел"
    echo "  sda2.pcl.gz   - system раздел"
    echo "  readme.txt    - информация о бекапе"
    echo "  over.sh       - скрипт восстановления"
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
    confirm_selection
    create_backup_dir
    select_compression
    backup
}

main "$@"