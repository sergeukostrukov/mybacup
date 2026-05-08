#!/bin/bash
#===============================================================================
# arch_bacup.sh — Резервное копирование Arch Linux (LiveUSB)
# Интерфейс: whiptail (диалоговые окна)
# Целевая ФС: boot=fat32, root=btrfs (два раздела)
# Запуск с установочного носителя Arch Linux
#===============================================================================
# ПРИМЕЧАНИЕ: Раскладка клавиатуры остаётся EN (US).
#       Сообщения на русском (отображаются через шрифт ter-v32b).
#===============================================================================

set -o pipefail

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    whiptail --msgbox "Ошибка: для работы скрипта требуются права root.\n\
Запустите скрипт с sudo: sudo ./arch_bacup.sh" 10 60
    exit 1
fi

#------Глобальные переменные---------------------------------
namedisk=""
boot=""
root=""
bacdir=""
compression=""

#------Проверка зависимостей---------------------------------
check_dependencies() {
    local missing_deps=()

    for cmd in sfdisk gzip lsblk whiptail; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if ! command -v partclone.vfat >/dev/null 2>&1; then
        missing_deps+=("partclone.vfat")
    fi

    if ! command -v partclone.btrfs >/dev/null 2>&1; then
        missing_deps+=("partclone.btrfs")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        local msg="ОШИБКА: Не найдены необходимые команды:\n"
        for dep in "${missing_deps[@]}"; do
            msg="${msg}  - ${dep}\n"
        done
        msg="${msg}\nУстановите:\n  pacman -S partclone util-linux gzip newt"
        whiptail --msgbox "$msg" 14 60
        exit 1
    fi
}

#===============================================================================
# Функции
#===============================================================================

setup_font() {
    if command -v setfont >/dev/null 2>&1; then
        setfont ter-v32b 2>/dev/null || setfont cybercafe-narrow 2>/dev/null || true
    fi
}

#--- Экран 1: Информационное окно ----------------------------
screen_info() {
    if ! whiptail --title "Резервное копирование Arch Linux" \
        --yesno "Скрипт создаёт резервную копию Arch Linux,\n\
установленного на двух партициях:\n\n\
  boot-раздел — fat32\n\
  root-раздел — btrfs\n\n\
  БУДЕТ СОЗДАНА ПАПКА С БЕКАПОМ В ТЕКУЩЕЙ ДИРЕКТОРИИ
Продолжить?" 14 60 \
        --yes-button "Продолжить" \
        --no-button "Выйти"; then
        exit 0
    fi
}

#--- Экран 2: Время системы ----------------------------------
screen_time() {
    local current_time
    current_time="$(date '+%A, %d %B %Y  %H:%M:%S')"

    while true; do
        if ! whiptail --title "Системное время" \
            --yes-button "Изменить" \
            --no-button "Продолжить" \
            --yesno "Текущее системное время:\n\n${current_time}\n\n\
Изменить время?" 14 60; then
            return
        fi

        # Одно поле с уже заполненными датой и временем
        local current_dt
        current_dt="$(date '+%Y-%m-%d %H:%M:%S')"

        local datetime
        datetime=$(whiptail --title "Установка времени" \
            --inputbox "Формат: ГГГГ-ММ-ДД ЧЧ:ММ:СС\n\
Значения уже подставлены — правьте только нужное:" \
            12 60 "$current_dt" 3>&1 1>&2 2>&3) || true

        if [[ -n "$datetime" ]]; then
            local newdate newtime
            newdate="${datetime%% *}"
            newtime="${datetime#* }"

            if [[ -n "$newdate" && -n "$newtime" ]]; then
                if date -s "${newdate} ${newtime}" 2>/dev/null; then
                    current_time="$(date '+%A, %d %B %Y  %H:%M:%S')"
                    whiptail --msgbox "Время установлено:\n${current_time}" 10 60
                else
                    whiptail --msgbox "Ошибка установки времени.\n\
Проверьте формат ввода." 10 60
                fi
            fi
        fi
    done
}

