# Настройка связки Node Exporter + Prometheus + Grafana

Запускаем и конфигурируем скрипт (примеры для хоста и для ноды):

![](/static/graf1.png)

![](/static/graf2.png)

Переходим в [Grafana](http://localhost:3000). Входим по комбинации admin/admin, затем создаем новый пароль.

Добавим Prometheus в качестве нового data source:

![](/static/graf3.png)

![](/static/graf4.png)

В connection вводим адрес Prometheus: http://prometheus:9090

![](/static/graf5.png)

Нажимаем Save. Если появилась зеленая плашка - все ОК.

Далее идем во вкладку Dashboards. Нажимаем New -> Import.

![](/static/graf6.png)

Вводим 1860 и нажимаем Load.

![](/static/graf7.png)

Выбираем наш data source и нажимаем Import.

![](/static/graf8.png)

 Готово - теперь у нас есть дашборт Node Exporter Full. В Jobs можно выбрать ноду чтобы посмотреть ее данные.