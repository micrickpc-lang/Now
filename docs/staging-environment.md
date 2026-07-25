# Границы staging environment

`docker-compose.staging.yml` — самостоятельный pilot stack для одного Linux host и bare IPv4. Он предназначен для функциональной проверки backend, realtime, безопасных location modes и self-hosted maps; это не уменьшенная production-конфигурация.

## Network и ресурсы

С хоста публикуется только `0.0.0.0:80 -> nginx:8080`. Ни PostgreSQL/PostGIS, ни Redis, Martin, Nominatim, API или worker host ports не имеют. `private` network имеет `internal: true`; Nginx видит API через отдельную `edge` network.

| Service            | Runtime limit | Назначение                        |
| ------------------ | ------------: | --------------------------------- |
| PostgreSQL/PostGIS |       256 MiB | system of record и spatial types  |
| Redis              |        64 MiB | ephemeral cache/queue             |
| Martin             |        64 MiB | internal MBTiles source `seychas` |
| Nominatim runtime  |       256 MiB | private search/reverse            |
| API                |       256 MiB | REST/Socket.IO/map proxy          |
| Worker             |       128 MiB | TTL cleanup                       |
| Nginx              |        64 MiB | единственный public ingress       |

Default runtime total — 1088 MiB. Одноразовый `maps-import` profile ограничен 768 MiB и выполняется при остановленном runtime. Migration job ограничен 256 MiB и завершается до старта API/worker/Nginx.

## Feature matrix

| Возможность                                 | Staging                                 |
| ------------------------------------------- | --------------------------------------- |
| REST, Socket.IO, PostgreSQL, Redis          | включены                                |
| Monaco tiles, style, sprite/glyph endpoints | включены                                |
| Nominatim search/reverse                    | включены, только через API              |
| City/district/approximate location          | включены                                |
| Exact room location                         | выключен (`ALLOW_EXACT_LOCATION=false`) |
| Object storage, antivirus, media upload     | fail-closed/не развернуты               |
| Admin UI                                    | не развернут                            |
| TLS/HSTS                                    | отсутствуют                             |
| Production SMS/Push                         | не развернуты                           |

HTTP staging нельзя использовать с реальными пользователями или чувствительными данными. Он пригоден только в контролируемом pilot scope с disposable accounts. Exact location нельзя включать отдельным env override: backend validation и mobile transport policy требуют HTTPS.

## Configuration

`.env.example` содержит только имена и безопасные non-secret defaults. Private `.env.staging` создаётся:

```bash
sh scripts/deploy/create-staging-env.sh --help
```

Скрипту нужны bare IPv4 и allowlist тестовых E.164 numbers; значения вводятся оператором вне документации и shell history. Результат имеет mode `600`, не печатает generated values и игнорируется Git.

Основные invariants Compose:

- `APP_ENV=staging`, `NODE_ENV=production`;
- `APP_ORIGINS` и public API строятся из `PUBLIC_IP`;
- `TRUST_PROXY_HOPS=1` и ingress нельзя обходить;
- `MAP_PUBLIC_BASE_URL` указывает на `/api/v1/maps`;
- `SEARCH_COUNTRY_CODES=mc` по умолчанию;
- development authentication bypasses выключены, `ALLOW_EXACT_LOCATION=false`;
- persistent root — `/opt/now/data`.

Не запускай `docker compose config` без `--quiet` в shared logs: resolved output содержит environment values.

## Persistent data

| Path                            | Содержимое                                   |
| ------------------------------- | -------------------------------------------- |
| `/opt/now/data/postgres`        | application PostgreSQL/PostGIS               |
| `/opt/now/data/redis`           | AOF; не system of record                     |
| `/opt/now/data/maps`            | verified PBF metadata и `seychas-v1.mbtiles` |
| `/opt/now/data/nominatim`       | imported geocoder PostgreSQL                 |
| `/opt/now/data/nginx-map-cache` | disposable tile cache                        |
| `/opt/now/data/deployments`     | current/previous image metadata              |
| `/opt/now/backups`              | restricted PostgreSQL custom dumps/checksums |

`.env.staging` хранится отдельно от data backups. Потеря cryptographic keys может сделать application data невосстановимыми; включи этот файл в защищённый host-level secret backup, но не в обычный database dump.

## Public routes

- `/health` — process liveness.
- `/ready` — PostgreSQL, Redis, Martin catalog и Nominatim status.
- `/api/v1/maps/style.json` — stable mobile URL, отдающий canonical v1 style.
- `/api/v1/maps/tilejson.json` и `/api/v1/maps/tiles/...` — API map contract.
- `/maps/v1/style.json`, `/maps/v1/tiles/...`, `/maps/v1/sprites/...`, `/maps/v1/glyphs/...` — versioned first-party resources.
- `/api/v1/maps/search` и `/api/v1/maps/reverse` — authenticated API; прямой Nominatim public route отсутствует.
- `/socket.io/` — Socket.IO transport; namespace приложения — `/realtime`.

Nginx rate limits разделены для auth, API, maps, search и Socket.IO. Tile cache key не включает query. Access logging исключает client IP и query-bearing values.

## Lifecycle

```bash
sh scripts/deploy/prepare-staging-maps.sh --help
sh scripts/deploy/deploy-staging.sh --help
sh scripts/deploy/health-staging.sh /opt/now/app/.env.staging
sh scripts/deploy/backup-staging.sh /opt/now/app/.env.staging
sh scripts/deploy/rollback-staging.sh --help
```

Полная последовательность находится в [server-deployment.md](server-deployment.md), восстановление — в [backup-restore.md](backup-restore.md), диагностика — в [troubleshooting.md](troubleshooting.md).
