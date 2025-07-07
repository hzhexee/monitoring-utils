#!/bin/bash

# Скрипт для установки и запуска мониторинг-утилит на Ubuntu VPS

set -e

echo "=== Установка мониторинг-утилит ==="

# Обновляем систему
echo "Обновление системы..."
sudo apt update && sudo apt upgrade -y

# Устанавливаем необходимые пакеты
echo "Установка необходимых пакетов..."
sudo apt install -y python3 python3-pip python3-pyyaml curl wget git

# Устанавливаем Python зависимости
echo "Установка Python зависимостей..."
pip3 install -r requirements.txt

# Делаем скрипт исполняемым
chmod +x script.py
