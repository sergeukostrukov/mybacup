# mybacup
## Скрипт bacup.sh 
В текущей директории создаёт подкаталог в который записывает файл "sda.dump" с дампом копируемого диска;
создаёт файл  "readme.txt" в который записывает краткую информацию об архиве, времени начала архивации,
степени сжатия, времени завершении процесса работы скрмпта;
В этуже директорию записывает два архива с копиями партиций диска и создаёт в этойже директории
файл "over.sh" со скриптом восстановления этих скопированных архивов на физический диск (восстановление).

Для работы скрипта нужно загрузиться с USB установочной флешки.
Комманда "lsblk" показывает подключенные в данный момент диски и партиции
Нужно подключить диск на котором будет создан архив диска.
Комманда      "mount /dev/sdx /mnt"    подклчает диск  "/dev/sdx"   к дириктории "/mnt"  
("/dev/sdx" нужно указать свой)
АРХИВ СОЗДАСТСЯ В  ТЕКУЩЕЙ ДИРИКТОРИИ ОТКУДА ЗАПУСКАЕТСЯ СКРИПT "bacup.sh"
Удобнее всего использовать утилиту  "mc"  для просмотра содержимого арживов и запуска скрипта.