# Развёртывание bare-IP staging на сервере

Этот runbook относится только к standalone staging из `docker-compose.staging.yml`. Он публикует HTTP на TCP `80`. Существующие listeners и сервисы на `443` и `2222` не изменяются; не останавливай и не перенастраивай их ради этого deployment.

## Ограничения контура

- TLS отсутствует: трафик, токены и содержимое не защищены от перехвата в недоверенной сети.
- `ALLOW_EXACT_LOCATION=false`; exact room sharing должен оставаться недоступным и на сервере, и в mobile UI.
- Media/ClamAV/object storage, admin UI и production SMS/Push не входят в stack.
- Пилотный регион карт — Монако; это не production dataset.
- Default runtime ограничен 1088 MiB. Профиль `maps-import` имеет отдельный лимит 768 MiB и запускается до runtime, а не одновременно с ним.
- Deploy scripts ожидают repository в `/opt/now/app` и persistent data в `/opt/now/data`.

## 1. Preflight

На Linux-сервере должны быть Git, Docker Engine, Compose v2, `curl`, `openssl`, `sha256sum` и достаточно свободного места. Работай из уже проверенного checkout:

```bash
cd /opt/now/app
git status --short
git rev-parse --verify HEAD
docker --version
docker compose version
```

Проверь listeners до изменений:

```bash
sudo ss -lntp
```

TCP `80` должен быть свободен. Наличие listeners на `443` и `2222` ожидаемо и не является конфликтом.

Подготовь bind directories. Map artifacts и deployment state принадлежат deploy-user; Nginx cache — uid/gid `101` из unprivileged image:

```bash
deploy_user=$(id -un)
deploy_group=$(id -gn)
sudo install -d -m 0750 -o "$deploy_user" -g "$deploy_group" \
  /opt/now/data \
  /opt/now/data/postgres \
  /opt/now/data/redis \
  /opt/now/data/maps \
  /opt/now/data/nominatim \
  /opt/now/data/deployments \
  /opt/now/backups
sudo install -d -m 0750 -o 101 -g 101 /opt/now/data/nginx-map-cache
unset deploy_user deploy_group
```

Container entrypoints устанавливают внутреннее ownership PostgreSQL, Redis и Nominatim при первом старте. Не выполняй recursive `chmod 777`.

## 2. Private environment

Не копируй credentials из README или shell history. Передай public IPv4 и разрешённые disposable test numbers скрипту через временные shell variables; в документации значения намеренно отсутствуют:

```bash
printf 'Public IPv4: ' >&2
IFS= read -r NOW_PUBLIC_IP
printf 'Allowed test phones (E.164, comma-separated; input hidden): ' >&2
IFS= read -r -s NOW_TEST_PHONE_ALLOWLIST
printf '\n' >&2
sh scripts/deploy/create-staging-env.sh \
  --public-ip "$NOW_PUBLIC_IP" \
  --phone-allowlist "$NOW_TEST_PHONE_ALLOWLIST" \
  --output /opt/now/app/.env.staging
unset NOW_PUBLIC_IP NOW_TEST_PHONE_ALLOWLIST
stat -c '%a %U:%G %n' /opt/now/app/.env.staging
```

Ожидаемый mode — `600`. Скрипт генерирует каждое секретное значение локально, пишет файл atomically и ничего чувствительного не печатает. Не используй `cat`, `docker compose config` без `--quiet` или shell tracing (`set -x`) с этим файлом.

## 3. Map build и одноразовый import

На новом пустом data root выполни до запуска API:

```bash
cd /opt/now/app
sh scripts/deploy/prepare-staging-maps.sh \
  --env-file /opt/now/app/.env.staging \
  --data-root /opt/now/data
```

Скрипт:

1. загружает Monaco PBF и проверяет remote MD5 до/после download;
2. проверяет/записывает SHA-256 sidecar;
3. строит `seychas-v1.mbtiles` закреплённым Tilemaker;
4. валидирует style/assets/MBTiles;
5. публикует artifacts atomically в `/opt/now/data/maps`;
6. запускает только profile `maps-import` с лимитом 768 MiB;
7. ждёт Nominatim status, останавливает import container и проверяет `PG_VERSION`.

