# Домашнее задание №3

Настроить репликацию MySQL master-slave, настроить бэкап БД на slave (потаблично с указанием позиции бинлога).

Цель: в результате выполнения ДЗ вы создадите репликацию базы данных master-slave для последующей работы с бекапами.

В данном задании тренируются навыки:

- понимание предметной области задания;
- установка ПО на сервер, работа с файлами конфигурации;
- построения репликации master-slave с последующей настройкой бекапа.

Необходимо:

- установить mysql на двух серверах;
- прверить доступность порта mysql с одного сервера на другой;
- создать пользователя для репликации на сервере master;
- настроить реплику slave;
- написать скрипт бекапа баз с реплики.

# Решение

Задание выполнялось на CentOS 7.

## Общая архитектура

Для выполнения задания создано 2 виртаульных сервера:

1. Master-сервер. Внутренний IP 10.0.1.1. Server_id = 1
2. Slave-сервер. Внутренний IP 10.0.1.2. Server_id = 2

Для удобства адресации прописываем адрес master и slave в `/etc/hosts` на обоих серверах:

```bash
echo "master 10.0.1.1" | tee -a /etc/hosts
echo "slave 10.0.1.2" | tee -a /etc/hosts
echo "" | tee -a /etc/hosts
```

## Общие действия для двух серверов

Устанавливаем MySQL:

```bash
yum localinstall -y https://dev.mysql.com/get/mysql80-community-release-el7-3.noarch.rpm && yum install -y mysql-server
```

Настраиваем сетевой экран:

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
# все остальные входящие пакеты отклоняем
iptables -P INPUT DROP
# все исходящие соединения разрешаем
iptables -P OUTPUT ACCEPT
# сохраняем настройки
service iptables save
# запускаем iptables
systemctl enable iptables && systemctl start iptables
```

Для master-сервера прописываем дополнительное правило:

```bash
# разрешаем подключения к MySQL только по локальной сети
iptables -A INPUT --source 10.0.1.0/24 -p tcp --dport 3306 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
```

## Настройка Master-сервера

Для реализации передачи пароля от slave к master в зашифрованном виде создадим пару RSA-ключей, ограничим права доступа к ним и скопируем в каталог данных MySQL-сервера.

```bash
openssl genrsa -out private_key.pem 2048 && openssl rsa -in private_key.pem -pubout -out public_key.pem
chown mysql:mysql private_key.pem public_key.pem
chmod 400 private_key.pem
chmod 444 public_key.pem
mv private_key.pem public_key.pem /var/lib/mysql

