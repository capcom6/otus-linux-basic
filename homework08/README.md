# Домашнее задание №8

Настроить сервер prometheus, настроить сбор метрик веб-сервера.

Цель: в результате выполнения ДЗ вы настроите систему мониторинга prometheus.

В данном задании тренируются навыки:

- настройка ПО;
- анализ метрик web-сервера;
- постановка системы на мониторинг.

Необходимо:

- установить и настроить prometheus;
- установить агент на web-сервер;
- настроить сбор метрик с web-сервера;
- настроить графическое отображение метрик в prometheus.

# Ход работы

Работы выполняется на CentOS 7.

Используется 2 сервера, прописанные для удобства в `/etc/hosts`:

```
10.0.1.1 web
10.0.1.3 prometheus
```

## Установка prometheus

Найдем актуальную версию prometheus в репозитории https://github.com/prometheus/prometheus/releases и установим на сервер:

```bash
# Создаем отдельного пользователя для запуска prometheus без домашней директории и оболочки
sudo useradd --no-create-home --shell /bin/false prometheus
# Скачаем архив с prometheus
curl -LO https://github.com/prometheus/prometheus/releases/download/v2.25.2/prometheus-2.25.2.linux-amd64.tar.gz
# Распакуем в текущую директорию
tar xzvf prometheus-2.25.2.linux-amd64.tar.gz
# Копируем исполняемые файлы в общесистемные локации
sudo cp prometheus-2.25.2.linux-amd64/prometheus prometheus-2.25.2.linux-amd64/promtool /usr/local/bin/
# Создаем каталог для конфигурационных файлов и копируем в него файлы из комплекта поставки
sudo mkdir /etc/prometheus
sudo cp -r prometheus-2.25.2.linux-amd64/consoles/ /etc/prometheus/consoles
sudo cp -r prometheus-2.25.2.linux-amd64/console_libraries/ /etc/prometheus/console_libraries
sudo cp prometheus-2.25.2.linux-amd64/prometheus.yml /etc/prometheus/
# Меняем владельца конфигурационных файлов
sudo chown -R prometheus:prometheus /etc/prometheus
# Создаем каталог для хранения базы данных
sudo mkdir /var/lib/prometheus
sudo chown prometheus:prometheus /var/lib/prometheus
```

Для реализации автоматического запуска создадим юнит systemd в `/etc/systemd/system/prometheus.service`:

```conf
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/prometheus \
    --config.file /etc/prometheus/prometheus.yml \
    --storage.tsdb.path /var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=default.target
```

Проверяем регистрацию сервиса `sudo systemctl status prometheus`:

```
● prometheus.service - Prometheus
   Loaded: loaded (/etc/systemd/system/prometheus.service; disabled; vendor preset: disabled)
   Active: inactive (dead)
```

Активируем и запускаем сервис:

```bash
sudo systemctl enable prometheus && sudo systemctl start prometheus
```

Открываем в браузере страницу http://${SERVER_IP}:9090/ и попадаем в веб-интерфейс Prometheus. Файл конфигурации по-умолчанию уже содержит одну конечную точку для мониторинга самого себя, поэтому, по прошествию некоторого времени, можем выполнить для проверки некоторые запросы:

Например, запрос `prometheus_target_interval_length_seconds` отобразит статистику времени между опросами конечных точек:

```
prometheus_target_interval_length_seconds{instance="localhost:9090", interval="15s", job="prometheus", quantile="0.01"}
	14.996100436
prometheus_target_interval_length_seconds{instance="localhost:9090", interval="15s", job="prometheus", quantile="0.05"}
	14.997974915
prometheus_target_interval_length_seconds{instance="localhost:9090", interval="15s", job="prometheus", quantile="0.5"}
	15.000033092
prometheus_target_interval_length_seconds{instance="localhost:9090", interval="15s", job="prometheus", quantile="0.9"}
	15.001567433
prometheus_target_interval_length_seconds{instance="localhost:9090", interval="15s", job="prometheus", quantile="0.99"}
	15.003983756
```

Исходя из этого можно сделать вывод, что при плановом опросе конечной точки `localhost:9090` в 15 секунд более 99% запросов были выполнены с периодом менее 15.003983756 секунд.

## Настройка мониторинга веб-сервера

В задании не уточняется что подразумевается под метриками веб-сервера, потому рассмотрим 2 варианта: общие метрики сервера, на котором запущен веб-сервер и метрики непосредственно веб-сервера Apache.

### Мониторинг сервера в целом

Для общего мониторинга будем использовать официальный агент Node Exporter, доступный в репозитории https://github.com/prometheus/node_exporter.

