#!/usr/bin/env python3
"""
Скрипт для автоматического развертывания контейнеров с мониторинг-утилитами
Поддерживает:
- Xray-checker + Node Exporter + Prometheus + Grafana
- Xray-checker + Uptime-Kuma
- Node Exporter на ноде
"""

import argparse
import os
import sys
import subprocess
import re
import yaml
import json
import urllib.parse
import base64
from pathlib import Path

def system_update():
    """Обновляет систему"""
    print("Обновление системы...")
    run_command("apt update && apt upgrade -y")
    
def create_basedir():
    """Создает базовую директорию для проекта"""
    base_dir = Path("/opt/monitoring-utils")
    if not base_dir.exists():
        print(f"Создание директории: {base_dir}")
        base_dir.mkdir()
        run_command("cd /opt/monitoring-utils", check=False)
    else:
        print(f"Директория уже существует: {base_dir}")

def run_command(command, check=True):
    """Выполняет команду в shell"""
    print(f"Выполняю: {command}")
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    if check and result.returncode != 0:
        print(f"Ошибка выполнения команды: {command}")
        print(f"Stderr: {result.stderr}")
        sys.exit(1)
    return result

def check_docker():
    """Проверяет наличие Docker"""
    try:
        result = run_command("docker --version", check=False)
        if result.returncode != 0:
            print("Docker не найден. Устанавливаю Docker...")
            install_docker()
        else:
            print("Docker уже установлен")
    except Exception as e:
        print(f"Ошибка проверки Docker: {e}")
        install_docker()

def install_docker():
    """Устанавливает Docker"""
    print("Установка Docker...")
    run_command("curl -fsSL https://get.docker.com -o get-docker.sh")
    run_command("sh get-docker.sh")
    run_command("sudo usermod -aG docker $USER")
    print("Docker установлен. Перезапустите сессию или выполните 'newgrp docker'")

def validate_subscription(subscription):
    """Валидирует формат подписки"""
    # URL формат
    if subscription.startswith(('http://', 'https://')):
        return True
    
    # BASE64 формат
    try:
        decoded = base64.b64decode(subscription)
        if decoded.decode('utf-8').startswith(('vmess://', 'vless://', 'trojan://')):
            return True
    except:
        pass
    
    # Файл формат
    if subscription.startswith('file:///'):
        file_path = subscription[7:]  # убираем file://
        if os.path.exists(file_path):
            return True
        else:
            print(f"Файл {file_path} не найден")
            return False
    
    # Папка формат
    if subscription.startswith('folder:///'):
        folder_path = subscription[9:]  # убираем folder://
        if os.path.exists(folder_path) and os.path.isdir(folder_path):
            return True
        else:
            print(f"Папка {folder_path} не найдена")
            return False
    
    return False

def get_subscription():
    """Получает подписку от пользователя"""
    print("\nФорматы подписок:")
    print("1. URL: https://sub.example.com/longassuuid")
    print("2. BASE64: dmxlc3M6Ly91dWlkQGV4YW1wbGUuY29tOjQ0MyVlbmNyeXB0aW9uPW5vbmUmc2VjdXJpdHk9dGxzI3Byb3h5MQ==")
    print("3. JSON-файл: file:///path/to/config.json")
    print("4. Папка с JSON: folder:///path/to/configs")
    
    while True:
        subscription = input("\nВведите подписку Xray: ").strip()
        if validate_subscription(subscription):
            return subscription
        else:
            print("Неверный формат подписки. Попробуйте снова.")



def create_prometheus_config(nodes=[]):
    """Создает конфигурацию Prometheus"""
    config = {
        'global': {
            'scrape_interval': '15s'
        },
        'scrape_configs': [
            {
                'job_name': 'Host-node',
                'static_configs': [
                    {'targets': ['nodeexp-node:9100']}
                ]
            }
        ]
    }
    
    # Добавляем внешние ноды
    if nodes:
        for node in nodes:
            config['scrape_configs'].append({
                'job_name': node['name'],
                'static_configs': [
                    {'targets': [f"{node['ip']}:9100"]}
                ]
            })
    
    with open('prometheus.yml', 'w') as f:
        yaml.dump(config, f, default_flow_style=False)
    
    print("Конфигурация Prometheus создана")

def create_docker_compose_grafana():
    """Создает docker-compose для Grafana стека"""
    compose_content = """volumes:
  prometheus_data:
  grafana_data:

services:
  node-exporter:
    image: prom/node-exporter:latest
    container_name: nodeexp-node
    restart: unless-stopped
    networks:
      - monitoring
    ports:
      - "127.0.0.1:9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/host:ro,rslave
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/host'

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    networks:
      - monitoring
    ports:
      - "127.0.0.1:9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    networks:
      - monitoring
    ports:
      - "127.0.0.1:3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_SECURITY_ALLOW_EMBEDDING=true
    depends_on:
      - prometheus

networks:
  monitoring:
    driver: bridge
"""
    
    with open('docker-compose.yml', 'w') as f:
        f.write(compose_content)
    
    print("Docker Compose файл для Grafana создан")

