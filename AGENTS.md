# Руководство для агентов — mybacup

## О проекте

Репозиторий с bash-скриптами для резервного копирования дисков Linux/Windows систем. Скрипты используют `partclone`, `sfdisk`, `gzip`.

```
.
├── liveBacup.sh   # Linux (btrfs + vfat)
├── bacup_win.sh   # Windows (ntfs + vfat)
├── README.md
└── AGENTS.md
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

---

## Стиль кодирования

### Основные правила
| Параметр | Значение |
|----------|----------|
| Интерпретатор | `#!/bin/bash` |
| Кодировка | UTF-8 |
| Отступы | 4 пробела |
| Макс. длина строки | 80 символов |

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
```

### Кавычки
```bash
# Двойные — для переменных
echo "$namedisk"
echo "$bacdir/sda.dump"

# Одинарные — литералы
echo 'Enter value:'

# Всегда с кавычками!
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
```

---

## Зависимости

| Утилита | Пакет | Назначение |
|---------|-------|------------|
| `partclone.vfat/btrfs/ntfs` | partclone | Клонирование разделов |
| `sfdisk` | util-linux | Таблица разделов |
| `gzip` / `zcat` | gzip | Сжатие/распаковка |

---

## Структура бекапа

```
backup_2024-01-15-143022/
├── sda.dump       # Partition table (sfdisk)
├── sda1.pcl.gz    # boot (vfat)
├── sda2.pcl.gz    # root (btrfs/ntfs)
├── readme.txt     # Metadata
└── over.sh        # Restore script
```

### Partition schemes
```
liveBacup.sh:  /dev/${disk}1 → vfat,  /dev/${disk}2 → btrfs
bacup_win.sh:  /dev/${disk}1 → vfat,  /dev/${disk}3 → ntfs,  /dev/${disk}4 → ntfs
```

---

## Режим запуска

Скрипты предназначены для **LiveUSB Arch Linux**:
1. Загрузитесь с установочной флешки
2. Не монтируйте целевой диск
3. Запускайте из текущей директории
4. **Keyboard layout: English only** (setfont обеспечивает отображение кириллицы)

---

## Чеклист перед коммитом

- [ ] `bash -n *.sh` — без ошибок синтаксиса
- [ ] `shellcheck -x *.sh` — без критических предупреждений
- [ ] Все комментарии и сообщения на русском
- [ ] Все переменные в кавычках

---

## Git

```bash
git status
git diff
git commit -m "Краткое описание"
git log --oneline -10
```
