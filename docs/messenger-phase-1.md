# Отчёт по фазе 1 мессенджера «Сейчас»

Дата проверки: 22 июля 2026 года.

## 1. Что реализовано

- Постоянные личные и групповые чаты отделены от `TemporaryRoom` и `RoomMessage`.
- Личный чат создаётся только между взаимными друзьями и уникален для пары пользователей.
- Для групп реализованы роли `OWNER`, `ADMIN`, `MEMBER`, управление составом, выход и атомарная передача владения.
- Реализованы текстовые и `SIGNAL`-сообщения, постоянная история, cursor pagination, идемпотентность по `clientMessageId`, доставка, прочтение, typing с TTL в Redis, черновики, реакции, редактирование, удаление, закрепление, mute и поиск.
- Membership- и block-проверки применяются к HTTP и WebSocket; отозванная сессия перестаёт работать и в HTTP, и в realtime.
- Direct после удаления дружбы остаётся доступным только как read-only архив; block скрывает его полностью, а unblock без новой дружбы не восстанавливает отправку.
- Flutter получил единый `RealtimeCoordinator`, offline queue для текста и read receipts, повторную подписку, дедупликацию и восстановление после смены lifecycle/сети.
- Realtime обрабатывает `auth.error`: один раз обновляет сессию, подключается со свежим access token и не создаёт socket после logout.
- Добавлены `ChatsScreen`, `ChatScreen`, нижняя навигация с сохранением состояния вкладок и создание сигнала из чата.
- Demo Mode с OTP `123456` работает без backend и сохраняет выбор режима, чаты, историю, черновики и очередь после перезапуска.
- Существующие сигналы, временные комнаты и их сообщения не удалены и не объединены с постоянными чатами.
- Добавлены `MessageEncryptionProvider` и честная реализация `SERVER_MANAGED` v1. E2EE не заявляется.

## 2. Созданные файлы

- `docs/messenger-development-audit.md`, `docs/messenger-threat-model.md`, `docs/adr/messenger-encryption-strategy.md`.
- `services/api/src/features/conversations/*` и миграция `202607220001_persistent_conversations`.
- `services/api/src/common/message-encryption.provider.ts` и новые backend/unit/E2E-тесты.
- `apps/mobile/lib/features/chats/*`, `features/navigation/presentation/app_shell.dart`, `features/stories/presentation/stories_screen.dart`, `core/storage/app_mode_store.dart`.
- Flutter-тесты постоянного Demo Mode, messenger cache, cursor pagination, моделей, realtime/auth recovery и `ChatScreen`.
- `.dockerignore` и тесты пакета `@seychas/api-contracts`.

Сгенерированные Prisma Client-файлы обновлены вместе со схемой и входят в изменение.

## 3. Изменённые файлы

- Backend: Prisma schema/seed, `app.module.ts`, HTTP auth guard, common/auth/users/moderation/realtime-модули, Dockerfile и Nest compiler config.
- Flutter: app/router, конфигурация, API и realtime clients, Drift cache, token/auth flow, onboarding, экраны «Сейчас» и комнаты, composer сигнала и `main.dart`.
- Общие контракты: `packages/api-contracts` и lockfile.
- Эксплуатация: CI workflow, `docker-compose.yml`, README, MVP и data-retention документация.
- Dependency overrides фиксируют безопасные `postcss@8.5.10` и `sharp@0.35.3`; `npm audit` после обновления сообщает 0 уязвимостей.

## 4. Миграции

Добавлена миграция `services/api/prisma/migrations/202607220001_persistent_conversations/migration.sql`. Она создаёт:

- `Conversation`, `ConversationMember`, `ConversationInvite`;
- `Message`, `MessageEdit`, `MessageAttachment`, `MessageReaction`;
- `MessageReadReceipt`, `MessageDelivery`, `PinnedMessage`;
- `ConversationDraft`, `ChatMute`, `ChatAuditEvent`;
- enum-типы, FK, check constraints и индексы для пары direct-чата, пагинации, непрочитанного состояния и идемпотентности;
- связь жалобы с конкретным сообщением чата.