Если `PG_VERSION` уже существует, in-place re-import намеренно не выполняется. Для нового geocoder dataset сначала останови runtime и перемести старый каталог в отдельный recovery path; не удаляй его до успешной проверки нового import.

## 4. Deploy

```bash
cd /opt/now/app
sh scripts/deploy/deploy-staging.sh \
  --env-file /opt/now/app/.env.staging
```

По умолчанию image tag — первые 12 символов текущего Git SHA. Скрипт выполняет `compose config --quiet`, строит migrate/API/worker images, запускает migration job, затем ждёт healthchecks до 10 минут. После здорового запуска записываются `/opt/now/data/deployments/current` и `previous`.

Проверь контур:

```bash
sh scripts/deploy/health-staging.sh /opt/now/app/.env.staging
curl --fail --silent --show-error http://127.0.0.1/health
curl --fail --silent --show-error http://127.0.0.1/ready
sudo ss -lntp
```

Map smoke фиксирует status, content type и bytes для style, TileJSON, sprites, glyph envelope и pilot tile. Он не доказывает визуальный rendering: это отдельно проверяется на Android/MapLibre.

## 5. Миграции

Deploy уже запускает `migrate` до API. Для отдельного migration window сначала создай backup, затем:

```bash
sh scripts/deploy/backup-staging.sh /opt/now/app/.env.staging
sh scripts/deploy/migrate-staging.sh /opt/now/app/.env.staging
sh scripts/deploy/health-staging.sh /opt/now/app/.env.staging
```

Migration должна быть forward-compatible с предыдущим application image. Автоматический rollback схемы отсутствует.

## 6. Логи и состояние

```bash
docker compose \
  --env-file /opt/now/app/.env.staging \
  -f /opt/now/app/docker-compose.staging.yml \
  ps
docker compose \
  --env-file /opt/now/app/.env.staging \
  -f /opt/now/app/docker-compose.staging.yml \
  logs --since 30m --tail 200 api worker nginx martin nominatim
```

Nginx access log содержит method, нормализованный path, status, bytes, duration и request id; query, IP, cookies и authorization не логируются. Не включай debug logging и не вставляй содержимое `.env.staging` в incident notes.

## 7. Rollback приложения

Rollback использует локально сохранённые предыдущие images и не откатывает БД:

```bash
sh scripts/deploy/rollback-staging.sh \
  --env-file /opt/now/app/.env.staging
sh scripts/deploy/health-staging.sh /opt/now/app/.env.staging
```

Если `previous` ещё не создан, передай только заранее проверенный retained tag через `--image-tag`. Не запускай старое приложение поверх несовместимой миграции. При сомнении останови ingress и следуй restore runbook из [backup-restore.md](backup-restore.md).

## 8. Mobile staging build

Bare-IP HTTP допускается только Android debug overlay. На build machine:

```bash
cd apps/mobile
flutter pub get
printf 'Staging IPv4: ' >&2
IFS= read -r NOW_PUBLIC_IP
flutter build apk --debug \
  --dart-define=APP_ENV=staging \
  --dart-define=API_BASE_URL="http://$NOW_PUBLIC_IP/api/v1" \
  --dart-define=WS_BASE_URL="http://$NOW_PUBLIC_IP" \
  --dart-define=MAP_STYLE_URL="http://$NOW_PUBLIC_IP/api/v1/maps/style.json" \
  --dart-define=FIRST_PARTY_DOMAINS="$NOW_PUBLIC_IP" \
  --dart-define=PILOT_REGION='Monaco pilot'
unset NOW_PUBLIC_IP
```

Не распространяй эту debug-сборку как release. Android release manifest запрещает cleartext, а iOS ATS не поддерживает этот public HTTP contour. Для них сначала разверни HTTPS.
