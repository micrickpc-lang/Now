# Troubleshooting staging

Этот runbook относится к standalone `docker-compose.staging.yml`: bare-IP HTTP на порту `80`, Monaco pilot maps и отключённая exact location. Он не заменяет production incident procedure.

## Безопасный первичный снимок

Запускай диагностику из checkout и передавай env только через `--env-file`. Не публикуй `.env.staging`, вывод развёрнутого `docker compose config`, содержимое базы, токены, тестовые номера или пользовательские координаты.

```bash
cd /opt/now/app
docker compose --env-file .env.staging -f docker-compose.staging.yml config --quiet
docker compose --env-file .env.staging -f docker-compose.staging.yml ps
curl --fail --silent --show-error --max-time 15 http://127.0.0.1/health
curl --fail --silent --show-error --max-time 15 http://127.0.0.1/ready
sh scripts/maps/smoke-map.sh --base-url http://127.0.0.1
```

Если один из шагов упал, собери ограниченный по времени и объёму вывод:

```bash
docker compose --env-file .env.staging -f docker-compose.staging.yml \
  logs --since 15m --tail 200 nginx api worker postgres redis martin nominatim migrate
docker stats --no-stream
```

Nginx staging пишет нормализованный path без query string и адреса клиента, но application logs всё равно проверяй и редактируй перед передачей. Не запускай `docker compose config` без `--quiet`: resolved config содержит секретные значения.

## Порт 80 уже занят

Симптом: Nginx не стартует с `address already in use`.

```bash
sudo ss -lntp 'sport = :80'
docker compose --env-file .env.staging -f docker-compose.staging.yml ps nginx
docker compose --env-file .env.staging -f docker-compose.staging.yml logs --tail 100 nginx
```

Определи владельца listener и согласуй его остановку; не останавливай неизвестный процесс автоматически. Staging Compose должен публиковать только `0.0.0.0:80`. Порты `443` и `2222` находятся вне его scope и не должны меняться.

## Env не проходит проверку

Симптомы: `env file not found`, `variable is required` или `config` возвращает ошибку.

```bash
cd /opt/now/app
test -f .env.staging
stat -c '%a %U:%G %n' .env.staging
docker compose --env-file .env.staging -f docker-compose.staging.yml config --quiet
```

Ожидаемый mode — `600`. Для нового файла используй генератор и вводи public IP и разрешённые тестовые номера интерактивно, чтобы они не попали в shell history:

```bash
read -r -p 'Public IPv4: ' NOW_PUBLIC_IP
read -r -s -p 'Disposable test-number allowlist: ' NOW_TEST_PHONE_ALLOWLIST
printf '\n'
sh scripts/deploy/create-staging-env.sh \
  --public-ip "$NOW_PUBLIC_IP" \
  --phone-allowlist "$NOW_TEST_PHONE_ALLOWLIST" \
  --output /opt/now/app/.env.staging
unset NOW_PUBLIC_IP NOW_TEST_PHONE_ALLOWLIST
```

Не заменяй существующий файл через `--force`, пока не сохранена отдельно зашифрованная recovery copy и не согласована ротация ключей.

## Deploy сообщает о недостающих map artifacts

`deploy-staging.sh` требует PBF, MBTiles и готовую Nominatim DB:

```bash
for artifact in \
  /opt/now/data/maps/region.osm.pbf \
  /opt/now/data/maps/seychas-v1.mbtiles \
  /opt/now/data/nominatim/PG_VERSION; do
  if test -s "$artifact"; then
    stat -c '%a %U:%G %s %n' "$artifact"
  else
    printf 'missing: %s\n' "$artifact"
  fi
done
```

Для первого импорта останови runtime и повтори проверяемый Monaco pipeline:

```bash
docker compose --env-file .env.staging -f docker-compose.staging.yml stop nginx api worker martin nominatim
sh scripts/deploy/prepare-staging-maps.sh \
  --env-file .env.staging \
  --data-root /opt/now/data
sh scripts/deploy/deploy-staging.sh --env-file .env.staging
```

Не запускай initial import одновременно с runtime stack: profile `maps-import` рассчитан на отдельное окно и 768 MiB. Если `PG_VERSION` уже существует, скрипт обновит проверенные map artifacts и пропустит Nominatim import. `--force-import` намеренно не удаляет и не перезаписывает существующую БД; recoverable rebuild описан в [backup/restore](backup-restore.md).

## `/ready` возвращает ошибку

`/health` показывает доступность процесса, а `/ready` — готовность его зависимостей. Сначала найди unhealthy/restarting service:

```bash
docker compose --env-file .env.staging -f docker-compose.staging.yml ps
docker compose --env-file .env.staging -f docker-compose.staging.yml logs --since 10m --tail 200 api postgres redis martin nominatim
docker stats --no-stream
```

