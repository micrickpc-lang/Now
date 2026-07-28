# Аудит состояния перед этапом server/maps/GPS

Дата аудита: 22 июля 2026 года. Исходная ветка: `main`, исходный commit: `77c8bd57e571baca059a6a0bb73dee15a88493f9`. Рабочая ветка этапа: `feat/server-maps-gps`.

## 1. Проверенная структура

Репозиторий является действующим монорепозиторием, а не пустым прототипом:

- `apps/mobile` — Flutter 3.44, Riverpod, GoRouter, Dio, Drift, Socket.IO и MapLibre;
- `services/api` — NestJS 11, Prisma 7, PostgreSQL/PostGIS, Redis, Swagger и WebSocket;
- `services/worker` — BullMQ-задачи TTL и физического удаления временных данных;
- `apps/admin` — Next.js-панель;
- `infra` — Nginx, Martin, Nominatim, PostGIS и monitoring-заготовки;
- `scripts` — map/security automation;
- `.github/workflows/ci.yml` — Node, Flutter, container и security jobs.

## 2. Что работало до изменений этого этапа

- Авторизация, refresh rotation, пользователи, дружба, сигналы, комнаты, постоянные чаты и realtime.
- Глобальная DTO-валидация, bearer guard, базовый rate limit, Swagger и production environment validation.
- `/health`, `/ready`, `/api/v1/users/me` и основные auth endpoint.
- PostGIS включается первой миграцией. `signals.approximate_point` имеет тип `geography(Point, 4326)` и GiST-индекс.
- Exact location временной комнаты требует `explicitConsent`, шифруется envelope AES-256-GCM, ограничена TTL комнаты и выдаётся только активным участникам после block/membership-проверки.
- Revoke, выход владельца, завершение комнаты и worker TTL физически удаляют exact share; чтение и изменение аудируются без координат.
- MapLibre уже подключён к экрану `/map`; style, search и tiles направлены на first-party backend gateway. Видимая атрибуция OSM присутствует.
- В исходной конфигурации нет Google Maps, Yandex Maps, Mapbox API, публичного Nominatim, публичного OSRM или `tile.openstreetmap.org`.
- Базовая проверка `npm run verify` прошла: 47 API unit-тестов, 2 contract-теста и 21 Flutter-тест; lint, typecheck, builds и security scanners успешны. Интеграционные тесты на реальном PostGIS ранее прошли в CI.

## 3. Что было реализовано частично

- Map API содержит style, tile proxy, search, reverse и stateless approximate endpoint, но отсутствует TileJSON.
- В `infra/maps/data` нет реального PBF и MBTiles; присутствует только маленький демонстрационный GeoJSON. Martin до сборки данных не может отдать реальный tile.
- Runtime style генерируется API, а validator проверяет отдельный JSON-файл. Sprites/glyphs и полноценные labels отсутствуют.
- Download script ограничивает размер файла, но не проверяет опубликованный checksum. Tilemaker использует mutable tag и не имеет воспроизводимого Linux pipeline.
- `POST /maps/approximate-location` только округляет и возвращает точку, но не сохраняет безопасный результат.
- Signal сохраняет округлённую PostGIS-точку отдельным raw UPDATE после INSERT. Операции не атомарны; radius/precision не сохраняются и безопасная зона не возвращается клиенту.
- `CITY` и `DISTRICT` существуют в модели и UI, но мобильный клиент не определяет их через backend.
- `/ready` проверяет только PostgreSQL, не проверяет Redis, Martin или Nominatim.
- Production Compose является неполным overlay: в нём нет самостоятельных PostGIS, Redis, migrate, reverse proxy, Martin и Nominatim.
- Exact share доступен из UI комнаты, но обычный join-flow не проводит пользователя в комнату, а карта не показывает полученные участником точки.

## 4. Моки и захардкоженные данные

- Demo-карта является градиентом и возвращает фиксированную демонстрационную точку.
- Центр реальной карты захардкожен под демонстрационный регион Монако.
- Demo search возвращает фиксированный результат.
- Главный экран «Сейчас» использует визуальную «вселенную», а не географическую карту; это существующий продуктовый экран и он не удаляется.
- Development Demo OTP и локальные demo-данные намеренно существуют только вне production.
- Routing provider намеренно отключён для MVP.

## 5. Что отсутствовало

