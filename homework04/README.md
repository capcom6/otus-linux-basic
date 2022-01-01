# Домашнее задание №4

Установить docker, скачать образ nginx, запустить контейнер nginx. Настроить балансировку, как в задании про веб-сервер только в кач-ве FrontEnd использовать контейнер nginx.

Цель: в результате выполнения ДЗ вы получите базовые навыки работы с контейнерами docker.

В данном задании тренируются навыки:

- понимание предметной области задания;
- установка ПО на сервер, работа с файлами конфигурации;
- базовая работа с контейнерами.

Необходимо:

- установить docker;
- найти образ nginx и скачать его;
- запустить контейнер nginx на базе образа nginx;
- подключить конфигурационные файлы nginx из ДЗ с web-сервером в контейнер nginx.

# Ход работы

Задание выполнялось на CentOS 7.

## Установка docker

Для установки docker необходимо предварительно добавить его репозиторий в yum:

```bash
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
```

Длаее устанавливаем необходимые для работы docker пакеты:

```bash
sudo yum install docker-ce docker-ce-cli containerd.io
```

Активируем и запускаем демон docker:

```bash
sudo systemctl enable docker && sudo systemctl start docker 
```

Проверяем состояние:

```bash
sudo systemctl status docker
```

Также останавливаем и отключаем настроенный ранее локальный nginx во избежание конфликта:

```bash
sudo systemctl stop nginx && sudo systemctl disable nginx
```

## Подготовка host-системы

Для nginx контейнера будем использовать существующий файл конфигурации nginx, находящийся в `/etc/nginx/nginx.conf`. Однако, чтобы корректно работала переадресация на upstream необходимо изменить адреса backend-серверов с `localhost` на фактический адрес сервера.

Для этого узнаем текущие присвоенные адреса, а также наименование сетевого интерфейса docker:

```bash
ip a
```

Фрагмент вывода:

```
3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 00:16:3e:0b:d0:1b brd ff:ff:ff:ff:ff:ff
    inet 10.0.1.1/24 brd 10.0.1.255 scope global noprefixroute dynamic eth1
       valid_lft 9562sec preferred_lft 9562sec
    inet6 fe80::15ec:c4e6:2425:fcae/64 scope link noprefixroute
       valid_lft forever preferred_lft forever
4: docker0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 02:42:f9:71:00:31 brd ff:ff:ff:ff:ff:ff
    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0
       valid_lft forever preferred_lft forever
    inet6 fe80::42:f9ff:fe71:31/64 scope link
       valid_lft forever preferred_lft forever
```

Исходя из полученного адреса исправляем секцию upstream:

```
upstream httpd {
    server 172.17.0.1:8081;
    server 172.17.0.1:8082;
    server 172.17.0.1:8083;
}
```

Поскольку ранее на сервере был ограничен доступ к backend только с локальных адресов, то необходимо добавить в цепочку `INPUT` `iptables` правило для разрешения доступа из контейнера:

```bash
sudo iptables -A INPUT -p tcp --dport 8081:8083 -i docker0 -j ACCEPT
```

## Запуск контейнера

Предварительно найдем подходящий образ nginx на https://hub.docker.com/. Это будет официальный образ nginx https://hub.docker.com/_/nginx.

Выполняем запуск контейнера с именем nginx-proxy, задаем соответствие порта 80 host-машины и порта 80 контейнера и монтируем каталог с файлами конфигурации в режиме только чтение:

```bash
sudo docker run --name nginx-proxy -p 80:80 -v /etc/nginx/:/etc/nginx/:ro -d nginx
```

При этом происходит загрузка наиболее свежего (latest) образа nginx и запуск контейнера.

Проверяем запущенные контейнеры:

```bash
sudo docker ps
```

Типовой вывод:

```
CONTAINER ID   IMAGE     COMMAND                  CREATED      STATUS       PORTS                NAMES
1c7b696ccc98   nginx     "/docker-entrypoint.…"   2 days ago   Up 8 hours   0.0.0.0:80->80/tcp   nginx-proxy
```

Проверяем доступность и балансировку нагрузки локально:

```
$ curl http://localhost
Apache8081
$ curl http://localhost
Apache8082
$ curl http://localhost
Apache8083
```

Убеждаемся, что запросы попадают именно в контейнер (приведены последние строки вывода):

```
$ sudo docker logs nginx-proxy

172.17.0.1 - - [09/Mar/2021:14:47:36 +0000] "GET / HTTP/1.1" 200 11 "-" "curl/7.29.0" "-"
172.17.0.1 - - [09/Mar/2021:14:47:37 +0000] "GET / HTTP/1.1" 200 11 "-" "curl/7.29.0" "-"
172.17.0.1 - - [09/Mar/2021:14:47:38 +0000] "GET / HTTP/1.1" 200 11 "-" "curl/7.29.0" "-"
```