def create_docker_compose_kuma(subscription, mount_paths=None):
    """Создает docker-compose для Uptime-Kuma"""
    compose_content = """volumes:
  uptime-kuma:

services:
  xray-checker:
    container_name: xray-checker
    restart: unless-stopped
    image: kutovoys/xray-checker
    networks:
      - monitoring
    environment:
      - SUBSCRIPTION_URL={subscription}
    ports:
      - "127.0.0.1:2112:2112"
""".format(subscription=subscription)

    # Добавляем монтирование для файлов/папок
    if mount_paths:
        lines = compose_content.split('\n')
        for i, line in enumerate(lines):
            if 'container_name: xray-checker' in line:
                # Вставляем volumes после container_name
                volume_lines = ['    volumes:']
                for mount_path in mount_paths:
                    volume_lines.append(f'      - {mount_path}:{mount_path}:ro')
                lines[i+1:i+1] = volume_lines
                break
        compose_content = '\n'.join(lines)

    compose_content += """
  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    restart: unless-stopped
    networks:
      - monitoring
    ports:
      - "127.0.0.1:3001:3001"
    volumes:
      - uptime-kuma:/app/data

networks:
  monitoring:
    driver: bridge
"""
    
    with open('docker-compose.yml', 'w') as f:
        f.write(compose_content)
    
    print("Docker Compose файл для Uptime-Kuma создан")

def create_node_compose():
    """Создает docker-compose для Node Exporter"""
    compose_content = """services:
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/host:ro,rslave
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/host'
"""
    
    with open('docker-compose.yml', 'w') as f:
        f.write(compose_content)
    
    print("Docker Compose файл для Node Exporter создан")

def get_mount_paths(subscription):
    """Получает пути для монтирования при использовании файлов/папок"""
    mount_paths = []
    
    if subscription.startswith('file:///'):
        file_path = subscription[7:]
        mount_paths.append(file_path)
    elif subscription.startswith('folder:///'):
        folder_path = subscription[9:]
        mount_paths.append(folder_path)
    
    return mount_paths

def deploy_grafana():
    """Развертывает Grafana стек"""
    print("\n=== Развертывание Grafana стека ===")
    
    # Проверяем Docker
    check_docker()
    
    # Спрашиваем про внешние ноды
    nodes = []
    add_nodes = input("\nХотите добавить внешние ноды для мониторинга? (y/n): ").strip().lower()
    if add_nodes in ['y', 'yes', 'да', 'д']:
        while True:
            node_ip = input("Введите IP адрес ноды (или 'done' для завершения): ").strip()
            if node_ip.lower() == 'done':
                break
            if re.match(r'^(\d{1,3}\.){3}\d{1,3}$', node_ip):
                node_name = input(f"Введите имя для ноды {node_ip}: ").strip()
                if not node_name:
                    node_name = f"node-{node_ip.replace('.', '-')}"
                nodes.append({'ip': node_ip, 'name': node_name})
            else:
                print("Неверный IP адрес")
    
    # Создаем конфигурации
    create_prometheus_config(nodes)
    create_docker_compose_grafana()
    
    # Запускаем контейнеры
    print("\nЗапуск контейнеров...")
    run_command("docker compose up -d")
    
    print("\n=== Развертывание завершено ===")
    print("Grafana: http://localhost:3000 (admin/admin)")
    print("Prometheus: http://localhost:9090")
    print("Node Exporter: http://localhost:9100")

def deploy_kuma():
    """Развертывает Uptime-Kuma стек"""
    print("\n=== Развертывание Uptime-Kuma стека ===")
    
    # Проверяем Docker
    check_docker()
    
    # Получаем подписку
    subscription = get_subscription()
    
    # Получаем пути для монтирования
    mount_paths = get_mount_paths(subscription)
    
    # Создаем конфигурации
    create_docker_compose_kuma(subscription, mount_paths)
    
    # Запускаем контейнеры
    print("\nЗапуск контейнеров...")
    run_command("docker compose up -d")
    
    print("\n=== Развертывание завершено ===")
    print("Uptime-Kuma: http://localhost:3001")
    print("Xray Checker: http://localhost:2112")

def deploy_node():
    """Развертывает Node Exporter на ноде"""
    print("\n=== Развертывание Node Exporter ===")
    
    # Проверяем Docker
    check_docker()
    
    # Создаем конфигурации
    create_node_compose()
    
    # Получаем IP мастер-ноды
    master_ip = input("\nВведите IP адрес мастер-ноды для настройки UFW: ").strip()
    if re.match(r'^(\d{1,3}\.){3}\d{1,3}$', master_ip):
        print(f"Настраиваю UFW для доступа с {master_ip}...")
        run_command(f"sudo ufw allow from {master_ip}", check=False)
    
    # Запускаем контейнеры
    print("\nЗапуск контейнеров...")
    run_command("docker compose up -d")
    
    print("\n=== Развертывание завершено ===")
    print("Node Exporter: http://localhost:9100")

def main():
    parser = argparse.ArgumentParser(description='Скрипт для развертывания мониторинг-утилит')
    parser.add_argument('--grafana', action='store_true', help='Развернуть Grafana стек')
    parser.add_argument('--kuma', action='store_true', help='Развернуть Uptime-Kuma стек')
    parser.add_argument('--node', action='store_true', help='Развернуть Node Exporter на ноде')
    
    args = parser.parse_args()
    
    if args.grafana:
        deploy_grafana()
    elif args.kuma:
        deploy_kuma()
    elif args.node:
        deploy_node()
    else:
        # Интерактивный режим
        print("Выберите вариант развертывания:")
        print("1. Grafana стек (Node Exporter + Prometheus + Grafana)")
        print("2. Uptime-Kuma стек (Xray-checker + Uptime-Kuma)")
        print("3. Node Exporter (только для ноды)")
        
        while True:
            choice = input("\nВведите номер варианта (1-3): ").strip()
            if choice == '1':
                deploy_grafana()
                break
            elif choice == '2':
                deploy_kuma()
                break
            elif choice == '3':
                deploy_node()
                break
            else:
                print("Неверный выбор. Введите 1, 2 или 3.")

if __name__ == "__main__":
    main()