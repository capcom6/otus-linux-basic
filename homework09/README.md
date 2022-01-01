# Домашнее задание №9

Настроить централизованный сбор логов в ELK.

Цель: в результате выполнения ДЗ Вы настроите систему сбора логов ELK.

В данном задании тренируются навыки:

- установка и настройка ПО;
- анализ сервера на основании данных логов.

Необходимо:

- установить Elasticsearch, Logstash, Kibana;
- настроить ELK Stack;
- настроить сбор логов с web-сервера nginx.

# Ход работы

Работа выполняется на CentOS 7.

Для работы используется 2 сервера, прописанные в `/etc/hosts`:

```
10.0.1.1 web
10.0.1.2 elk
```

## Установка Elasticsearch

Установим зависимости и сам Elasticsearch для хранения информации из логов:

```bash
# Устанавливаем Java, необходимую для работы Elasticsearch
yum install java-1.8.0
# Скачиваем пакет с Elasticsearch
curl -LO https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.12.0-x86_64.rpm
# Выполняем установку пакета в систему
yum install elasticsearch-7.12.0-x86_64.rpm
# Обновляем список сервисов
systemctl daemon-reload
# Активируем и запускаем сервис Elsaticsearch
systemctl enable elasticsearch
systemctl start elasticsearch
# Проверяем состояние
systemctl status elasticsearch
```

Elasticsearch успешно запущен и готов к работе:

```log
● elasticsearch.service - Elasticsearch
   Loaded: loaded (/usr/lib/systemd/system/elasticsearch.service; enabled; vendor preset: disabled)
   Active: active (running) since Чт 2021-04-01 14:51:49 UTC; 2 days ago
     Docs: https://www.elastic.co
 Main PID: 20378 (java)
   CGroup: /system.slice/elasticsearch.service
           ├─20378 /usr/share/elasticsearch/jdk/bin/java -Xshare:auto -Des.networkaddress.cache.ttl=60 -Des.networkaddress.cache.negative.ttl=10 -XX:+AlwaysPreTouch -Xss1m -Djava...
           └─20534 /usr/share/elasticsearch/modules/x-pack-ml/platform/linux-x86_64/bin/controller

апр 01 14:51:03 wvds126112 systemd[1]: Starting Elasticsearch...
апр 01 14:51:49 wvds126112 systemd[1]: Started Elasticsearch.
```

Из файла конфигурации `/etc/elasticsearch/elasticsearch.yml` узнаем порт, на котором Elasticsearch ожидает подключения и проверяем слушающие сокеты:

```bash
ss -tlnp | grep 9200
```

Elasticsearch готов к подключениям с локального компьютера:

```log
LISTEN     0      128     [::ffff:127.0.0.1]:9200                  [::]:*                   users:(("java",pid=20378,fd=285))
LISTEN     0      128      [::1]:9200                  [::]:*                   users:(("java",pid=20378,fd=283))
```

## Установка Logstash

Устанавливаем Logstash для расширенного парсинга логов:

```bash
# Скачиваем пакет
curl -LO https://artifacts.elastic.co/downloads/logstash/logstash-7.12.0-x86_64.rpm
# Устанавливаем в систему
yum install logstash-7.12.0-x86_64.rpm
# Обновляем список сервисов
systemctl daemon-reload
```

Создаем `/etc/logstash/conf.d/logstash-nginx.conf` с описанием порядка разбора лога:

