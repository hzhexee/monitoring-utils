#!/bin/bash

# Скрипт для установки и запуска мониторинг-утилит на Ubuntu VPS

set -e

echo "=== Установка мониторинг-утилит ==="

# Обновляем систему
echo "Обновление системы..."
sudo apt update && sudo apt upgrade -y

# Устанавливаем необходимые пакеты
echo "Установка необходимых пакетов..."
sudo apt install -y python3 python3-pip curl wget git

# Делаем скрипт исполняемым
chmod +x script.py

# Запускаем скрипт
echo "Запуск скрипта..."
python3 script.py
