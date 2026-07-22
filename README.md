# Сейчас

«Сейчас» — privacy-first мессенджер и приложение для координации встреч внутри взаимного круга друзей. Постоянные личные и закрытые групповые чаты отделены от временных комнат встреч. В продукте нет публичных групп, поиска незнакомцев и фонового отслеживания: сигнал живёт ограниченное время, а точная геопозиция доступна только подтверждённым участникам временной комнаты и удаляется по TTL.

## Состав репозитория

- `apps/mobile` — Flutter-клиент для Android и iOS.
- `apps/admin` — закрытая Next.js-панель модерации.
- `services/api` — NestJS REST/WebSocket API.
- `services/worker` — TTL, уведомления, удаление данных и фоновые задания.
- `packages` — контракты, типы и дизайн-токены.
- `infra` — Docker, reverse proxy, monitoring и self-hosted map stack.
- `scripts` — development, maps и security automation.
- `docs` — архитектура, безопасность, приватность и эксплуатация.

## Быстрый запуск

Требования: Node.js 24 LTS+, npm 11+, Flutter 3.44+, Docker Engine 27+ с Compose v2.

```bash
cp .env.example .env
npm ci
npm run db:generate
docker compose up -d postgres redis minio
docker compose run --rm migrate
docker compose run --rm migrate npm run db:seed --workspace=@seychas/api
docker compose up --build api worker admin nginx
```

API: `http://localhost:8080/api/v1`; Swagger: `http://localhost:8080/docs`; admin: `http://localhost:8080/admin`; health: `http://localhost:8080/health`.

Development OTP — значение `DEV_OTP_CODE` из локального `.env`. Оно журналируется только при `NODE_ENV=development` и `ALLOW_DEV_OTP=true`. Эти переменные запрещены production-конфигурацией.

### Mobile

```bash
cd apps/mobile
flutter pub get
flutter run --dart-define=APP_ENV=development --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1 --dart-define=WS_BASE_URL=http://10.0.2.2:3000
```

Автономная демонстрация на телефоне без backend, Docker и WSL:

```bash
flutter run --dart-define=APP_ENV=development --dart-define=DEMO_MODE=true
```

В этом режиме OTP `123456`, а список чатов, история сообщений, черновики и очередь отправки сохраняются локально и переживают перезапуск приложения. Выбранный Demo Mode также сохраняется на устройстве. Production-конфигурация отклоняет `DEMO_MODE` при запуске.

Для проверки с реальным API на физическом Android используй LAN-адрес компьютера с Windows (телефон и компьютер должны быть в одной доверенной Wi-Fi-сети). `10.0.2.2` работает только в Android Emulator:

```powershell
flutter run --dart-define=APP_ENV=development --dart-define=API_BASE_URL=http://192.168.1.10:3000/api/v1 --dart-define=WS_BASE_URL=http://192.168.1.10:3000
```

Замени `192.168.1.10` на IPv4-адрес компьютера. Не публикуй development API в интернет; для внешней сети нужен HTTPS reverse proxy и production-настройки безопасности.

Android release:

```bash
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://api.example.invalid/api/v1 --dart-define=WS_BASE_URL=https://api.example.invalid
```

iOS release (только macOS с Xcode):

```bash
flutter build ipa --release --obfuscate --split-debug-info=build/symbols --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://api.example.invalid/api/v1 --dart-define=WS_BASE_URL=https://api.example.invalid
```

### Карты

Пилотный регион по умолчанию — Монако (малый reproducible extract, не production dataset):

```bash
npm run maps:download --if-present
powershell -File scripts/maps/build-tiles.ps1
powershell -File scripts/maps/start-map-stack.ps1
node scripts/maps/validate-map-style.mjs
```

Подробности и Linux-команды находятся в [docs/map-infrastructure.md](docs/map-infrastructure.md).

## Проверки

```bash
npm run verify
docker compose --profile test run --rm api-integration-tests
```

Docker-интеграционные тесты используют настоящий PostgreSQL/PostGIS. Mobile golden-файлы создаются и проверяются Flutter-командами из `apps/mobile`.

## Production

`.env.example` содержит только локальные заглушки. Production требует secret manager, реальный SMS/Push provider, собственные домены и TLS, юридически утверждённые документы, загруженный OSM extract выбранного региона и ключи подписи магазинов. См. [docs/deployment.md](docs/deployment.md) и [docs/legal-open-questions.md](docs/legal-open-questions.md).