```conf
# входящие данные будем получать от Filebeat на порту 5400
input {
    beats {
        port => 5400
    }
}

filter {
# для начала разберем входящее сообщение плагином grok на основании встроенного в него шаблона для Apache
 grok {
   match => [ "message" , "%{COMBINEDAPACHELOG}+%{GREEDYDATA:extra_fields}"]
   overwrite => [ "message" ]
 }
# преобразуем типы некоторых полей в более подходящие для анализа
 mutate {
   convert => ["response", "integer"]
   convert => ["bytes", "integer"]
   convert => ["responsetime", "float"]
 }
# применим плагин geoip для определение местоположения по ip
 geoip {
   source => "clientip"
   add_tag => [ "nginx-geoip" ]
 }
# определяем поле с датой события
 date {
   match => [ "timestamp" , "dd/MMM/YYYY:HH:mm:ss Z" ]
   remove_field => [ "timestamp" ]
 }
# парсим информацию о браузере
 useragent {
   source => "agent"
 }
}

# результат отправляем в локальный Elasticsearch
output {
 elasticsearch {
   hosts => ["localhost:9200"]
   index => "weblogs-%{+YYYY.MM.dd}"
   document_type => "nginx_logs"
 }
 # для отладки также выводим в stdout
 stdout { codec => rubydebug }
}
```

```bash
# Активируем и запускаем сервис Logstash
systemctl enable logstash
systemctl start logstash
# Проверяем статус
systemctl status logstash
```

Logstash успешно запущен:

```log
● logstash.service - logstash
   Loaded: loaded (/etc/systemd/system/logstash.service; disabled; vendor preset: disabled)
   Active: active (running) since Чт 2021-04-01 14:52:48 UTC; 2 days ago
 Main PID: 20593 (java)
   CGroup: /system.slice/logstash.service
           └─20593 /usr/share/logstash/jdk/bin/java -Xms1g -Xmx1g -XX:+UseConcMarkSweepGC -XX:CMSInitiatingOccupancyFraction=75 -XX:+UseCMSInitiatingOccupancyOnly -Djava.awt.head...
```

## Установка Filebeat

На сервере с Nginx устанавливаем Filebeat:

```bash
# Скачиваем пакет
curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-7.12.0-x86_64.rpm
# Устанавливаем в систему
yum install filebeat-7.12.0-x86_64.rpm
# Обновляем список сервисов
systemctl daemon-reload 
```

Заменяем файл конфигурации по-умолчанию следующим:

```yaml
filebeat.inputs:
- type: log
  paths:
    - /var/log/nginx/*.log
  exclude_files: ['\.gz$']

output.logstash:
  hosts: ["elk:5400"]
```

Запускаем сервис:

```bash
sudo systemctl enable filebeat
sudo systemctl start filebeat
sudo systemctl status filebeat
```

Получаем информацию о текущем статусе:

```log
● filebeat.service - Filebeat sends log files to Logstash or directly to Elasticsearch.
   Loaded: loaded (/usr/lib/systemd/system/filebeat.service; disabled; vendor preset: disabled)
   Active: active (running) since Сб 2021-04-03 02:07:49 UTC; 1 day 5h ago
     Docs: https://www.elastic.co/products/beats/filebeat
 Main PID: 31036 (filebeat)
   CGroup: /system.slice/filebeat.service
           └─31036 /usr/share/filebeat/bin/filebeat --environment systemd -c /etc/filebeat/filebeat.yml --path.home /usr/share/filebeat --path.config /etc/filebeat --path.data /v...
```

Теперь логи Nginx будут считаны Filebeat и переданы в Logstash.

## Установка Kibana

Аналогично устанавливаем Kibana для отображения аналитики по логам:

```bash
# Скачиваем пакет
curl -LO https://artifacts.elastic.co/downloads/kibana/kibana-7.12.0-x86_64.rpm
# Устанавливаем в систему
yum install kibana-7.12.0-x86_64.rpm
# Обновляем список сервисов
systemctl daemon-reload
# Активируем и запускаем Kibana
systemctl enable kibana
systemctl start kibana
# Проверяем состояние
systemctl status kibana
```

Kibana успешно запущена и готова к работе:

```log
● kibana.service - Kibana
   Loaded: loaded (/etc/systemd/system/kibana.service; disabled; vendor preset: disabled)
   Active: active (running) since Сб 2021-04-03 14:00:15 UTC; 17h ago
     Docs: https://www.elastic.co
 Main PID: 26942 (node)
   CGroup: /system.slice/kibana.service
           └─26942 /usr/share/kibana/bin/../node/bin/node /usr/share/kibana/bin/../src/cli/dist --logging.dest="/var/log/kibana/kibana.log" --pid.file="/run/kibana/kibana.pid"

апр 03 14:00:15 wvds126112 systemd[1]: Started Kibana.
```

