# Backup и восстановление staging

`scripts/deploy/backup-staging.sh` создаёт PostgreSQL custom-format dump и SHA-256 sidecar. Это database backup, а не полный host snapshot: он не включает `.env.staging`, map artifacts, Nominatim DB, Redis, Nginx cache или Docker images.

## Что является system of record

- PostgreSQL/PostGIS — application system of record.
- Redis — cache/queue, отдельно не восстанавливается.
- Map PBF/MBTiles воспроизводятся checksum pipeline и могут копироваться из verified artifact storage.
- Nominatim DB воспроизводится import из verified PBF.
- Nginx map cache disposable.
- `.env.staging`/cryptographic keys требуют отдельного encrypted secret backup. Database dump их не содержит.

Exact location в HTTP staging выключен, но application DB всё равно содержит чувствительные данные. Не выгружай decrypted fields отдельно и не вставляй row content в tickets/logs.

## Создание backup

Проверь readiness и запусти скрипт:

```bash
cd /opt/now/app
sh scripts/deploy/health-staging.sh /opt/now/app/.env.staging
sh scripts/deploy/backup-staging.sh /opt/now/app/.env.staging
```

Default destination — `/opt/now/backups/postgres-<UTC>.dump`; рядом создаётся `.sha256`. Оба файла имеют mode `600`, запись выполняется через `.partial` и atomic rename.

Проверка последнего dump без вывода содержимого:

```bash
backup=$(find /opt/now/backups -maxdepth 1 -type f -name 'postgres-*.dump' -print | sort | tail -n 1)
test -n "$backup"
(cd /opt/now/backups && sha256sum -c "$(basename -- "$backup.sha256")")
docker compose --env-file /opt/now/app/.env.staging \
  -f /opt/now/app/docker-compose.staging.yml \
  exec -T postgres pg_restore --list <"$backup" >/dev/null
unset backup
```

Скрипт не шифрует dump. Mode `600` защищает только от других local users. Для off-host хранения используй host/storage encryption и отдельный restricted transfer channel; encryption keys не должны лежать рядом с dump.

## Retention и цели

Staging baseline: ежедневный dump, RPO до 24 часов, RTO до 4 часов. Установи host-level rotation отдельно и не удаляй последний проверенный restore point. Redis AOF не заменяет backup.

Production требует encrypted snapshots/WAL/PITR, object storage versioning, KMS-separated keys и юридически утверждённый retention. Staging scripts этого не реализуют.

## Restore database

Restore destructive: `pg_restore --clean --if-exists` заменяет объекты в текущей staging database. Сначала создай свежий backup и зафиксируй incident/change window.

Выбери проверенный dump и выполни explicit confirmation:

```bash
cd /opt/now/app
sh scripts/deploy/backup-staging.sh /opt/now/app/.env.staging
backup=$(find /opt/now/backups -maxdepth 1 -type f -name 'postgres-*.dump' -print | sort | tail -n 1)
test -n "$backup"
sh scripts/deploy/restore-staging.sh \
  --backup "$backup" \
  --confirm RESTORE_STAGING \
  --env-file /opt/now/app/.env.staging
unset backup
```

Скрипт принимает только absolute `.dump` внутри `/opt/now/backups`, проверяет sidecar при наличии, останавливает Nginx/API/worker, выполняет restore с `--exit-on-error`, затем запускает stack и ждёт healthchecks.

После restore:

```bash
sh scripts/deploy/health-staging.sh /opt/now/app/.env.staging
sh scripts/maps/smoke-map.sh --base-url http://127.0.0.1
```

Также проверь migration history, PostGIS extension/indexes, ожидаемые aggregate row counts и отсутствие уже expired safe-location records. Не выводи пользовательские строки или coordinates в отчёт drill.

## Maps/Nominatim disaster recovery

Если application DB цела, а map data утрачены:

1. останови ingress/runtime;
2. сохрани существующий Nominatim directory через rename, не удаление;
3. создай новый пустой `/opt/now/data/nominatim`;
4. повтори `prepare-staging-maps.sh`;
5. запусти deploy и full health/map smoke;
6. удали recovery directory только после отдельного approval.

Пример recoverable rename:

```bash
cd /opt/now/app
docker compose --env-file .env.staging -f docker-compose.staging.yml stop nginx api worker nominatim martin
recovery_stamp=$(date -u +%Y%m%dT%H%M%SZ)
mv /opt/now/data/nominatim "/opt/now/data/nominatim.recovery-$recovery_stamp"
install -d -m 0750 /opt/now/data/nominatim
sh scripts/deploy/prepare-staging-maps.sh --env-file .env.staging --data-root /opt/now/data
sh scripts/deploy/deploy-staging.sh --env-file .env.staging
unset recovery_stamp
```

## Application rollback vs restore

`rollback-staging.sh` переключает только retained API/worker images. Он не меняет database schema/data. Используй rollback для совместимого application regression; restore — для подтверждённого повреждения данных. Не пытайся «откатить» необратимую миграцию старым image без compatibility review.

Restore drill выполняется не реже квартала в изолированном environment. Зафиксируй checksum result, длительность, RPO/RTO и privacy checks, затем уничтожь drill data по утверждённой процедуре.
