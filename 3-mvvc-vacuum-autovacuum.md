## 3 MVCC, vacuum/autovacuum
### Установка postgres в docker
- Спуллить самый свежий образ postgres

```
docker search postgres
docker pull  postgres
docker images
```
- Создать docker-сеть
```
sudo docker network create pg-otus-net
```
- Запустить контейнер сервера postgres в созданной сети
```
sudo docker run --name pg-server --network pg-otus-net -e POSTGRES_PASSWORD=postgres -d -p 5432:5432 -v /var/lib/postgres:/var/lib/postgresql/data postgres
```

### pgbench
- Зайти в интерактивном режиме в контейнер сервера
```
sudo docker exec -it pg-server bash
su postgres
```
- Инициализировать и запустить pgbench
```
pgbench -i postgres;
pgbench -c 8 -P 6 -T 60 -U postgres postgres;

-- Результат
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 8
number of threads: 1
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 80635
number of failed transactions: 0 (0.000%)
latency average = 5.931 ms
latency stddev = 3.971 ms
initial connection time = 19.388 ms
tps = 1344.127023 (without initial connection time)

```
- В новой сессии запустить контейнер с клиентом и изменить настройки Автовакуума
```
sudo docker run -it --rm --network pg-otus-net --name pg-client postgres psql -h pg-server -U postgres
alter system set autovacuum_max_workers = 10;
alter system set autovacuum_naptime = '15s';
alter system set autovacuum_vacuum_threshold = 25;
alter system set autovacuum_vacuum_scale_factor = 0.05;
alter system set autovacuum_vacuum_cost_delay = 10;
alter system set autovacuum_vacuum_cost_limit = 1000;
select pg_reload_conf();
```
- Перезапустить сервер, т.к. среди настроек есть настройка autovacuum_max_workers c контекстом postmaster
```
# pg_ctl reload внутри контейнера не приводит к сбросу поля pending_restart
docker container restart 82f0dc79ad69
```
- Убедиться, что настройки применились
```
select * from pg_settings where name like 'autovacuum%' and pending_restart is false;
```

- Повторно инициализировать и запустить pgbench
```
pgbench -i postgres;
pgbench -c 8 -P 6 -T 60 -U postgres postgres;

-- результат
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 8
number of threads: 1
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 77158
number of failed transactions: 0 (0.000%)
latency average = 6.202 ms
latency stddev = 4.400 ms
initial connection time = 22.766 ms
tps = 1285.347964 (without initial connection time)
```

### Работа с MVCC
- Запустить контейнер с клиентом в той же сети, что и сервер. Поключиться к контейнеру в утилите psql
```
sudo docker run -it --rm --network pg-otus-net --name pg-client postgres psql -h pg-server -U postgres
```
- Создать БД otus. Создать таблицу и заполнить сгенерированными данными в размере 1млн строк
```
create database otus;
\c otus;
create table students(id serial, fio varchar);
insert into students(fio) select 'noname' from generate_series(1,1000000);
```
- Посмотреть размер файла с таблицей
```
select pg_size_pretty(pg_total_relation_size('students'));

-- результат
pg_size_pretty
----------------
85 MB
(1 row)
```
- 5 раз обновить все строчки и добавить к каждой строчке любой символ
```
update students set fio=concat(fio, '1');
update students set fio=concat(fio, '2');
update students set fio=concat(fio, '3');
update students set fio=concat(fio, '4');
update students set fio=concat(fio, '5');
```

- Ещё раз посмотреть размер файла с таблицей
```
select pg_size_pretty(pg_total_relation_size('students'));

-- результат
pg_size_pretty
----------------
169 MB
(1 row)
```
- Посмотреть количество мёртвых строчек в таблице и когда последний раз проходил автовакуум
```
SELECT relname, n_live_tup, n_dead_tup, trunc(100*n_dead_tup/(n_live_tup+1))::float "ratio%", last_autovacuum 
FROM pg_stat_user_tables WHERE relname = 'students';

-- результат
relname  | n_live_tup | n_dead_tup | ratio% |        last_autovacuum        
----------+------------+------------+--------+-------------------------------
 students |    1000000 |          0 |      0 | 2025-05-27 17:25:28.070679+00
```
Пояснение: мёртвых строчек 0 т.к. выполнен autovacuum. При этом размер таблицы после autovacuum не изменился.

- Отключить Автовакуум на таблице и опять 5 раз обновить все строки
```
alter table students set (autovacuum_enabled = off);
update students set fio=concat(fio, '6');
update students set fio=concat(fio, '7');
update students set fio=concat(fio, '8');
update students set fio=concat(fio, '9');
update students set fio=concat(fio, '10');
```

- Посмотреть количество мёртвых строчек в таблице и когда последний раз проходил автовакуум
```
SELECT relname, n_live_tup, n_dead_tup, trunc(100*n_dead_tup/(n_live_tup+1))::float "ratio%", last_autovacuum 
FROM pg_stat_user_tables WHERE relname = 'students';

 -- результат
 relname  | n_live_tup | n_dead_tup | ratio% |        last_autovacuum        
----------+------------+------------+--------+-------------------------------
 students |    1000000 |    4999336 |    499 | 2025-05-27 17:25:28.070679+00
(1 row)

```
Пояснение: мертвых точек ~5млн (почему их не ровно 5млн?). Перед обновлением после отключения Автовакуума было 1млн живых записей. Потом было 5 обновлений каждой записи.
Поэтому появилось 5 мёртвых записей на каждую запись, т.е. 5млн.
Дата последнего запуска Автовакуума не изменилась, т.к. для данной таблицы была применена настройка autovacuum_enabled = off