- `LocationProvider`, типы permission/location, системный foreground GPS, runtime permission flow и accuracy circle.
- Обработка approximate/precise, denied, permanently denied, disabled service, timeout и переход в системные настройки.
- Остановка location stream при revoke/logout/lifecycle; stream фактически отсутствовал.
- `MAP_STYLE_URL` и конфигурируемые pilot center/bounds.
- Reverse geocoding после выбора точки и безопасный вызов approximate-location перед публикацией.
- `GET /api/v1/maps/tilejson.json` и отдельный `GET /api/v1/rooms/:id/location-share`.
- Request ID, единый error envelope и глубокая редактура чувствительных полей логов.
- Redis cache для geocoding, upstream timeouts и отдельные лимиты search/reverse.
- Реальные versioned tiles, sprites, glyphs, cache proxy и tile smoke test.
- Полноценный standalone staging deployment, deploy/rollback/migrate/health/backup/restore scripts.
- GPS/map unit и integration coverage из критериев текущего этапа.

## 6. Критические проблемы

1. `GET /maps/reverse?lat=...&lon=...` и `/maps/search?q=...` могут попадать вместе с query string в стандартный Nginx access log. Это нарушает запрет логирования координат и полного адреса.
2. Реальный PBF/MBTiles отсутствует, поэтому утверждать, что карта работает, до tile smoke нельзя.
3. Development Compose публикует БД, Redis, MinIO и API на host; его нельзя запускать на публичном сервере как staging/production.
4. Bare IP допускает только явно небезопасный HTTP staging без реальных аккаунтов и exact location. Для production необходим домен и HTTPS.
5. MapLibre загружает style/tiles нативно без bearer-заголовков; публичные read-only map assets должны быть доступны безопасно и отдельно от пользовательских endpoint.
6. Mobile сохраняет координату тапа, но рисует маркер в центре экрана, из-за чего отображение может не соответствовать отправляемой точке.
7. Current signal flow отправляет исходную координату прямо в `/signals` и использует простое округление, которое недостаточно как единственная privacy policy.
8. В account deletion обнаружен слишком широкий delete exact shares других владельцев через общие комнаты.

## 7. Состояние мобильных разрешений

- Source Android manifest явно содержит только `INTERNET`, но MapLibre SDK добавляет `ACCESS_COARSE_LOCATION` и `ACCESS_FINE_LOCATION` в merged manifest.
- `ACCESS_BACKGROUND_LOCATION` отсутствует и добавляться не должен.
- iOS `NSLocationWhenInUseUsageDescription` отсутствует; `Always` также отсутствует.
- GPS автоматически при запуске не запрашивается, но и после явного действия пока не работает.

## 8. Состояние предоставленного сервера

- Ubuntu 24.04.4 LTS, x86-64, 2 vCPU, 1.9 GiB RAM, без swap, ext4-диск 58 GiB (около 53 GiB свободно).
- Docker 29.6.1 и Docker Compose 5.3.1 установлены.
- SSH доступ подтверждён. До изменения SSH-политики должен быть создан и отдельно проверен deploy user с ключом.
- Уже работает сторонний контейнер `remnanode`, использующий host network и публичные порты `443` и `2222`. Он, `/opt/remnanode` и его данные не относятся к «Сейчас» и не должны изменяться.
- Порт `80` свободен. PostgreSQL, Redis и Nominatim наружу не открыты.
- UFW неактивен. Firewall можно включать только после проверки SSH allow rule и отдельной сессии по ключу.
- Ресурсы ограничены: существующий контейнер использует примерно 580 MiB RAM. Для небольшого пилотного региона требуется компактный staging stack, resource limits и swap; тяжёлый production Nominatim/tiles build на этом хосте не гарантирован.

## 9. Изменения текущего этапа

1. Закрыть утечки логов, добавить request ID/error envelope, readiness зависимостей, timeouts, cache и DTO/rate limits.
2. Сделать атомарную и тестируемую privacy policy для `CITY`, `DISTRICT`, `APPROXIMATE`, безопасное PostGIS-хранение и отдельный exact-share read endpoint.
3. Добавить воспроизводимый Monaco pilot pipeline с checksum, versioned MBTiles/style/assets, Martin, private Nominatim и реальным tile smoke.
4. Добавить foreground-only `LocationProvider`, реальные системные разрешения, GPS/accuracy UI, privacy modes и остановку stream.
5. Создать изолированный staging Compose и deploy scripts без публикации внутренних сервисов.
6. Развернуть на сервере в `/opt/now`, не затрагивая существующий `remnanode`; на bare IP публиковать только HTTP staging без exact location.
7. Добавить требуемые backend/Flutter/security тесты, документацию, backup/restore и restart smoke.

Этот аудит описывает состояние **до** реализации этапа и не является заявлением о готовности карты или GPS.