```bash
# Создаем отдельного пользователя для запуска exporter без домашней директории и оболочки
sudo useradd --no-create-home --shell /bin/false prometheus-exporter
# Скачаем архив с node exporter
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.1.2/node_exporter-1.1.2.linux-amd64.tar.gz
# Распакуем в текущую директорию
tar xzvf node_exporter-1.1.2.linux-amd64.tar.gz
# Копируем исполняемый файл в общесистемный каталог
sudo cp node_exporter-1.1.2.linux-amd64/node_exporter /usr/local/bin/
```

Для реализации автоматического запуска создадим юнит systemd в `/etc/systemd/system/node_exporter.service`:

```conf
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus-exporter
Group=prometheus-exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=default.target
```

Активируем и запускаем сервис:

```bash
sudo systemctl enable node_exporter && sudo systemctl start node_exporter
# Разрешаем доступ из локальной сети
sudo iptables -A INPUT --source 10.0.1.0/24 -p tcp --dport 9100 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
# Сохраняем настройки
sudo service iptables save
```

На сервере с Prometheus дополняем файл конфигурации `/etc/prometheus/prometheus.yml` в секции `scrape_targets`:

```yml
scrape_configs:
  # The job name is added as a label `job=<job_name>` to any timeseries scraped from this config.
  - job_name: 'prometheus'

    # metrics_path defaults to '/metrics'
    # scheme defaults to 'http'.

    static_configs:
    - targets: ['localhost:9090']

  - job_name: 'web'
    static_configs:
    - targets: ['web:9100']
```

Перезапускаем prometheus командой `sudo systemctl restart prometheus`.

Теперь в веб-консоле prometheus отображается две цели (targets), а через запросы, например, можно посмотреть время работы процессора в разных режимах запросом `node_cpu_seconds_total{job="web"}`:

```
node_cpu_seconds_total{cpu="0", instance="web:9100", job="web", mode="idle"}
	1262.15
node_cpu_seconds_total{cpu="0", instance="web:9100", job="web", mode="iowait"}
	1.98
node_cpu_seconds_total{cpu="0", instance="web:9100", job="web", mode="irq"}
	0
node_cpu_seconds_total{cpu="0", instance="web:9100", job="web", mode="nice"}
	0
node_cpu_seconds_total{cpu="0", instance="web:9100", job="web", mode="softirq"}
	0.33
node_cpu_seconds_total{cpu="0", instance="web:9100", job="web", mode="steal"}
	5.19
node_cpu_seconds_total{cpu="0", instance="web:9100", job="web", mode="system"}
	16.29
node_cpu_seconds_total{cpu="0", instance="web:9100", job="web", mode="user"}
	14.69
```

Откуда делаем вывод, что большую часть времени процессор простаивает.

### Мониторинг веб-сервера Apache

Для мониторинга Apache воспользуемся рекомендуемым на сайте Prometheus агентом https://github.com/Lusitaniae/apache_exporter

```bash
# Скачиваем последний релиз
curl -LO https://github.com/Lusitaniae/apache_exporter/releases/download/v0.8.0/apache_exporter-0.8.0.linux-amd64.tar.gz
# Распаковываем в текущую директорию
tar xzvf apache_exporter-0.8.0.linux-amd64.tar.gz
# Копируем в общесистемный каталог
sudo cp apache_exporter-0.8.0.linux-amd64/apache_exporter /usr/local/bin/
```

Создаем юнит systemd, поскольку Apache запущен на нестандартном порту, то указываем соответствующий параметр запуска:

```conf
[Unit]
Description=Apache Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus-exporter
Group=prometheus-exporter
ExecStart=/usr/local/bin/apache_exporter --scrape_uri=http://localhost:8081/server-status/?auto

[Install]
WantedBy=default.target
```

Для работы агента Apache должен выводить статистику своей работы с помощью модуля mod_status, настроим его работу, создав файл конфигурации `/etc/httpd/conf.d/modstatus.conf`:

```conf
<Location "/server-status">
    SetHandler server-status
    Require local
</Location>
```

Несмотря на то что мы ограничили доступ к данной странице только с локальных адресов через директиву `Require local` данная страница все равно остается доступной извне, поскольку в frontend nginx расположен локально. Таким образом, чтобы ограничить доступ необходимо также настроить запрет доступа к этой странице на стороне nginx. Для этого создадим файл конфигурации `/etc/nginx/default.d/deny_server_status.conf` со следующим содержимым:

```conf
location /server-status {
    return 404;
}
```

Таким образом, при попытке доступа через nginx к URI `/server-status` будет возвращен HTTP-код `404 Not Found`.

Применяем внесенные изменения и запускаем агента:

```bash
sudo systemctl restart httpd
sudo systemctl restart nginx
sudo systemctl start apache_exporter
```

Проверяем что есть доступ к странице статуса Apache и агента:

```bash
curl http://localhost:8081/server-status?auto
curl http://localhost:9117/metrics
```