- `postgres`/`redis` unhealthy: проверь bind-mount permissions и свободное место через `df -h /opt/now`; не удаляй persistent directories.
- `martin` unhealthy: проверь `/opt/now/data/maps/seychas-v1.mbtiles` через `sh scripts/maps/validate-map.sh --mbtiles /opt/now/data/maps/seychas-v1.mbtiles`, затем повтори deploy.
- `nominatim` unhealthy: проверь наличие `PG_VERSION` и логи; не запускай destructive in-place re-import.
- exit `137` или OOM: убедись, что profile `maps-import` остановлен. Runtime limits суммарно составляют 1088 MiB; не повышай их без повторного sizing host.

После исправления не делай ручной restart отдельных зависимостей без необходимости; воспроизводимый запуск:

```bash
sh scripts/deploy/deploy-staging.sh --env-file .env.staging
sh scripts/deploy/health-staging.sh .env.staging
```

## Карта пустая или не загружается

Раздели transport и визуальную проверку:

```bash
sh scripts/maps/validate-map.sh --mbtiles /opt/now/data/maps/seychas-v1.mbtiles
sh scripts/maps/smoke-map.sh --base-url http://127.0.0.1
curl --fail --silent --show-error http://127.0.0.1/api/v1/maps/style.json >/dev/null
curl --fail --silent --show-error http://127.0.0.1/api/v1/maps/tilejson.json >/dev/null
```

Если server smoke проходит, проверь mobile configuration:

- Android к public HTTP staging подключается только debug-сборкой; release manifest запрещает cleartext.
- iOS не поддерживает этот public bare-IP HTTP контур; нужен HTTPS.
- `API_BASE_URL` должен заканчиваться на `/api/v1`, а `WS_BASE_URL` — не содержать этот suffix.
- После `onStyleLoaded` открой Monaco pilot bounds и убедись, что attribution видима.

`401` от неаутентифицированных `/api/v1/maps/search` и `/api/v1/maps/reverse` — ожидаемая защита, а не отказ Nominatim. Успешный smoke не гарантирует визуально корректный render, поэтому Android picker проверяется отдельно.

## Realtime не подключается

Socket.IO transport использует `/socket.io/`, даже если приложение работает с namespace `/realtime`. Проверь оба маршрута и ограниченные логи:

```bash
docker compose --env-file .env.staging -f docker-compose.staging.yml logs --since 10m --tail 200 nginx api
curl --include --max-time 10 'http://127.0.0.1/socket.io/?EIO=4&transport=polling'
```

Не добавляй API prefix к `WS_BASE_URL`. HTTP `400` на искусственном handshake может быть нормальным без корректной Socket.IO session; важны прохождение запроса через Nginx и отсутствие `404`/`502`.

## Migration не завершилась

Перед повтором сделай backup, затем запусти одноразовый migration service:

```bash
sh scripts/deploy/backup-staging.sh .env.staging
sh scripts/deploy/migrate-staging.sh .env.staging
docker compose --env-file .env.staging -f docker-compose.staging.yml logs --tail 200 migrate
sh scripts/deploy/health-staging.sh .env.staging
```

Не очищай schema и не применяй старый image поверх необратимой миграции. Если regression находится в application image и schema обратно совместима, используй:

```bash
sh scripts/deploy/rollback-staging.sh --env-file .env.staging
sh scripts/deploy/health-staging.sh .env.staging
```

Rollback меняет только retained API/worker images; database migration он не отменяет. Если предыдущий image отсутствует локально или schema несовместима, остановись и следуй review/restore procedure из [backup/restore](backup-restore.md).

## Backup или restore не проходит

Проверь место, checksum и структуру dump без вывода данных:

```bash
df -h /opt/now/backups /opt/now/data
backup=$(find /opt/now/backups -maxdepth 1 -type f -name 'postgres-*.dump' -print | sort | tail -n 1)
test -n "$backup"
(cd /opt/now/backups && sha256sum -c "$(basename -- "$backup.sha256")")
docker compose --env-file .env.staging -f docker-compose.staging.yml \
  exec -T postgres pg_restore --list <"$backup" >/dev/null
unset backup
```

Restore намеренно требует absolute path под `/opt/now/backups` и подтверждение `RESTORE_STAGING`. Пока restore не завершился, оставь ingress закрытым; после него обязательно выполни health и map smoke из [runbook восстановления](backup-restore.md).

## Exact location недоступна

Это ожидаемое поведение bare-IP HTTP staging, а не mobile defect. Серверный feature flag и mobile policy разрешают только безопасные режимы местоположения; exact location остаётся выключенной. Не обходи ограничение локальным патчем. Для проверки exact flow нужен отдельный HTTPS environment с согласованной privacy/security конфигурацией.

## Что приложить к incident ticket

- Git SHA и неперсональный `IMAGE_TAG`.
- UTC interval и названия затронутых services.
- Результаты `config --quiet`, `ps`, health/map smoke и checksum — без env values.
- Ограниченные, отредактированные logs без query strings, токенов, номеров и пользовательских данных.
- Последнее безопасное действие и наличие проверенного backup.

Не прикладывай `.env.staging`, database rows/dumps, authentication payloads, полные test identifiers или снимки карты с пользовательской позицией.
