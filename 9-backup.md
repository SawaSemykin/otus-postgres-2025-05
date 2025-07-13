## 9 Работа с бекапами
Для работы с бекапами используется демонстрационная БД с сайта edu.postgrespro.ru. Установка
```shell
sudo apt install unzip
wget --quiet https://edu.postgrespro.ru/demo_small.zip
unzip demo_small.zip
sudo -u postgres psql < demo_small.sql
sudo -u postgres psql -d demo
```
#### Создать бекапы с помощью pg_dump, pg_dumpall и pg_basebackup сравнить скорость создания и возможности.
#### pg_dump
```shell
# Логическое копирование
# + можно восстановиться на кластере другоой основной версии
# + можно восстановиться на другой архитектуре
# + поддерживает параллельное выполенение (-j 8)
# + позволяет ограничить набор выгружаемых объектов (таблицы --table, схемы --schema-only, данные --data-only и т.п.)
# 
# - по умолчанию не создаёт tablespace и юзеров
# - невысокая скорость относительно физического копирования 

# в 1-м терминале. Делаем дамп базы demo в файл demo_arch.sql
sudo -u postgres pg_dump -d demo -C -U postgres > demo_arch.sql

# во 2-м терминале. Удаляем базу demo для последующего восстановления
postgres=# drop database demo;
DROP DATABASE

# в 1-м терминале. Восстанавливаем базу demo из файла demo_arch.sql
sudo -u postgres psql -U postgres < demo_arch.sql

# во 2-м терминале
postgres=# \l
                                                   List of databases
   Name    |  Owner   | Encoding | Locale Provider | Collate |  Ctype  | ICU Locale | ICU Rules |   Access privileges   
-----------+----------+----------+-----------------+---------+---------+------------+-----------+-----------------------
 demo      | postgres | UTF8     | libc            | C.UTF-8 | C.UTF-8 |            |           | 
 postgres  | postgres | UTF8     | libc            | C.UTF-8 | C.UTF-8 |            |           | 
 template0 | postgres | UTF8     | libc            | C.UTF-8 | C.UTF-8 |            |           | =c/postgres          +
           |          |          |                 |         |         |            |           | postgres=CTc/postgres
 template1 | postgres | UTF8     | libc            | C.UTF-8 | C.UTF-8 |            |           | =c/postgres          +
           |          |          |                 |         |         |            |           | postgres=CTc/postgres
(4 rows)

```
#### pg_dumall
```shell
# Работает так же как и pg_dump + имеет возможность сохранять глобальные данные
# + сохраняет весь кластер, включая роли и табличные пространства
# - параллельное выполнение не поддерживается
# Best practice: использовать pg_dumpall в комбинации pd_dump. pg_dumpall для выгрузки только глобальных объектов, pg_dump для выгрузки бд
```
#### pg_basebackup
```shell
# Физическое копирование
# + скорость восстановление
# + можно восстановить кластер на определённым момент времени - бе
#
# - нельзя восстановить отдельную БД только весь кластер
# - восстановление только на той же основноой версии и архитектуре
#
# 1. Убедимся, что wal_level установлен в replica
postgres=# show wal_level;
 wal_level 
-----------
 replica
(1 row)

# 2. Создадим новый кластер. Обязательно той же основной версии! В данном случае 16
pg_lsclusters
Ver Cluster Port Status Owner    Data directory              Log file
16  main    5432 online postgres /var/lib/postgresql/16/main /var/log/postgresql/postgresql-16-main.log

sudo pg_createcluster -d /var/lib/postgresql/16/main2 16 main2

sudo ls -la /var/lib/postgresql/16
total 16
drwxr-xr-x  4 postgres postgres 4096 Jul 13 15:52 .
drwxr-xr-x  3 postgres postgres 4096 Jul 12 14:20 ..
drwx------ 19 postgres postgres 4096 Jul 12 11:01 main
drwx------ 19 postgres postgres 4096 Jul 13 15:52 main2

# 3. Удадяем в нём каталог main2
sudo rm -rf /var/lib/postgresql/16/main2
sudo ls -la /var/lib/postgresql/16
total 12
drwxr-xr-x  3 postgres postgres 4096 Jul 13 15:56 .
drwxr-xr-x  3 postgres postgres 4096 Jul 12 14:20 ..
drwx------ 19 postgres postgres 4096 Jul 12 11:01 main

# 4. Создаём копию. Проверяем, что снова появился каталог main2
sudo -u postgres pg_basebackup -D /var/lib/postgresql/16/main2
sudo ls -la /var/lib/postgresql/16
total 16
drwxr-xr-x  4 postgres postgres 4096 Jul 13 15:58 .
drwxr-xr-x  3 postgres postgres 4096 Jul 12 14:20 ..
drwx------ 19 postgres postgres 4096 Jul 12 11:01 main
drwx------ 19 postgres postgres 4096 Jul 13 15:58 main2

# 5. Запустим восстановленный кластер и убедимся, что в нем есть БД demo из первого кластера
pg_lsclusters
Ver Cluster Port Status Owner    Data directory               Log file
16  main    5432 online postgres /var/lib/postgresql/16/main  /var/log/postgresql/postgresql-16-main.log
16  main2   5433 down   postgres /var/lib/postgresql/16/main2 /var/log/postgresql/postgresql-16-main2.log

sudo pg_ctlcluster 16 main2 start
sudo -u postgres psql -p 5433

postgres=# \l
                                                   List of databases
   Name    |  Owner   | Encoding | Locale Provider | Collate |  Ctype  | ICU Locale | ICU Rules |   Access privileges   
-----------+----------+----------+-----------------+---------+---------+------------+-----------+-----------------------
 demo      | postgres | UTF8     | libc            | C.UTF-8 | C.UTF-8 |            |           | 
 postgres  | postgres | UTF8     | libc            | C.UTF-8 | C.UTF-8 |            |           | 
 template0 | postgres | UTF8     | libc            | C.UTF-8 | C.UTF-8 |            |           | =c/postgres          +
           |          |          |                 |         |         |            |           | postgres=CTc/postgres
 template1 | postgres | UTF8     | libc            | C.UTF-8 | C.UTF-8 |            |           | =c/postgres          +
           |          |          |                 |         |         |            |           | postgres=CTc/postgres
(4 rows)

# 6. Удалим резервный кластер
sudo pg_dropcluster 16 main2 --stop
pg_lsclusters
Ver Cluster Port Status Owner    Data directory              Log file
16  main    5432 online postgres /var/lib/postgresql/16/main /var/log/postgresql/postgresql-16-main.log

```
#### Настроить копирование WAL файлов.
#### Восстановить базу на другой машине PostgreSQL на заданное время, используя ранее созданные бекапы и WAL файлы.
```shell
# Для создания папки выполните команду
sudo mkdir /archive_wal

# Для предоставления прав выполните команду
sudo chown -R postgres:postgres /archive_wal

# включить режим архивирования WAL и прописать команду архивирования в файл конфигурации Postgres.
postgres=# ALTER SYSTEM SET archive_mode = 'on';
ALTER SYSTEM
postgres=# ALTER SYSTEM SET archive_command = 'test ! -f /archive_wal/%f && cp %p /archive_wal/%f';
ALTER SYSTEM

# Чтобы изменения параметров вступили в силу, нужно перезапустить сервер:
sudo systemctl restart postgresql

# Создать каталог для полного копирования
sudo mkdir /full_backup
sudo chown -R postgres:postgres /full_backup

# Для проведения полного резервного копирования выполните команду
sudo -u postgres pg_basebackup -v -D /full_backup
# вывод
pg_basebackup: initiating base backup, waiting for checkpoint to complete
pg_basebackup: checkpoint completed
pg_basebackup: write-ahead log start point: 0/2C000028 on timeline 1
pg_basebackup: starting background WAL receiver
pg_basebackup: created temporary replication slot "pg_basebackup_31109"
pg_basebackup: write-ahead log end point: 0/2C000100
pg_basebackup: waiting for background process to finish streaming ...
pg_basebackup: syncing data to disk ...
pg_basebackup: renaming backup_manifest.tmp to backup_manifest
pg_basebackup: base backup completed

# В клиенте Postgres, например, DBeaver, выполните команды:
create table test (c1 text);
insert into test values ('Проверка восстановления с использованием WAL');
demo=# select now();
              now              
-------------------------------
 2025-07-13 17:02:52.275384+00 
(1 row)

demo=# update tickets set passenger_name = 'UKNOWN';
UPDATE 366733

demo=# select * from tickets limit 10;
   ticket_no   | book_ref | passenger_id | passenger_name |       contact_data        
---------------+----------+--------------+----------------+---------------------------
 0005432000987 | 06B046   | 8149 604011  | UKNOWN         | {"phone": "+70127117011"}
 0005432000988 | 06B046   | 8499 420203  | UKNOWN         | {"phone": "+70378089255"}
 0005432000989 | E170C3   | 1011 752484  | UKNOWN         | {"phone": "+70760429203"}
 0005432020662 | BF66FF   | 2859 507139  | UKNOWN         | {"phone": "+70183675161"}
 0005432020903 | 29577D   | 6269 794131  | UKNOWN         | {"phone": "+70506417931"}
 0005432034661 | 78B91F   | 4104 174362  | UKNOWN         | {"phone": "+70478554566"}
 0005432035129 | 9A7C9F   | 7380 365920  | UKNOWN         | {"phone": "+70256836192"}
 0005432035431 | D35D3C   | 6817 727324  | UKNOWN         | {"phone": "+70100650097"}
 0005432042676 | DC4889   | 3152 702249  | UKNOWN         | {"phone": "+70143754462"}
 0005432042739 | D8AC64   | 5453 486061  | UKNOWN         | {"phone": "+70054165531"}
(10 rows)

#---- восстановления на определенный момент времени:
# 1. Остановите сервер Postgres:
sudo systemctl stop postgresql

# 2. Сохраните текущее состояние данных Postgres (на всякий случай).
sudo mkdir /old_data
# И после этого переносим в него весь каталог с данными Postgres:
sudo mv /var/lib/postgresql/16/main /old_data
# После этого нужно воссоздать каталог main:
sudo mkdir /var/lib/postgresql/16/main

# 3. Копируем в main полную резервную копию:
sudo cp -a /full_backup/. /var/lib/postgresql/16/main

# 4. В восстановленной резервной копии нужно почистить каталог pg_wal:
sudo rm -rf /var/lib/postgresql/16/main/pg_wal/*
# и скопировать в этот каталог последний вариант WAL
sudo cp -a /old_data/main/pg_wal/. /var/lib/postgresql/16/main/pg_wal

# 5. Затем редактируем файл конфигурации postgresql.conf
restore_command = 'cp /archive_wal/%f "%p"' -- (команда должна быть строго обратной команде на архивирование WAL )
recovery_target_time = '2025-07-13 17:02:52.275384+00' --(то время, которое мы зафиксировали).

# Затем создаем пустой файл recovery.signal:
sudo touch /var/lib/postgresql/16/main/recovery.signal

# меняем владение и права на каталог main с подкаталогами:
sudo chown -R postgres:postgres /var/lib/postgresql/16/main/
sudo chmod -R 750 /var/lib/postgresql/16/main/

# И запускаем сервер:
sudo systemctl start postgresql

# 6.	Проверяем в клиенте, что таблица test в базе данных восстановлена:
demo=# set search_path = bookings;
SET
demo=# select * from test;
                      c1                      
----------------------------------------------
 Проверка восстановления с использованием WAL
(1 row)

# И ошибочный update в таблице tickets отменен:
demo=# select * from tickets limit 10;
   ticket_no   | book_ref | passenger_id |   passenger_name    |                                   contact_data                                   
---------------+----------+--------------+---------------------+----------------------------------------------------------------------------------
 0005432000987 | 06B046   | 8149 604011  | VALERIY TIKHONOV    | {"phone": "+70127117011"}
 0005432000988 | 06B046   | 8499 420203  | EVGENIYA ALEKSEEVA  | {"phone": "+70378089255"}
 0005432000989 | E170C3   | 1011 752484  | ARTUR GERASIMOV     | {"phone": "+70760429203"}
 0005432000990 | E170C3   | 4849 400049  | ALINA VOLKOVA       | {"email": "volkova.alina_03101973@postgrespro.ru", "phone": "+70582584031"}
 0005432000991 | F313DD   | 6615 976589  | MAKSIM ZHUKOV       | {"email": "m-zhukov061972@postgrespro.ru", "phone": "+70149562185"}
 0005432000992 | F313DD   | 2021 652719  | NIKOLAY EGOROV      | {"phone": "+70791452932"}
 0005432000993 | F313DD   | 0817 363231  | TATYANA KUZNECOVA   | {"email": "kuznecova-t-011961@postgrespro.ru", "phone": "+70400736223"}
 0005432000994 | CCC5CB   | 2883 989356  | IRINA ANTONOVA      | {"email": "antonova.irina04121972@postgrespro.ru", "phone": "+70844502960"}
 0005432000995 | CCC5CB   | 3097 995546  | VALENTINA KUZNECOVA | {"email": "kuznecova.valentina10101976@postgrespro.ru", "phone": "+70268080457"}
 0005432000996 | 1FB1E4   | 6866 920231  | POLINA ZHURAVLEVA   | {"phone": "+70639918455"}
(10 rows)

# 7. После всех проверок можно открыть доступ к серверу не только на чтение, но и на запись:
demo=# select pg_wal_replay_resume();
 pg_wal_replay_resume 
----------------------
 
(1 row)
```