Prisma schema проходит `validate` и `generate`. Локально миграция не применялась: PostgreSQL на `127.0.0.1:5432` и Docker daemon недоступны. В [GitHub Actions run 29953296793](https://github.com/micrickpc-lang/Now/actions/runs/29953296793) обе миграции успешно применены с нуля к PostgreSQL 17 + PostGIS 3.5; после этого выполнены реальные integration-тесты. Миграционный Docker target и команда Compose валидированы локально, а используемая ими команда Prisma подтверждена в CI.

## 5. Добавленные API

- `GET /conversations`
- `POST /conversations/direct`
- `POST /conversations/group`
- `GET`, `PATCH`, `DELETE /conversations/:id`
- `POST /conversations/:id/members`
- `DELETE /conversations/:id/members/:userId`
- `POST /conversations/:id/leave`
- `POST /conversations/:id/ownership`
- `POST`, `DELETE /conversations/:id/mute`
- `GET`, `POST /conversations/:id/messages`
- `PATCH`, `DELETE /messages/:id`
- `POST`, `DELETE /messages/:id/reactions[/:reaction]`
- `POST /messages/:id/read`
- `POST`, `DELETE /messages/:id/pin`
- `GET /conversations/:id/search`
- `POST /conversations/:id/typing`
- `POST`, `GET /conversations/:id/drafts`

В DTO и OpenAPI зафиксированы wire-типы. Ответ для отправителя содержит viewer-aware `deliveryStatus`; чужой участник этот внутренний статус не получает.

## 6. Добавленные тесты

- Backend unit: block/direct policy, idempotency, SIGNAL replay, delivery/read semantics, ownership, безопасное удаление аккаунта, typing TTL, session-aware guard, WebSocket membership/session, encryption envelope.
- Backend integration: уникальность direct-чата, повтор `clientMessageId`, IDOR чтения/отправки, роли группы, read receipts, блокировка, remove-friend и block→unblock.
- Contracts: enum-значения и уникальность realtime event names.
- Flutter: постоянный выбор Demo Mode, модели и статусы доставки, Drift messenger cache/outbox, сохранение direct/group истории и черновика, безопасная многостраничная загрузка чатов, realtime sequence/deduplication/auth recovery/logout race, `ChatScreen` и карточка сигнала.

## 7. Результаты тестов

- `npm run verify` — успешно.
- API Jest — 10 suites, 47/47 тестов успешно.
- API integration с PostgreSQL 17 + PostGIS 3.5 — 2 suites, 9/9 тестов успешно.
- API contracts — 2/2 теста успешно.
- Flutter — 21/21 тестов успешно.
- `flutter analyze` — ошибок нет.
- `npm audit --audit-level=high` — 0 уязвимостей.
- `security:maps`, `security:secrets`, `docker compose config --quiet` — успешно.

Локальный PostgreSQL отсутствует, поэтому integration-набор выполнен в изолированном CI с реальными PostgreSQL, PostGIS и Redis. Итоговый [CI run 29953296793](https://github.com/micrickpc-lang/Now/actions/runs/29953296793) полностью зелёный: `node`, `flutter`, `containers` и `security` завершились успешно.

## 8. Результаты сборки

- Next.js admin production build — успешно.
- NestJS API, worker и все TypeScript packages — успешно.
- Android debug APK с автономным Demo Mode — успешно: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`, 222 409 038 байт, SHA-256 `2C2914BE9F7C37794711A13850B5D94E42A2BF7FC8DA129710999A2C97512550`.
- Docker Compose конфигурация валидна. API image собран, загружен в runner и успешно прошёл Trivy HIGH/CRITICAL scan в CI; локальная сборка не выполнялась только из-за выключенного Docker daemon.
- Android debug AAB также успешно собран в CI с `APP_ENV=development`.

Flutter вывел предупреждение о будущем переходе `maplibre_gl` на Built-in Kotlin; текущую сборку оно не ломает.

## 9. Найденные и исправленные проблемы

- Исправлены все четыре предыдущих CI-причины: production env для Next build, Java 21 для Flutter, runtime dependency layout API image и миграционный Compose target.
- Устранён каскад удаления групп владельцем: теперь владение передаётся активному участнику, а FK использует `RESTRICT`.
- Устранено ложное состояние `READ` от собственного receipt и добавлено отдельное `DELIVERED`.
- Исправлено принятие низкого realtime sequence после перезапуска API.
- Закрыта pre-auth WebSocket race: до завершения server-side session check все handlers работают fail-closed и не обращаются к Prisma с неопределённым user ID.
- Удалён sender-only `deliveryStatus` из общего realtime payload; исключённый участник принудительно удаляется из conversation room на всех устройствах.
- Исправлена потеря кэша, черновиков и outbox у чатов за пределами первой cursor-страницы.
- Добавлены refresh/reconnect после `auth.error`, controlled backoff и защита от reconnect после logout.
- Исправлена небезопасная работа с Riverpod `ref` при размонтировании `ChatScreen`; ошибку обнаружил новый widget-тест.
- Закрыта high severity dependency-цепочка Next/Sharp без downgrade Next.js.
- Исправлено зависание integration runner при shutdown: ленивый ioredis-клиент больше не запускает reconnect через `quit()` до первого подключения; lifecycle покрыт регрессионными тестами.
- Исправлена обработка IP за reverse proxy: `TRUST_PROXY_HOPS` валидируется и задаётся явно, поэтому OTP/throttling/session audit не объединяют всех клиентов Nginx в один IP и при этом не доверяют произвольному `X-Forwarded-For`.
- Устранены две ошибки E2E-стенда: тестовые пользователи больше не делят один OTP abuse budget, а параллельные Supertest-запросы используют один явно запущенный HTTP server без `ECONNRESET`.
- GitHub Actions обновлены до Node 24-compatible major-релизов; предупреждения runner о deprecated Node 20 runtime устранены.

## 10. Что осталось

- Для direct-чата нужен отдельный per-user hide; общий `DELETE` сейчас намеренно отклоняется, чтобы не удалить переписку второго участника.
- `SELF` delete пока хранится как общий tombstone автора, а не отдельная видимость для каждого участника.
- Multi-instance realtime требует Redis Socket.IO adapter и глобальный sequence source.
- Полный UI фазы 2 для reply/edit/delete/reactions/pin/search ещё не завершён, хотя backend-контракты уже существуют.
- Медиа pipeline, голосовые, production push/SMS, WebRTC/coturn, нативные call services, истории и SFU относятся к следующим фазам.
- Нужен smoke-тест debug APK на физическом Android: установка, перезапуск persistent Demo, отправка/retry и выход из Demo к обычному входу.
- Message burst-limit сейчас сочетает global throttler и DB count; для строгой multi-instance атомарности его нужно перенести в Redis. Дополнительное Demo-состояние сигналов пока memory-only.

## 11. Текущая готовность

- Фаза 1 по коду и автоматизированным критериям: **около 95%**. Личный и групповой чат, история, realtime, receipts, offline queue, persistent Demo, block policy, сигнал в чате, отдельные временные комнаты, миграции, Android debug build и `npm run verify` подтверждены зелёным CI. До 100% первой фазы не хватает smoke-теста на физическом Android и закрытия перечисленных выше продуктовых краёв.
- Полный мессенджер из целевого плана: **около 35%**. Нельзя считать продукт готовым без production SMS/push, media security/storage, coturn, звонков на физических Android/iOS, CallKit/Android call service, production map region и monitoring.

## 12. Следующая фаза

Сначала выполнить короткий smoke-тест готового APK на физическом Android, затем завершить фазу 2: per-user delete semantics, reply/edit/delete/reactions/pin/search в Flutter, расширенные offline операции и дополнительные IDOR/limitedMode тесты. К медиа и звонкам переходить только после этого.
