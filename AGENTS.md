# Руководство для агентов — mybacup

## О проекте

Репозиторий с bash-скриптами для резервного копирования дисков Linux/Windows систем и установки snap-пакетов в Arch Linux. Скрипты резервного копирования используют `partclone`, `sfdisk`, `gzip`.

```
.
├── liveBacup.sh   # Linux (btrfs + vfat) - полная версия
├── bacup_win.sh   # Windows (ntfs + vfat) - полная версия
├── easyBacup.sh   # Linux (btrfs + vfat) - упрощенная версия
├── easyBacWin.sh  # Windows (ntfs + vfat) - упрощенная версия
├── archSnap.sh    # Установка snap-пакетов в Arch Linux
├── over.sh        # Скрипт восстановления (генерируется)
├── README.md
├── AGENTS.md
└── SESSION_NOTES.md
```

---

## Команды проверки

### Синтаксис
```bash
# Один файл
bash -n liveBacup.sh

# Все скрипты
for s in *.sh; do bash -n "$s" && echo "OK: $s" || echo "ERROR: $s"; done
```

### ShellCheck (статический анализ)
```bash
# Полный анализ
shellcheck -x liveBacup.sh

# Только ошибки
shellcheck -S error liveBacup.sh

# Все скрипты (SC1090 игнорируется — sourced файлы)
shellcheck -x -i SC1090 *.sh
```

### Трассировка выполнения
```bash
bash -x liveBacup.sh 2>&1 | tee debug.log
time bash liveBacup.sh
```

### Тестирование (функциональные проверки)
```bash
# Проверка наличия зависимостей
for cmd in partclone.vfat partclone.btrfs partclone.ntfs sfdisk gzip; do
    command -v "$cmd" >/dev/null 2>&1 || echo "Missing: $cmd"
done

# Проверка прав доступа
ls -la *.sh
```

---

## Стиль кодирования

### Основные правила
| Параметр | Значение |
|----------|----------|
| Интерпретатор | `#!/bin/bash` |
| Кодировка | UTF-8 |
| Отступы | 4 пробела |
| Макс. длина строки | 80 символов |
| Shebang | `#!/bin/bash` |
| Strict mode | `set -euo pipefail` |

### Именование
```bash
# Переменные — snake_case
namedisk="sda"
bacdir="backup_$(date +%F)"

# Константы — UPPER_CASE + readonly
readonly BACKUP_DIR="/backups"
readonly MAX_RETRIES=3

# Функции — snake_case
dump_partition_table() { ... }
backup_partitions() { ... }

# Глобальные переменные — объявлять в начале файла
namedisk=""
boot=""
root=""
bacdir=""
compression=""
```

### Кавычки
```bash
# Двойные — для переменных и подстановок
echo "$namedisk"
echo "$bacdir/sda.dump"

# Одинарные — литералы и строки без подстановок
echo 'Enter value:'
echo '=========================================='

# Всегда с кавычками!
```

### Структура файла
```bash
#!/bin/bash
#===============================================================================
# Описание скрипта
# Запуск с установочного носителя Arch Linux
#===============================================================================
# ПРИМЕЧАНИЕ: Раскладка клавиатуры остаётся EN (US).
#       Сообщения на русском (отображаются через шрифт ter-v32b).
#===============================================================================

set -euo pipefail

#------Глобальные переменные---------------------------------
namedisk=""
boot=""
root=""
bacdir=""
compression=""

#===============================================================================
# Функции
#===============================================================================

function_name() {
    # 4 пробела отступа
    local var1="$1"
    # ...
}

#===============================================================================
# Главная программа
#===============================================================================

main() {
    # Основная логика
}

main "$@"
```

### Обработка ошибок
```bash
# Критические команды
mkdir "$bacdir" || exit 1

# Валидация ввода
if [[ ! "$namedisk" =~ ^[sv]d[a-z]$ ]]; then
    echo "Error: invalid disk name. Example: sda, vda"
    exit 1
fi

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "Error: root privileges required"
    exit 1
fi

# Dependency check
check_dependency() {
    local cmd="$1"
    local package="${2:-$cmd}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd not found. Install: pacman -S $package"
        exit 1
    fi
}
check_dependency "partclone.vfat" "partclone"
check_dependency "sfdisk" "util-linux"

# Использование local в функциях
process_disk() {
    local disk_name="$1"
    local backup_dir="$2"
    # ...
}
```

### Комментарии
```bash
# Однострочные комментарии на русском
# Многострочные комментарии с разделителями
#===============================================================================
# Блок функций
#===============================================================================

# Важные предупреждения
# ПРИМЕЧАНИЕ: Раскладка клавиатуры остаётся EN (US).
```

---

## Зависимости

| Утилита | Пакет | Назначение |
|---------|-------|------------|
| `partclone.vfat` | partclone | Клонирование vfat разделов |
| `partclone.btrfs` | partclone | Клонирование btrfs разделов |
| `partclone.ntfs` | partclone | Клонирование ntfs разделов |
| `sfdisk` | util-linux | Таблица разделов |
| `gzip` / `zcat` | gzip | Сжатие/распаковка |
| `lsblk` | util-linux | Информация о блочных устройствах |
| `setfont` | kbd | Настройка шрифтов (терминал) |