# Сразу копируем открытый ключ на slave для дальнейшей настройки
scp /var/lib/mysql/public_key.pem slave:~
```

Для корректной работы репликации необходимо каждому серверу задать уникальный server_id, также пропишем сгенерированные RSA-ключи.

```bash
echo "# Security" | tee -a /etc/my.cnf
echo "caching_sha2_password_private_key_path=private_key.pem" | tee -a /etc/my.cnf
echo "caching_sha2_password_public_key_path=public_key.pem" | tee -a /etc/my.cnf
echo "" | tee -a /etc/my.cnf
echo "# replication" | tee -a /etc/my.cnf
echo "server_id = 1" | tee -a /etc/my.cnf
echo "" | tee -a /etc/my.cnf
```

Запускаем MySQL:

```bash
systemctl enable mysqld && systemctl start mysqld
```

При первом запуске генерируется случайный пароль для пользователя root в MySQL, узнаем его:

```bash
cat /var/log/mysqld.log | grep password
```

Выполним дополнительные настройки безопасности в MySQL путем выполнения скрипта `mysql_secure_installation`. В том числе изменим пароль пользователя root, запретим гостевой доступ и удаленное подключение под root.

Подключимся локально к серверу MySQL с помощь `mysql -u root -p` и создадим пользователя для репликации (пароль скрыт):

```SQL
GRANT REPLICATION SLAVE ON *.* TO 'slave'@'%' IDENTIFIED BY '***';
FLUSH PRIVILEGES;
```

Создадим тестовую базу данных и таблицу в ней:

```SQL
CREATE DATABASE `database`;
USE `database`;
CREATE TABLE `table` (`id` INTEGER NOT NULL PRIMARY KEY, `value` VARCHAR(128) NOT NULL);
```

Получим информацию, необходимую для настройки slave. При этом заблокируем таблицы во избежание изменений до снятия дампа:

```SQL
FLUSH TABLES WITH READ LOCK;
```

В отдельной сессии выполняем дамп базы данных, получаем позицию binlog и копируем на slave:

```bash
mysqldump -u root -p database > dump.sql
mysql -u root -p <<< "SHOW MASTER STATUS\G;" > binlog.pos
scp dump.sql slave:~
scp binlog.pos slave:~
```

Разблокируем таблицы:

```SQL
UNLOCK TABLES;
```

## Настройка Slave-сервера

Проверим подключение со slave на master:

```bash
mysql -h master -u slave -p
```

Копируем ранее полученный с master публичный ключ в каталог данных сервера, предварительно обновив права доступа:

```bash
chown mysql:mysql public_key.pem
chmod 444 public_key.pem
mv public_key.pem /var/lib/mysql
```

Задаем уникальный server_id.

```bash
echo "# replication" | tee -a /etc/my.cnf
echo "server_id = 2" | tee -a /etc/my.cnf
echo "" | tee -a /etc/my.cnf
```

Запускаем MySQL:

```bash
systemctl enable mysqld && systemctl start mysqld
```

При первом запуске генерируется случайный пароль для пользователя root в MySQL, узнаем его:

```bash
cat /var/log/mysqld.log | grep password
```

Выполним дополнительные настройки безопасности в MySQL путем выполнения скрипта `mysql_secure_installation`. В том числе изменим пароль пользователя root, запретим гостевой доступ и удаленное подключение под root.

Подключимся локально к серверу MySQL с помощь `mysql -u root -p` и создадим базу данных:

```SQL
CREATE DATABASE `database`;
```

Импортируем ранее полученный с master дамп:

```bash
mysql -u root -p database < dump.sql
```

Настроим начальные параметры репликации (пароль скрыт) из файла binlog.pos и запустим процесс:

```SQL
CHANGE MASTER TO MASTER_HOST='10.0.1.1', MASTER_USER='slave', MASTER_PASSWORD='***', MASTER_LOG_FILE = 'binlog.000007', MASTER_LOG_POS = 156, MASTER_PUBLIC_KEY_PATH = 'public_key.pem';
START SLAVE;
```

Проверим состояние репликации:

```SQL
SHOW SLAVE STATUS\G;
```

## Проверка работы репликации

Для проверки работы подключимся локально на master к MySQL командой `mysql -u root -p` и добавим данные в таблицу:

```SQL
USE `database`
INSERT INTO `table` (`id`, `value`) VALUES (1, 'Test 1'), (2, 'Test 2'), (3, 'Test 3');
```

Далее на slave-сервере:

```bash
mysql -u root -p database <<< "SELECT * FROM table;"
```

При успешной репликации будут отображены строки, добавленные в таблицу на master.

## Скрипт резервного копирования

Для резервного копирования был создан скрипт `backup.sh`. Данный скрипт позволяет выполнить резервное копирование с локального сервера как отдельных баз данных, так и всех. Резервная копия создается потаблично в виде SQL-скриптов для возможности последующей загрузки по средствам `mysql`.

Сформированная резервная копия имеет следующую структуру:

- binlog.pos - позиция binlog на которую актуальна резервная копия;
- database/ - каталог базы данных `database`:
    - table.sql - дамп таблицы `table`.

Пример запуска скрипта:

```bash
./backup.sh -u user -d destination database
```

Доступные опции:

- -u user - пользователь базы данных, если не указан, то используется имя текущего пользователя ОС;
- -p password - пароль пользователя базы данных для возможности использования в автоматизированных операциях, при отсутствии пароль будет запрошен в интерактивном режиме;
- -d destination - каталог, в который будет помещена резервная копия.

После опций может быть перечислено неограниченное количество имен баз данных. Если не указана ни одна база данных, то выполняется резервное копирование всех доступных БД.

При возникновении ошибок они записываются во временный файл, путь к которому отображается в конце работы скрипта. Также содержимое файла с ошибками отображается в случае завершения с ошибкой одной из команд скрипта.


Для автоматизации резервного копирования вызов данного скрипта помещается в планировщик `cron` с требуемым расписанием и параметрами.