#--- Экран 3: Выбор диска ------------------------------------
screen_select_disk() {
    local disks=()
    local menu_items=()
    local num=0

    while IFS= read -r line; do
        local name size model
        name=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        model=$(echo "$line" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' \
            | sed 's/ *$//')
        disks+=("$name")
        menu_items+=("$name" "${size}  ${model}")
        ((num++))
    done < <(lsblk -nd -o NAME,SIZE,MODEL 2>/dev/null | grep -E '^sd|^vd|^nvme')

    if [[ ${#disks[@]} -eq 0 ]]; then
        whiptail --msgbox "Ошибка: диски для копирования не найдены." 10 60
        exit 1
    fi

    local all_info
    all_info="Доступные диски:\n\n"
    for ((i = 0; i < ${#disks[@]}; i++)); do
        all_info="${all_info}  $((i + 1)). ${disks[$i]}  ${menu_items[$((i * 2 + 1))]}\n"
    done

    local choice
    choice=$(whiptail --title "Выбор диска" \
        --menu "${all_info}\nВыберите диск для резервного копирования:" \
        20 70 12 \
        "${menu_items[@]}" 3>&1 1>&2 2>&3) || true

    if [[ -z "$choice" ]]; then
        exit 0
    fi

    namedisk="$choice"

    # Показываем подробности выбранного диска
    local disk_detail
    disk_detail=$(lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL "/dev/$namedisk" 2>/dev/null)

    whiptail --title "Диск: $namedisk" \
        --msgbox "Выбран диск: $namedisk\n\n\
${disk_detail}" 20 70

    # Определяем префикс для разделов
    local partition_prefix=""
    if [[ "$namedisk" =~ ^nvme ]]; then
        partition_prefix="p"
    fi

    boot="${namedisk}${partition_prefix}1"
    root="${namedisk}${partition_prefix}2"

    # Проверяем существование разделов
    if [[ ! -b "/dev/$boot" ]]; then
        whiptail --msgbox "Ошибка: раздел /dev/$boot не найден." 10 60
        exit 1
    fi

    if [[ ! -b "/dev/$root" ]]; then
        whiptail --msgbox "Ошибка: раздел /dev/$root не найден." 10 60
        exit 1
    fi
}

#--- Экран 4: Префикс архива --------------------------------
screen_prefix() {
    local prefix
    if ! prefix=$(whiptail --title "Имя архива" \
        --inputbox "Введите префикс для имени директории бекапа.\n\n\
Имя будет сформировано как:\n  [префикс]ГГГГ-ММ-ДД-ЧЧММ-СС\n\n\
Оставьте пустым для имени без префикса." \
        14 60 3>&1 1>&2 2>&3); then
        exit 0
    fi

    bacdir="${prefix}$(date +%F-%H%M-%S)"
    mkdir "$bacdir"
}

#--- Экран 5: Описание архива --------------------------------
screen_description() {
    local description
    if ! description=$(whiptail --title "Описание бекапа" \
        --inputbox "Введите описание для этого бекапа:" \
        10 60 3>&1 1>&2 2>&3); then
        rm -rf "$bacdir"
        exit 0
    fi

    echo "$description" > "./$bacdir/readme.txt"
    echo "$(date +%F-%H%M-%S)" >> "./$bacdir/readme.txt"
}

#--- Экран 6: Выбор сжатия -----------------------------------
screen_compression() {
    local choice
    if ! choice=$(whiptail --title "Степень сжатия" \
        --menu "Выберите степень сжатия gzip:" \
        14 60 4 \
        "1" "Быстрое сжатие (--fast)" \
        "2" "Сбалансированное сжатие (-6)" \
        "3" "Максимальное сжатие (--best)" \
        3>&1 1>&2 2>&3); then
        rm -rf "$bacdir"
        exit 0
    fi

    case "$choice" in
        1) compression="--fast" ;;
        2) compression="-6" ;;
        3) compression="--best" ;;
    esac
}

#--- Экран 7: Сводная информация -----------------------------
screen_summary() {
    local disk_type
    if [[ "$namedisk" =~ ^nvme ]]; then
        disk_type="NVMe"
    else
        disk_type="SATA/IDE"
    fi

    local summary="Диск:          $namedisk ($disk_type)\n\
boot-раздел:   /dev/$boot\n\
root-раздел:   /dev/$root\n\n\
Директория:    $bacdir\n\
Сжатие:        $compression\n\n\
Файлы бекапа:\n\
  $bacdir/sda.dump\n\
  $bacdir/sda1.pcl.gz\n\
  $bacdir/sda2.pcl.gz\n\
  $bacdir/readme.txt\n\
  $bacdir/over.sh"

    if ! whiptail --title "Сводная информация" \
        --yes-button "Начать" \
        --no-button "Выйти" \
        --yesno "$summary" 22 65; then
        rm -rf "$bacdir"
        exit 0
    fi
}

dump_partition_table() {
    echo "Сохранение таблицы разделов..."
    sfdisk -d "/dev/$namedisk" > "./$bacdir/sda.dump"
}

backup_partitions() {
    echo "Сжатие: $compression" >> "./$bacdir/readme.txt"

    echo "Копирование boot-раздела ($boot)..."
    partclone.vfat -c -N -s "/dev/$boot" \
        | gzip -c $compression > "./$bacdir/sda1.pcl.gz"

    echo "Копирование root-раздела ($root)..."
    partclone.btrfs -c -N -s "/dev/$root" \
        | gzip -c $compression > "./$bacdir/sda2.pcl.gz"

    echo "$(date +%F-%H%M-%S)" >> "./$bacdir/readme.txt"
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

    dt_start=$(date +%s)

    dump_partition_table
    backup_partitions

    dt_end=$(date +%s)
    dt_total=$((dt_end - dt_start))

    hours=$((dt_total / 3600))
    minutes=$(((dt_total - hours * 3600) / 60))
    seconds=$((dt_total - (hours * 3600 + minutes * 60)))

    echo "Общее время: $hours ч $minutes м $seconds с" >> "./$bacdir/readme.txt"

    create_restore_script

    whiptail --msgbox \
        "БЕКАП ЗАВЕРШЁН\n\n\
Директория: $bacdir\n\
Время: ${hours} ч ${minutes} м ${seconds} с" \
        12 60
}

#===============================================================================
# Главная программа
#===============================================================================

main() {
    check_dependencies
    setup_font

    screen_info
    screen_time
    screen_select_disk
    screen_prefix
    screen_description
    screen_compression
    screen_summary
    backup
}

main "$@"
