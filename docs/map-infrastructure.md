# Self-hosted карты

MapLibre получает style, vector tiles, sprites, glyphs и search только с first-party endpoints. Backend proxy обращается к Nominatim по private Docker DNS. Martin читает versioned MBTiles. В production внешний OSM extract разрешён только pipeline обновления, не runtime mobile/API traffic.

## Global Map And Local Demo

`/app/map` starts at a world camera and obtains markers only from the authenticated
`GET /map/friends` API. The map client never receives another user's exact
coordinates unless an active, explicit, recipient-scoped server grant permits it.
The production MBTiles deployment must cover every supported market; a world
camera alone does not make a regional extract global.

`infra/maps/region.json` ограничивает загрузку extract размером 10 MB и по умолчанию использует Монако. Это local demo input only and must not be deployed as the production global tile dataset. `infra/maps/data/demo.geojson` позволяет проверить style/attribution без большого PBF.

```powershell
npm run maps:download
./scripts/maps/build-tiles.ps1
./scripts/maps/start-map-stack.ps1
npm run maps:validate
```

Обновление: `./scripts/maps/update-map-data.ps1`. Для zero-downtime production pipeline строит новый versioned файл, валидирует tile metadata/style, публикует под новым URL, прогревает cache, переключает style version и оставляет предыдущую версию до истечения mobile cache. Локальный упрощённый скрипт перезапускает только Martin.

RoutingProvider присутствует, но отключён. V2 может подключить private OSRM; публичный routing endpoint запрещён. `npm run security:maps` проверяет source/network configuration на запрещённые SDK/domains. ODbL attribution: `© OpenStreetMap contributors` видима поверх карты и есть в style metadata.

Sprites/glyphs должны размещаться в `infra/maps/assets` под versioned именами. Production download, tile generation и database import выполняются отдельным CI runner без доступа к application secrets.