Проверяем настройки по-умолчанию в файле `/etc/kibana/kibana.yml`, в частности, интересны значения по-умолчанию для следующих параметров:

```yaml
server.port: 5601
server.host: "localhost"
elasticsearch.hosts: ["http://localhost:9200"]
```

Таким образом, Kibana уже настроена на подключение к локальному Elasticsearch и ожидает входящих подключений с локального компьютера на порт 5601. Оставляем настройки по-умолчанию.

### Настройка внешнего доступа к Kibana

Поскольку интерфейс Kibana не имеет встроенных возможностей для авторизации воспользуемся для этих целей Nginx:

```bash
# Добавляем репозиторий
yum install epel-release
# Устанавливаем Nginx
yum install nginx
# Устаналиваем утилиты, среди которых нас интересует htpasswd для создания файлов авторизации
yum install httpd-tools
# Создаем каталог для хранения файла с парами логин-пароль
mkdir /etc/nginx/private
# Создаем файл с одним пользователем otus, пароль вводим в интерактивном режиме
htpasswd -c /etc/nginx/private/kibana.htpasswd otus
# Ограничиваем доступ к файлу: запрещаем чтение всем, кроме пользователя и группы nginx
chmod o-r /etc/nginx/private/kibana.htpasswd
chown nginx:nginx /etc/nginx/private/kibana.htpasswd
```

Изменяем файл `/etc/nginx/nginx.conf` для работы с авторизацией и перенаправления запросов в Kibana:

```conf
    server {
        listen       80 default_server;
        listen       [::]:80 default_server;
        server_name  _;
        root         /usr/share/nginx/html;

        # Load configuration files for the default server block.
        include /etc/nginx/default.d/*.conf;

        auth_basic		"Authorization";
        auth_basic_user_file	/etc/nginx/private/kibana.htpasswd;

        location / {
            # Перенаправление на Kibana
            proxy_pass http://localhost:5601;
        }

        error_page 404 /404.html;
        location = /404.html {
        }

        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
        }
    }
```

Активируем и запускаем Nginx:

```bash
systemctl enable nginx && systemctl start nginx
```

### Настройка интерфейса Kibana

Открываем в браузере интерфейс Kibana по адресу http://kibana.capcomhome.info, вводим заданные ранее данные для авторизации.

Следуя инструкциям Kibana создаем шаблон индексирования `weblogs-*`.

Переходим в раздел *Analytics* - *Discover* и наблюдаем уже принятые данные:

<img src="/images/discover.png">

Перейдем в раздел *Analytics* - *Dashboard* и создадим новую панель с двумя диаграммами: распределение HTTP-кодов ответа (поле `response`) и стран клиента (поле `geoip.country_name.keyword`). Получаем панель следующего вида:

<img src="/images/dashboard.png">

## Безопасность

Дополнительно настраиваем сетевой экран на сервере `elk`:

```bash
yum install -y iptables-services
# разрешаем входящие подключения по loopback-интерфейсу
iptables -A INPUT -i lo -j ACCEPT
# разрешаем уже установленные соединения
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# отклоняем пакеты с ошибками
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP 
# разрешаем входящие подключения по SSH
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
# разрешаем входящие подключения по HTTP к Nginx
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
# разрешаем входящие подключения к Elasticsearch по локальной сети
iptables -A INPUT --source 10.0.1.0/24 -p tcp --dport 9200 -j ACCEPT
# все остальные входящие пакеты отклоняем
iptables -P INPUT DROP
# все исходящие соединения разрешаем
iptables -P OUTPUT ACCEPT
# сохраняем настройки
service iptables save
# запускаем iptables
systemctl enable iptables && systemctl start iptables
```

# Итоги

Таким образом, был реализован сбор логов с сервера Nginx с помощью Filebeat, их разбор с помощью Logstash, хранение в Elasticsearch и анализ с визуализацией в Kibana.
