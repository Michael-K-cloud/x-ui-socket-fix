#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BRIGHT_WHITE='\033[1;37m'
NC='\033[0m'

# Информационная заставка
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  Установка скрипта x-ui-socket-fix${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${CYAN}Этот скрипт исправляет проблему с мёртвыми Unix Domain Socket файлами${NC}"
echo -e "${CYAN}(/dev/shm/uds*.sock) для панели 3X-UI.${NC}"
echo ""
echo -e "${BRIGHT_WHITE}Что будет установлено:${NC}"
echo "  • Systemd override для автоматической очистки сокетов при запуске/остановке x-ui"
echo "  • Cron-задача для проверки и удаления мёртвых сокетов каждые 5 минут"
echo ""
echo -e "${BRIGHT_WHITE}После установки скрипт автоматически покажет:${NC}"
echo "  • Содержимое override.conf — убедимся, что systemd override создан правильно"
echo "  • Cron-задачу — убедимся, что задача в crontab"
echo "  • Статус x-ui — активен ли сервис"
echo "  • Процесс Xray — PID и время запуска"
echo "  • Сокеты в /dev/shm — есть ли активные сокеты"
echo "  • Ошибки за последний час — есть ли ERROR в логах"
echo ""
read -p "Продолжить установку? (Enter = да, или введите no): " ans
if [ "$ans" = "no" ]; then
    echo "Установка отменена"
    exit 0
fi
echo ""

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  Начинаем установку...${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# 1. Проверка прав root
echo -e "${CYAN}[1/6]${NC} Проверка прав root..."
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Скрипт должен быть запущен от имени root${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Права root подтверждены${NC}"
echo ""

# 2. Проверка наличия x-ui
echo -e "${CYAN}[2/6]${NC} Проверка наличия службы x-ui..."
if ! systemctl list-unit-files 2>/dev/null | grep -q "x-ui.service"; then
  echo -e "${RED}❌ Служба x-ui не найдена. Скрипт предназначен только для серверов с панелью 3X-UI.${NC}"
  exit 1
fi
echo -e "${GREEN}✅ Служба x-ui найдена${NC}"
echo ""

# 3. Создание systemd override
echo -e "${CYAN}[3/6]${NC} Создание systemd override (drop-in) для x-ui.service..."
mkdir -p /etc/systemd/system/x-ui.service.d

cat > /etc/systemd/system/x-ui.service.d/override.conf <<'EOF'
[Service]
ExecStartPre=/bin/rm -f /dev/shm/uds*.sock
ExecStopPost=/bin/rm -f /dev/shm/uds*.sock
EOF

if [ -f /etc/systemd/system/x-ui.service.d/override.conf ]; then
    echo -e "${GREEN}✅ Файл override.conf создан${NC}"
    echo -e "${WHITE}   Путь: /etc/systemd/system/x-ui.service.d/override.conf${NC}"
else
    echo -e "${RED}❌ Ошибка создания файла${NC}"
    exit 1
fi

echo -e "${YELLOW}   Перезагрузка systemd daemon...${NC}"
systemctl daemon-reload
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Systemd daemon перезапущен${NC}"
else
    echo -e "${RED}❌ Ошибка перезапуска systemd daemon${NC}"
    exit 1
fi
echo ""

# 4. Добавление cron-задачи
echo -e "${CYAN}[4/6]${NC} Добавление cron-задачи (очистка мёртвых сокетов каждые 5 минут)..."

if crontab -l 2>/dev/null | grep -q "find /dev/shm -name 'uds\*.sock'"; then
    echo -e "${YELLOW}⚠️ Cron-задача уже существует, пропускаем добавление${NC}"
else
    (crontab -l 2>/dev/null; echo "*/5 * * * * find /dev/shm -name 'uds*.sock' -type s -exec fuser {} \; 2>/dev/null | xargs -r -I {} sh -c 'if ! ps -p {} >/dev/null 2>&1; then rm -f /dev/shm/uds*.sock; fi'") | crontab -
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Cron-задача добавлена (каждые 5 минут)${NC}"
    else
        echo -e "${RED}❌ Ошибка добавления cron-задачи${NC}"
        exit 1
    fi
fi
echo ""

# 5. Перезапуск x-ui для применения изменений
echo -e "${CYAN}[5/6]${NC} Перезапуск службы x-ui для применения systemd override..."
systemctl restart x-ui
sleep 3

if systemctl is-active --quiet x-ui; then
    echo -e "${GREEN}✅ Служба x-ui перезапущена и активна${NC}"
else
    echo -e "${RED}❌ Ошибка перезапуска x-ui${NC}"
fi
echo ""

# 6. Финальная проверка
echo -e "${CYAN}[6/6]${NC} Финальная проверка..."
echo ""

echo -e "${BRIGHT_WHITE}=== Systemd override ===${NC}"
if [ -f /etc/systemd/system/x-ui.service.d/override.conf ]; then
    echo -e "${GREEN}✅ Файл существует${NC}"
    cat /etc/systemd/system/x-ui.service.d/override.conf
else
    echo -e "${RED}❌ Файл не найден${NC}"
fi
echo ""

echo -e "${BRIGHT_WHITE}=== Cron-задача ===${NC}"
CRON_CHECK=$(crontab -l 2>/dev/null | grep "find /dev/shm -name 'uds\*.sock'")
if [ -n "$CRON_CHECK" ]; then
    echo -e "${GREEN}✅ Задача добавлена в crontab${NC}"
    echo -e "${WHITE}   $CRON_CHECK${NC}"
else
    echo -e "${RED}❌ Задача не найдена в crontab${NC}"
fi
echo ""

echo -e "${BRIGHT_WHITE}=== Статус x-ui ===${NC}"
if systemctl is-active --quiet x-ui; then
    echo -e "${GREEN}✅ x-ui активен${NC}"
else
    echo -e "${RED}❌ x-ui не активен${NC}"
fi

echo -e "${BRIGHT_WHITE}=== Процесс Xray ===${NC}"
ps aux | grep -v grep | grep xray | awk '{print "   PID:", $2, "| запущен в:", $9}' || echo -e "${RED}   Xray не запущен${NC}"
echo ""

echo -e "${BRIGHT_WHITE}=== Сокеты в /dev/shm ===${NC}"
ls -la /dev/shm/uds*.sock 2>/dev/null || echo "   Сокетов нет"
echo ""

echo -e "${BRIGHT_WHITE}=== Ошибки за последний час ===${NC}"
ERROR_COUNT=$(journalctl -u x-ui --since "1 hour ago" --no-pager 2>/dev/null | grep -c "ERROR")
if [ "$ERROR_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✅ Ошибок нет${NC}"
else
    echo -e "${YELLOW}⚠️ Найдено ошибок: $ERROR_COUNT${NC}"
fi
echo ""

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  ✅ Установка успешно завершена!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${CYAN}Что было сделано:${NC}"
echo "  • Создан systemd override для автоматической очистки сокетов"
echo "  • Добавлена cron-задача для удаления мёртвых сокетов каждые 5 минут"
echo "  • Служба x-ui перезапущена с новыми настройками"
echo ""
echo -e "${YELLOW}⚠️ Эти изменения сохраняются навсегда и переживают перезагрузку сервера${NC}"