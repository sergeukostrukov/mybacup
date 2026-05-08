# Руководство для агентов — mybacup

## О проекте

Bash-скрипты для резервного копирования дисков Linux/Windows и восстановления из бэкапа. Запускаются с LiveUSB Arch Linux. Используют `partclone`, `sfdisk`, `gzip`.

```
.
├── liveBacup.sh    # Linux (btrfs + vfat) — полная версия, интерактивный выбор разделов
├── bacup_win.sh    # Windows (ntfs + vfat) — полная версия, 3 раздела (boot + ntfs×2)
├── easyBacup.sh    # Linux (btrfs + vfat) — упрощённая, разделы определяются автоматически (№1, №2)
├── easyBacWin.sh   # Windows (ntfs + vfat) — упрощённая, разделы автоматически (№1 boot, №2 system)
├── over.sh         # Скрипт восстановления (генерируется в каждый бекап)
├── README.md
├── AGENTS.md
└── SESSION_NOTES.md
```

**Файла `archSnap.sh` в репозитории больше нет** — не ссылаться на него.

---

## Критические правила

- **Общение на русском языке** — все комментарии, сообщения, коммиты на русском
- **Раскладка клавиатуры EN (US)** — скрипты используют `setfont ter-v32b` для отображения кириллицы, но ввод только на английском
- **Требуется root** — все скрипты проверяют `$EUID -ne 0`
- **Целевой диск НЕ должен быть смонтирован**
- **Не запускать на хост-системе** — предназначены для LiveUSB Arch Linux

---

## Команды проверки

```bash
# Синтаксис всех скриптов
for s in *.sh; do bash -n "$s" && echo "OK: $s" || echo "ERROR: $s"; done

# ShellCheck
shellcheck -x -i SC1090 *.sh

# Проверка зависимостей
for cmd in partclone.vfat partclone.btrfs partclone.ntfs sfdisk gzip; do
    command -v "$cmd" >/dev/null 2>&1 || echo "Missing: $cmd"
done
```

---

## Стиль кодирования

| Правило | Значение |
|---------|----------|
| Интерпретатор | `#!/bin/bash` |
| Strict mode | `set -euo pipefail` |
| Отступы | 4 пробела |
| Макс. длина строки | 80 символов |
| Именование переменных | snake_case |
| Константы | UPPER_CASE + readonly |
| Комментарии | на русском |
| Кавычки | всегда, особенно вокруг переменных |
| `local` | для всех локальных переменных в функциях |

### Структура файла
```
shebang → заголовок-описание → root check → глобальные переменные →
check_dependencies() → функции → main() → main "$@"
```

---

## Зависимости

| Утилита | Пакет |
|---------|-------|
| `partclone.vfat` / `partclone.btrfs` / `partclone.ntfs` | partclone |
| `sfdisk`, `lsblk` | util-linux |
| `gzip` / `zcat` | gzip |
| `setfont` | kbd (шрифт ter-v32b) |

---

## Схема бекапа

```
[префикс]YYYY-MM-DD-HHMM-SS/
├── sda.dump       # Таблица разделов (sfdisk -d)
├── sda1.pcl.gz    # boot (vfat)
├── sda2.pcl.gz    # root/system (btrfs или ntfs)
├── sda3.pcl.gz    # ntfs данные (только bacup_win.sh)
├── sda4.pcl.gz    # ntfs данные (только bacup_win.sh)
├── readme.txt     # Описание, время, сжатие
└── over.sh        # Скрипт восстановления (генерируется)
```

### Различия по скриптам

| Скрипт | Разделы | ФС | Выбор разделов |
|--------|---------|----|----------------|
| liveBacup.sh | №1, №2 | vfat + btrfs | Интерактивный |
| bacup_win.sh | №1, №3, №4 | vfat + ntfs×2 | Интерактивный |
| easyBacup.sh | №1, №2 | vfat + btrfs | Авто |
| easyBacWin.sh | №1, №2 | vfat + ntfs | Авто |

### NVMe-префикс
Для NVMe-дисков разделы имеют префикс `p`: `nvme0n1p1`, `nvme0n1p2`. Все скрипты обрабатывают это через проверку `[[ "$namedisk" =~ ^nvme ]]`.

---

## Ключевые команды бэкапа/восстановления

```bash
# Сохранение таблицы разделов
sfdisk -d "/dev/$namedisk" > "./$bacdir/sda.dump"

# Клонирование (backup)
partclone.vfat -c -N -s "/dev/$boot_part" | gzip -c $compression > "./$bacdir/sda1.pcl.gz"
partclone.btrfs -c -N -s "/dev/$root_part" | gzip -c $compression > "./$bacdir/sda2.pcl.gz"
partclone.ntfs  -c -N -s "/dev/$ntfs_part" | gzip -c $compression > "./$bacdir/sda3.pcl.gz"

# Восстановление
zcat ./sda1.pcl.gz | partclone.vfat -r -N -o /dev/$boot
```

---

## Последовательность работы скриптов

1. `check_dependencies` — проверка утилит
2. `setup_font` — шрифт ter-v32b для кириллицы
3. `show_time` — отображение/установка системного времени
4. `select_disk` — выбор диска (lsblk, интерактивный или авто)
5. `select_partitions` — выбор разделов (только полные версии)
6. `confirm_selection` — подтверждение
7. `create_backup_dir` — создание директории с префиксом
8. `select_compression` --fast / -6 / --best
9. `backup` → preview → dump → clone → create_restore_script

---

## Git

- Коммиты на русском языке
- `git commit -m "Краткое описание изменений"`
- Чеклист: `bash -n *.sh` → `shellcheck -x -i SC1090 *.sh` → коммит

## Отладка

```bash
bash -x script.sh 2>&1 | tee debug.log
time bash script.sh
```
