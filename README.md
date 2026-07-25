# Сейчас

«Сейчас» — privacy-first мессенджер и приложение для координации встреч внутри взаимного круга друзей. Постоянные личные и закрытые групповые чаты отделены от временных комнат. Публичных групп, поиска незнакомцев и фонового отслеживания местоположения нет.

## Репозиторий

- `apps/mobile` — Flutter-клиент Android/iOS.
- `apps/admin` — закрытая Next.js-панель модерации.
- `services/api` — NestJS REST/Socket.IO API.
- `services/worker` — TTL и фоновые задания.
- `packages` — контракты, типы и дизайн-токены.
- `infra` — Compose, Nginx, PostgreSQL/PostGIS и self-hosted maps.
- `scripts` — map, security, backup и staging automation.
- `docs` — архитектура, приватность и runbooks.

## Local development

Требования: Node.js 24+, npm 11+, Flutter 3.44+ и Docker Compose v2.

```bash
npm ci
npm run db:generate
docker compose up -d postgres redis minio
docker compose run --rm migrate
docker compose up --build api worker admin nginx
```

Local endpoints: API `http://localhost:8080/api/v1`, Swagger `http://localhost:8080/docs`, admin `http://localhost:8080/admin`, health `http://localhost:8080/health`.

`.env.example` намеренно не содержит значений credentials, cryptographic keys, test phones или кодов входа. Для запуска Node-процессов вне Compose скопируй файл в `.env`, заполни пустые поля локально и не добавляй `.env` в Git.

### Mobile development

Android Emulator:

```bash
cd apps/mobile
flutter pub get
flutter run \
  --dart-define=APP_ENV=development \
  --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1 \
  --dart-define=WS_BASE_URL=http://10.0.2.2:3000
```

Автономный UI без backend:

```bash
flutter run \
  --dart-define=APP_ENV=development \
  --dart-define=DEMO_MODE=true
```

Demo Mode хранит тестовые чаты и outbox только локально. Production-конфигурация запрещает `DEMO_MODE`.

Поведение разрешений и privacy contract описаны в [mobile GPS](docs/mobile-gps.md) и [location privacy](docs/location-privacy.md).

## Bare-IP staging

Standalone staging описан в `docker-compose.staging.yml`: с хоста опубликован только TCP `80`; PostgreSQL, Redis, Martin, Nominatim, API и worker остаются во внутренних Docker-сетях. Это временный HTTP-контур без TLS. В нём exact location отключён на сервере и в mobile UI, media pipeline отключён, а Android подключается только debug-сборкой. Для iOS и release-сборок требуется HTTPS.

Посмотреть интерфейс безопасных команд:

```bash
sh scripts/deploy/create-staging-env.sh --help
sh scripts/deploy/prepare-staging-maps.sh --help
sh scripts/deploy/deploy-staging.sh --help
```

Полный порядок: [server deployment](docs/server-deployment.md), [staging boundaries](docs/staging-environment.md), [troubleshooting](docs/troubleshooting.md).

## Monaco map pilot

Пилот использует небольшой extract Монако. Download сверяет опубликованный Geofabrik MD5 до и после передачи, записывает локальный SHA-256, Tilemaker закреплён по версии, а style/sprite/glyph/tile URLs находятся на first-party endpoints.

Linux:

```bash
sh scripts/maps/download-region.sh
sh scripts/maps/build-tiles.sh
sh scripts/maps/validate-map.sh --mbtiles infra/maps/data/seychas-v1.mbtiles
```

PowerShell:

```powershell
./scripts/maps/download-region.ps1
./scripts/maps/build-tiles.ps1
./scripts/maps/validate-map.ps1 --mbtiles infra/maps/data/seychas-v1.mbtiles
```

См. [map infrastructure](docs/map-infrastructure.md).

## Проверки

```bash
npm run verify
docker compose --profile test run --rm api-integration-tests
```

Map-only checks:

```bash
sh scripts/maps/validate-map.sh
sh scripts/maps/check-map-security.sh
```

## Production boundary

Bare-IP staging не является production. Production требует TLS, domain allowlist, secret manager/KMS, реальных SMS/Push и media providers, admin SSO/MFA, юридически утверждённых политик, store signing и отдельного sizing/backup drill. Начни с [deployment](docs/deployment.md), [security model](docs/security-model.md) и [legal open questions](docs/legal-open-questions.md).