В завершении настройки разрешаем доступ к агенту только по локальной сети:

```bash
sudo iptables -A INPUT --source 10.0.1.0/24 -p tcp --dport 9117 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
# Сохраняем настройки
sudo service iptables save
```

На сервере с Prometheus приводим файл конфигурации `/etc/prometheus/prometheus.yml` в секции `scrape_targets` к следующему виду:

```yml
scrape_configs:
  # The job name is added as a label `job=<job_name>` to any timeseries scraped from this config.
  - job_name: 'prometheus'

    # metrics_path defaults to '/metrics'
    # scheme defaults to 'http'.

    static_configs:
    - targets: ['localhost:9090']

  - job_name: 'web'
    static_configs:
    - targets: ['web:9100', 'web:9117']
```

Перезапускаем prometheus и наблюдаем в веб-интерфейсе, что у цели `web` теперь имеется 2 конечных точки, а в доступных запросах появились запросы вида `apache_*`. Выполним запрос по параметру `apache_scoreboard` для получение информации о текущем состоянии обработчиков запросов:

```
apache_scoreboard{instance="web:9117", job="web", state="closing"}
	0
apache_scoreboard{instance="web:9117", job="web", state="dns"}
	0
apache_scoreboard{instance="web:9117", job="web", state="graceful_stop"}
	0
apache_scoreboard{instance="web:9117", job="web", state="idle"}
	5
apache_scoreboard{instance="web:9117", job="web", state="idle_cleanup"}
	0
apache_scoreboard{instance="web:9117", job="web", state="keepalive"}
	0
apache_scoreboard{instance="web:9117", job="web", state="logging"}
	0
apache_scoreboard{instance="web:9117", job="web", state="open_slot"}
	250
apache_scoreboard{instance="web:9117", job="web", state="read"}
	0
apache_scoreboard{instance="web:9117", job="web", state="reply"}
	1
apache_scoreboard{instance="web:9117", job="web", state="startup"}
	0
```

Исходя из полученных данных делаем вывод, что сервер простаивает и только 1 обработчик отдает данные, вероятно, как раз агенту.

## Графическое отображение метрик

Веб-интерфейс Prometheus имеет возможность помимо получения данных в табличном виде также строить простейшие графики на основании собранных метрик. Например, можно построить график количества обращений к веб-серверу в единицу времени с помощью запроса `rate(apache_accesses_total[10m])`, перейдя на вкладку *Graph*:

<img src="/images/rate(apache_accesses_total[10m]).png" alt="График доступа к веб-серверу"/>

Однако, для получения расширенной визуальной информации по метрикам можно использовать дополнительно ПО, например, Grafana.

### Установка и настройка Grafana

Установим, запустим и настроим Grafana:

```bash
# Скачиваем официальный пакет
curl -LO https://dl.grafana.com/oss/release/grafana-7.4.5-1.x86_64.rpm
# Устанавливаем в систему
sudo yum install grafana-7.4.5-1.x86_64.rpm
# Активируем и запускаем сервер Grafana
sudo systemctl status grafana-server && sudo systemctl start grafana-server
```

После запуска сервера Grafana открываем его интерфейс в браузере по адресу `http://${SERVER_IP}:3000`, заходим под пользователем admin с паролем по-умолчанию и добавляем источник данных - Prometheus по адресу `http://localhost:9090`.

Далее переходим в раздел *Dashboards* - *Manage* и с помощью кнопки *Import* добавим две панели (dashboards):

1. https://grafana.com/grafana/dashboards/1860 - для мониторинга общесистемных метрик.
2. https://grafana.com/grafana/dashboards/3894 - для мониторинга метрик Apache.

Для доступа в Grafana с ограниченными правами создадим нового пользователя в разделе *Server Admin* - *Users* - *New Users* с именем входа `otus` и правами Viewer.

## Настройка сетевого экрана

В завершении настроим iptables для ограничения доступа к серверу с Prometheus и Grafana:

```bash
yum install iptables-services
# разрешаем входящие подключения по loopback-интерфейсу
iptables -A INPUT -i lo -j ACCEPT
# разрешаем уже установленные соединения
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# отклоняем пакеты с ошибками
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP 
# разрешаем входящие подключения по SSH
iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
# разрешаем входящие подключения к Grafana
iptables -A INPUT -p tcp --dport 3000 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
# все остальные входящие пакеты отклоняем
iptables -P INPUT DROP
# все исходящие соединения разрешаем
iptables -P OUTPUT ACCEPT
# запускаем iptables
systemctl enable iptables && systemctl start iptables
```

## Итоги

Таким образом, был настроен сбор как общесистемных метрик веб-сервера, так и конкретно метрик Apache с помощью Prometheus и соответствующих экспортеров, а также их последующее отображение в Grafana.