---

## Структура бекапа

```
backup_2024-01-15-143022/
├── sda.dump       # Partition table (sfdisk)
├── sda1.pcl.gz    # boot (vfat)
├── sda2.pcl.gz    # root (btrfs/ntfs)
├── readme.txt     # Metadata (описание, время, сжатие)
└── over.sh        # Restore script
```

### Partition schemes
```
liveBacup.sh:  /dev/${disk}1 → vfat,  /dev/${disk}2 → btrfs
bacup_win.sh:  /dev/${disk}1 → vfat,  /dev/${disk}3 → ntfs,  /dev/${disk}4 → ntfs
```

### Формат именования
- Директория бекапа: `[префикс]YYYY-MM-DD-HHMM-SS`
- Файлы: `sda.dump`, `sda1.pcl.gz`, `sda2.pcl.gz`, `sda3.pcl.gz`, `sda4.pcl.gz`
- Скрипт восстановления: `over.sh`
- Метаданные: `readme.txt`

---

## Режим запуска

Скрипты предназначены для **LiveUSB Arch Linux**:
1. Загрузитесь с установочной флешки Arch Linux
2. Не монтируйте целевой диск к системе
3. Запускайте из текущей директории
4. **Keyboard layout: English only** (setfont обеспечивает отображение кириллицы)
5. Требуются права root

### Последовательность работы
1. Настройка шрифта (`setup_font`)
2. Установка времени (`show_time`)
3. Выбор диска (`select_disk`)
4. Выбор разделов (`select_partitions`)
5. Подтверждение выбора (`confirm_selection`)
6. Создание директории бекапа (`create_backup_dir`)
7. Выбор сжатия (`select_compression`)
8. Копирование (`backup`)

---

## Чеклист перед коммитом

- [ ] `bash -n *.sh` — без ошибок синтаксиса
- [ ] `shellcheck -x *.sh` — без критических предупреждений
- [ ] Все комментарии и сообщения на русском
- [ ] Все переменные в кавычках
- [ ] Использован strict mode: `set -euo pipefail`
- [ ] Глобальные переменные объявлены в начале
- [ ] Функции используют `local` для локальных переменных
- [ ] Соответствие стилю именования (snake_case)
- [ ] Максимальная длина строки 80 символов
- [ ] Правильные отступы (4 пробела)

---

## Git

```bash
# Статус
git status
git diff

# Коммит
git commit -m "Краткое описание на русском"

# История
git log --oneline -10
git log --graph --oneline --decorate

# Ветки
git branch -a
```

### Сообщения коммитов
- На русском языке
- Краткое описание изменений
- Пример: "Добавлена проверка зависимостей", "Исправлена обработка ошибок"

---

## Особенности реализации

### Общие функции в обоих скриптах
- `setup_font()` — настройка шрифта для кириллицы
- `show_time()` — отображение и установка времени
- `select_disk()` — интерактивный выбор диска
- `select_partitions()` — выбор разделов
- `confirm_selection()` — подтверждение выбора
- `create_backup_dir()` — создание директории бекапа
- `select_compression()` — выбор степени сжатия
- `dump_partition_table()` — сохранение таблицы разделов
- `create_restore_script()` — создание скрипта восстановления

### Различия
- `liveBacup.sh`: btrfs + vfat, 2 раздела (полная версия с выбором разделов)
- `bacup_win.sh`: ntfs + vfat, 3 раздела (Windows версия)
- `easyBacup.sh`: btrfs + vfat, 2 раздела (упрощенная версия, разделы определяются автоматически)
- `easyBacWin.sh`: ntfs + vfat, 2 раздела (упрощенная Windows версия, только boot и system)

### Ключевые команды
```bash
# Сохранение таблицы разделов
sfdisk -d "/dev/$namedisk" > "./$bacdir/sda.dump"

# Клонирование разделов
partclone.vfat -c -N -s "/dev/$boot_part" | gzip -c $compression > "./$bacdir/sda1.pcl.gz"
partclone.btrfs -c -N -s "/dev/$root_part" | gzip -c $compression > "./$bacdir/sda2.pcl.gz"

# Восстановление
zcat ./sda1.pcl.gz | partclone.vfat -r -N -o /dev/$boot
```

---

## Безопасность

1. **Проверка прав root** — скрипты требуют привилегий суперпользователя
2. **Валидация ввода** — проверка имен дисков и разделов
3. **Strict mode** — `set -euo pipefail` для обработки ошибок
4. **Локализация** — сообщения на русском, ввод на английском
5. **Интерактивность** — подтверждение действий перед выполнением

---

## Отладка

```bash
# Подробный вывод
bash -x script.sh 2>&1 | tee debug.log

# Только ошибки
bash script.sh 2> error.log

# Проверка времени выполнения
time bash script.sh

# Проверка зависимостей
./script.sh --help 2>&1 | head -20
```
