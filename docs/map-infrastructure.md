# Self-hosted maps: Monaco pilot

Mobile получает карты только с first-party endpoints. Nginx отдаёт canonical MapLibre style/sprites/glyphs и проксирует vector tiles через API; API обращается к Martin и Nominatim по private Docker DNS. У mobile/API нет runtime-запросов к внешним map providers.

```text
MapLibre ── /api/v1/maps/style.json ──> Nginx alias ──> assets/v1/style.json
         ├─ /maps/v1/tiles/... ───────> Nginx cache ─> API ─> Martin ─> MBTiles
         ├─ /maps/v1/sprites/... ─────> Nginx alias
         └─ /maps/v1/glyphs/... ──────> Nginx alias
Mobile ──── /api/v1/maps/search|reverse ─> API ─> Nominatim
```

Nominatim и Martin не публикуют host ports. Routing в V1 отключён.

## Artifacts

- `infra/maps/region.json` — Monaco download/checksum policy и output paths.
- `infra/maps/data/region.osm.pbf` — downloaded extract, игнорируется Git.
- `infra/maps/data/region.osm.pbf.metadata.json` — фактические MD5/SHA-256, size и source metadata.
- `infra/maps/data/seychas-v1.mbtiles` — versioned Martin input, игнорируется Git.
- `infra/maps/tilemaker/image.txt` — официальный Tilemaker, закреплённый по immutable OCI digest.
- `infra/maps/tilemaker/config.json` и `process.lua` — детерминированные слои `water`, `landuse`, `transportation`.
- `infra/maps/assets/v1` — canonical style, 1x/2x empty sprite и minimal glyph envelope.
- `infra/maps/martin.yaml` — internal source `seychas -> /data/seychas-v1.mbtiles`.

V1 style намеренно не имеет `symbol` layers: текущий glyph asset — валидная минимальная оболочка, но не полный font set. Добавление подписей или icons требует versioned real glyph/sprite generation и нового style version.

## Checksum model

Geofabrik для Monaco публикует MD5 manifest. Downloader:

1. получает manifest только по HTTPS и выбирает точное имя PBF;
2. загружает PBF с size limit;
3. вычисляет MD5 и SHA-256 в потоке;
4. повторно получает manifest, исключая смену `latest` во время download;
5. публикует PBF только после совпадения MD5;
6. сохраняет SHA-256 в metadata sidecar.

`pinnedSha256` в `region.json` может быть заполнен release owner после отдельной проверки конкретного extract. Пока он `null`, build checksum-verified, но URL `latest` не является долгосрочно воспроизводимым release input. Не вписывай выдуманный digest.

## Local build

Linux/macOS shell (Node.js 24+ используется, а при его отсутствии скрипт запускает закреплённый Node container через Docker):

```bash
sh scripts/maps/download-region.sh
sh scripts/maps/build-tiles.sh
sh scripts/maps/validate-map.sh --mbtiles infra/maps/data/seychas-v1.mbtiles
sh scripts/maps/check-map-security.sh
```

PowerShell требует Node.js 24+ и Docker:

```powershell
./scripts/maps/download-region.ps1
./scripts/maps/build-tiles.ps1
./scripts/maps/validate-map.ps1 --mbtiles infra/maps/data/seychas-v1.mbtiles
./scripts/maps/check-map-security.ps1
```

Повторная загрузка и перезапись versioned MBTiles требуют явного `--force`. Build запускает Tilemaker с `--network none`, проверяет local PBF sidecar, генерирует assets и проверяет SQLite header до atomic rename.

## First server import

На новом staging host с уже созданным private env:

```bash
cd /opt/now/app
sh scripts/deploy/prepare-staging-maps.sh \
  --env-file /opt/now/app/.env.staging \
  --data-root /opt/now/data
```

Profile `maps-import` ограничен 768 MiB и должен выполняться без runtime stack. Upstream PostgreSQL defaults уменьшены до профиля пилотного VPS (в частности, `shared_buffers=128MB` и один import thread). Скрипт ждёт `/status.php?format=json`, затем останавливает/removes import container и требует `/opt/now/data/nominatim/PG_VERSION` вместе с `/opt/now/data/nominatim/import-finished`. Runtime Nominatim имеет меньший memory limit и не предназначен для initial import.

Наличие `import-finished` делает операцию idempotent: artifacts обновляются, но Nominatim не импортируется заново. Один `PG_VERSION` не принимается за успех, потому что он появляется до загрузки OSM. `--force-import` не удаляет существующую БД и намеренно отказывает для in-place destructive import.

## Runtime routes

| Public path                          | Поведение                                             |
| ------------------------------------ | ----------------------------------------------------- |
| `/api/v1/maps/style.json`            | stable mobile URL; canonical v1 style, короткий cache |
| `/api/v1/maps/tilejson.json`         | API TileJSON с `/api/v1/maps/tiles/...`               |
| `/api/v1/maps/tiles/{z}/{x}/{y}.pbf` | public API tile proxy/cache                           |
| `/maps/v1/style.json`                | immutable canonical style                             |
| `/maps/v1/tiles/{z}/{x}/{y}.pbf`     | versioned alias/rewrite к API tile                    |
| `/maps/v1/sprites/...`               | immutable 1x/2x sprite assets                         |
| `/maps/v1/glyphs/...`                | immutable glyph assets                                |
| `/api/v1/maps/search`                | authenticated, rate-limited Nominatim search          |
| `/api/v1/maps/reverse`               | authenticated, rate-limited reverse lookup            |

Attribution `© OpenStreetMap contributors` находится в source и style metadata; mobile оставляет MapLibre attribution control видимым.

## Validation и smoke

Static graph validator проверяет mobile URL, API controller routes, Nginx aliases/rewrite/cache, Compose DNS/base URLs, Martin source, Nominatim routes, Tilemaker layers, asset manifest и checksum policy:

```bash
sh scripts/maps/validate-map.sh
```

После deploy:

```bash
sh scripts/maps/smoke-map.sh --base-url http://127.0.0.1
```

PowerShell:

```powershell
./scripts/maps/smoke-map.ps1 --base-url http://127.0.0.1
```

Smoke фиксирует status/content-type/bytes для health, обоих styles, TileJSON, API/versioned tile, 1x/2x sprites и glyph. Неаутентифицированные search/reverse должны вернуть `401`. Успешный transport smoke не доказывает визуальное отображение: отдельно открой picker на Android, дождись `onStyleLoaded`, проверь pilot bounds и видимую attribution.

## Обновление данных

`scripts/maps/update-map-data.sh`/`.ps1` — staging convenience: повторно загружает Monaco, перестраивает `v1`, atomically публикует files и перезапускает только Martin. Он не re-import Nominatim и не очищает persistent Nginx/client caches. Поэтому не используй его как production zero-downtime pipeline и не считай search dataset обновлённым.

Для release обновления создай новый dataset/style version, новый MBTiles filename и новые URLs; прогрей cache, переключи style и сохрани предыдущую версию на mobile cache window. Nominatim обновляй через отдельную verified import/replication процедуру, а не in-place удаление.
