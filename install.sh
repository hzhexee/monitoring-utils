#!/bin/bash

# Скрипт для авторазвертывания контейнеров с мониторинг-утилитами
# Поддерживает флаги: --grafana, --kuma, --node

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка зависимостей
check_dependencies() {
    log_info "Проверка зависимостей..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker не установлен"
        exit 1
    fi
    
    log_success "Все зависимости установлены"
}

# Получение подписки от пользователя
get_subscription() {
    while true; do
        echo ""
        log_info "Введите подписку для Xray-checker:"
        echo "Поддерживаемые форматы:"
        echo "  - URL (sub.12345678.com/longassuuid)"
        echo "  - BASE64 (dmxlc3M6Ly9...)"
        echo "  - JSON-файл (file:///path/to/config.json)"
        echo "  - Папка с JSON-конфигурациями (folder:///path/to/configs)"
        echo ""
        read -p "Подписка: " subscription
        
        if [[ -n "$subscription" ]]; then
            echo "$subscription"
            return 0
        else
            log_warning "Подписка не может быть пустой"
        fi
    done
}

# Получение информации о дополнительных нодах
get_additional_nodes() {
    local nodes=""
    
    echo ""
    read -p "Хотите добавить дополнительные ноды для мониторинга? (y/n): " add_nodes
    
    if [[ "$add_nodes" =~ ^[Yy]$ ]]; then
        while true; do
            read -p "Введите количество дополнительных нод: " node_count
            
            if [[ "$node_count" =~ ^[0-9]+$ ]] && [[ "$node_count" -gt 0 ]]; then
                break
            else
                log_warning "Введите корректное число больше 0"
            fi
        done
        
        for ((i=1; i<=node_count; i++)); do
            echo ""
            log_info "Конфигурация ноды $i:"
            
            while true; do
                read -p "Введите название ноды $i: " node_name
                if [[ -n "$node_name" ]]; then
                    break
                else
                    log_warning "Название не может быть пустым"
                fi
            done
            
            while true; do
                read -p "Введите IP адрес ноды $i: " node_ip
                if [[ "$node_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                    break
                else
                    log_warning "Введите корректный IP адрес"
                fi
            done
            
            nodes="${nodes}  - job_name: ${node_name}
    static_configs:
      - targets: ['${node_ip}:9100']
"
        done
    fi
    
    echo "$nodes"
}

# Установка Grafana версии
install_grafana() {
    log_info "Установка мониторинга с Grafana..."
    
    # Создание docker-compose.yml
    cat > docker-compose.yml << 'EOF'
volumes:
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

  xray-checker:
    image: kutovoys/xray-checker
    networks:
      - monitoring
    container_name: xray-checker
    environment:
      - SUBSCRIPTION_URL=PLACEHOLDER_SUBSCRIPTION
    ports:
      - "127.0.0.1:2112:2112"

networks:
  monitoring:
    driver: bridge
EOF

    # Проверка нужна ли подписка
    echo ""
    read -p "Хотите добавить подписку для Xray-checker? (y/n): " need_subscription
    
    if [[ "$need_subscription" =~ ^[Yy]$ ]]; then
        # Получение подписки
        subscription=$(get_subscription)
    else
        subscription=""
    fi
    
    # Получение дополнительных нод
    additional_nodes=$(get_additional_nodes)
    
    # Создание prometheus.yml
    cat > prometheus.yml << EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: Xray Checker
    metrics_path: /metrics
    static_configs:
      - targets: ['xray-checker:2112']
    scrape_interval: 1m
  - job_name: Host-node
    static_configs:
      - targets: ['nodeexp-node:9100']
${additional_nodes}EOF

    # Замена подписки в docker-compose.yml только если она есть
    if [[ -n "$subscription" ]]; then
        sed -i "s|PLACEHOLDER_SUBSCRIPTION|$subscription|g" docker-compose.yml
        
        # Обработка файловых подписок
        if [[ "$subscription" == file://* || "$subscription" == folder://* ]]; then
            local path=${subscription#*://}
            if [[ ! -e "$path" ]]; then
                log_error "Путь $path не существует"
                exit 1
            fi
            
            # Добавление volume для файлов/папок
            if [[ "$subscription" == file://* ]]; then
                sed -i "/xray-checker:/a\\    volumes:\n      - $path:/app/config.json:ro" docker-compose.yml
            else
                sed -i "/xray-checker:/a\\    volumes:\n      - $path:/app/configs:ro" docker-compose.yml
            fi
        fi
    else
        # Удаление xray-checker из docker-compose если подписка не нужна
        sed -i '/xray-checker:/,/^$/d' docker-compose.yml
        # Удаление xray-checker из prometheus.yml
        sed -i '/Xray Checker/,/scrape_interval: 1m/d' prometheus.yml
    fi
    
    # Запуск контейнеров
    log_info "Запуск контейнеров..."
    docker compose up -d
    
    log_success "Grafana мониторинг установлен!"
    echo ""
    log_info "Доступные сервисы:"
    echo "  - Grafana: http://localhost:3000 (admin/admin)"
    echo "  - Prometheus: http://localhost:9090"
    echo "  - Node Exporter: http://localhost:9100"
    if [[ -n "$subscription" ]]; then
        echo "  - Xray Checker: http://localhost:2112"
    fi
    echo ""
    if [[ -n "$additional_nodes" ]]; then
        log_info "Дополнительные ноды настроены в Prometheus"
        log_warning "Убедитесь, что на всех нодах запущен Node Exporter и открыт порт 9100"
    fi
}

# Установка Uptime-Kuma версии
install_kuma() {
    log_info "Установка мониторинга с Uptime-Kuma..."
    
    # Создание docker-compose.yml
    cat > docker-compose.yml << 'EOF'
volumes:
  uptime-kuma:

services:
  xray-checker:
    container_name: xray-checker
    restart: unless-stopped
    image: kutovoys/xray-checker
    networks:
      - monitoring
    environment:
      - SUBSCRIPTION_URL=PLACEHOLDER_SUBSCRIPTION
    ports:
      - "127.0.0.1:2112:2112"

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
EOF

    # Проверка нужна ли подписка
    echo ""
    read -p "Хотите добавить подписку для Xray-checker? (y/n): " need_subscription
    
    if [[ "$need_subscription" =~ ^[Yy]$ ]]; then
        # Получение подписки
        subscription=$(get_subscription)
        
        # Замена подписки в docker-compose.yml
        sed -i "s|PLACEHOLDER_SUBSCRIPTION|$subscription|g" docker-compose.yml
        
        # Обработка файловых подписок
        if [[ "$subscription" == file://* || "$subscription" == folder://* ]]; then
            local path=${subscription#*://}
            if [[ ! -e "$path" ]]; then
                log_error "Путь $path не существует"
                exit 1
            fi
            
            # Добавление volume для файлов/папок
            if [[ "$subscription" == file://* ]]; then
                sed -i "/xray-checker:/a\\    volumes:\n      - $path:/app/config.json:ro" docker-compose.yml
            else
                sed -i "/xray-checker:/a\\    volumes:\n      - $path:/app/configs:ro" docker-compose.yml
            fi
        fi
    else
        # Удаление xray-checker из docker-compose если подписка не нужна
        sed -i '/xray-checker:/,/^$/d' docker-compose.yml
    fi
    
    # Запуск контейнеров
    log_info "Запуск контейнеров..."
    docker compose up -d
    
    log_success "Uptime-Kuma мониторинг установлен!"
    echo ""
    log_info "Доступные сервисы:"
    echo "  - Uptime-Kuma: http://localhost:3001"
    if [[ "$need_subscription" =~ ^[Yy]$ ]]; then
        echo "  - Xray Checker: http://localhost:2112"
    fi
}

# Установка Node Exporter на ноду
install_node() {
    log_info "Установка Node Exporter на ноду..."
    
    # Создание docker-compose.yml
    cat > docker-compose.yml << 'EOF'
services:
  node-exporter:
    image: prom/node-exporter:latest
    container_name: nodeexp-node
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
EOF

    # Запуск контейнера
    log_info "Запуск Node Exporter..."
    docker compose up -d
    
    log_success "Node Exporter установлен!"
    echo ""
    log_info "Доступные сервисы:"
    echo "  - Node Exporter: http://localhost:9100"
    echo ""
    log_warning "ВАЖНО: Для корректной работы необходимо открыть доступ с IP мастер-ноды:"
    echo "  ufw allow from <MASTER_NODE_IP>"
}

# Интерактивное меню
show_menu() {
    echo ""
    log_info "Выберите тип установки:"
    echo "1) Grafana (Xray-checker + Node Exporter + Prometheus + Grafana)"
    echo "2) Uptime-Kuma (Xray-checker + Uptime-Kuma)"
    echo "3) Node Exporter (только Node Exporter на ноду)"
    echo "4) Выход"
    echo ""
    read -p "Ваш выбор [1-4]: " choice
    
    case $choice in
        1) install_grafana ;;
        2) install_kuma ;;
        3) install_node ;;
        4) log_info "Выход из скрипта"; exit 0 ;;
        *) log_error "Неверный выбор"; show_menu ;;
    esac
}

# Основная функция
main() {
    echo ""
    log_info "=== Скрипт установки мониторинг-утилит ==="
    echo ""
    
    # Проверка зависимостей
    check_dependencies
    
    # Парсинг аргументов командной строки
    case "${1:-}" in
        --grafana)
            install_grafana
            ;;
        --kuma)
            install_kuma
            ;;
        --node)
            install_node
            ;;
        *)
            show_menu
            ;;
    esac
}

# Запуск скрипта
main "$@"