# Скрипт для авторазвертывания контейнеров с мониторинг-утилитами

Скрипт позволяет полу-автоматически развернуть на VPS две вариации мониторинга:

- Xray-checker + Node Exporter + Prometheus + Grafana
- Xray-checker + Uptime-Kuma
  - Host
  - Node

## Запуск скрипта на VPS:

```curl -sL https://raw.githubusercontent.com/hzhexee/monitoring-utils/main/install.sh | bash```

## Конфигурация Xray-Checker

Xray-Checker принимает 4 формата подписок:
- URL (`sub.12345678.com/longassuuid`)
- BASE64 (`dmxlc3M6Ly91dWlkQGV4YW1wbGUuY29tOjQ0MyVlbmNyeXB0aW9uPW5vbmUmc2VjdXJpdHk9dGxzI3Byb3h5MQ==`)
- JSON-файл V2Ray/Xray (`file:///path/to/config.json`) 
- Папка с JSON-конфигурациями (`folder:///path/to/configs`)

Скрипт поддерживает все 4 формата подписок, НО для формата файла и папки необходимо указывать валидные пути к файлам/папкам - они монтируются в контейнер.

## Важная информация

> [!NOTE]
> Все контейнеры слушают только localhost; доступ извне можно получить либо с помощью проброса портов, либо с помощью Reverse-Proxy.

Доступны следующие флаги выполнения:

- `--grafana` - установка версии с Xray-checker + Node Exporter + Prometheus + Grafana
- `--kuma` - установка версии с Xray-checker + Uptime-Kuma
- `--node` - устаовка Node Exporter на ноду и откытие портов
- Без указания флагов скрипт предложит выбор из трех вышеописанных опций 

> [!WARNING]
Для коректной работы Node Exporter на нодах необходимо открыть доступ с айпи мастер-ноды
i.e. `ufw allow from 1.2.3.4` 

