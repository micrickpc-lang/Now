# Аудит развития мессенджера «Сейчас»

Дата аудита: 22 июля 2026 года. Аудит выполнен по существующему монорепозиторию без замены стека и без изменения назначения сигналов и временных комнат.

## 1. Что уже работает

### API и данные

- Авторизация по OTP, development-код `123456`, ротация refresh-токенов, устройства, отзыв сессий и logout.
- Профиль пользователя, настройки приватности, limited mode и удаление аккаунта.
- Взаимная дружба по закрытому приглашению, закрытые круги и двусторонние блокировки.
- Временные сигналы, видимость по друзьям и кругам, Join/Approve, ограничение участников и создание комнаты встречи.
- Временные комнаты: участники, текстовые сообщения, реакции, опрос, временная точная геолокация и её немедленный отзыв.
- Воспоминания из завершённых встреч.
- Загрузка аватара через MinIO/S3, проверка размера, MIME и magic bytes, обработка Sharp, ClamAV и короткие signed URL.
- Жалобы, базовая очередь модерации, audit log, feature flags и self-hosted карты.
- JWT guard, DTO validation, глобальный rate limit, Helmet, CORS allowlist, Prisma/PostgreSQL/PostGIS, Redis и Socket.IO-инфраструктура.

### Flutter

- Onboarding, OTP, безопасное локальное хранение токенов и single-flight refresh.
- Экран сигналов, создание сигнала, Join, круги, карта, временная комната, location consent, воспоминания и настройки приватности.
- Fallback-кэш живых сигналов в SQLite.
- Demo OTP и локальный interceptor при явном включении development Demo Mode.

### Админка и эксплуатация

- Закрытая Next.js-панель с HttpOnly/SameSite cookie, очередью жалоб и обязательным обоснованием решения.
- Worker архивирует истёкшие сигналы/комнаты, физически удаляет просроченную точную геолокацию, OTP и сессии.
- Dev Compose поднимает PostGIS, Redis, MinIO, ClamAV, API, worker, admin и Nginx; CI проверяет Node, Flutter и security jobs.

## 2. Что отсутствует или является заглушкой

- Постоянных личных и групповых чатов, постоянной истории и `/conversations` пока нет.
- Нет доставки/прочтения сообщений, cursor pagination, idempotent `clientMessageId`, черновиков, закрепления, поиска и offline outbox для чатов.
- Typing state не реализован; Redis объявлен обязательным, но API пока его не использует.
- Realtime обслуживает сигналы и временные комнаты. Sequence process-local, нет replay/resume, Redis adapter и сохранения подписок.
- Flutter имеет плоский router без пяти постоянных вкладок. `HomeScreen` сам подключает и отключает общий WebSocket.
- Demo-данные interceptor находятся в памяти процесса и не переживают перезапуск. Таблица `outbox` создана, но не используется.
- На физическом Android адрес `10.0.2.2` недоступен: это адрес только эмулятора; требуется LAN HTTPS/HTTP development URL либо автономный Demo Mode.
- Production SMS и push не подключены. Worker содержит отключённый push provider.
- Звонки, истории, chat media, голосовые сообщения и production monitoring не реализованы.
- Пакеты `api-contracts`, `shared-types` и `design-tokens` пока не являются реально используемым source of truth.
- Admin/worker/package tests почти отсутствуют; текущий backend E2E покрывает только основной сценарий встречи.

## 3. TemporaryRoom и RoomMessage

`TemporaryRoom` — bounded context конкретной встречи, а не постоянного общения:

- имеет обязательный уникальный `signalId`;
- содержит owner, расписание, `expiresAt` и состояния `ACTIVE/COMPLETED/ARCHIVED`;
- создаётся после одобрения Join-запроса;
- доступна только активному `RoomMember` с `leftAt = null`;
- после завершения или истечения архивируется, а точная геолокация физически удаляется.

`RoomMessage` содержит `roomId`, nullable author, текст, system flag, время и soft-delete. У него нет `clientMessageId`, read/delivery receipt и устойчивой cursor pagination. Реакции и опросы принадлежат только комнате встречи.

Worker обращается к `temporary_rooms`, `room_messages` и `location_shares` по физическим snake_case-именам. Переименование или использование этих таблиц для постоянного чата сломает TTL/cleanup-инварианты и может привести к потере истории. Они остаются отдельными и обратно совместимыми.

## 4. Что переиспользуется

- `AccessTokenGuard`, `CurrentAuth`, `PrismaService`, `AuditService`, `ContentPolicyService` и глобальная validation/rate-limit инфраструктура.
- Каноническая пара пользователей и `SocialService.areFriends()` для уникального direct-чата.
- Двусторонняя проверка блокировки как общий messaging policy.
- `RealtimeGateway` как единый транспорт и envelope `{ id, sequence, occurredAt, payload }`, но с отдельными conversation channels.
- MinIO/ClamAV/Sharp pipeline после добавления membership-based media authorization.
- Secure token storage, refresh interceptor, Drift/SQLite и существующие UI-паттерны composer/consent.
- Сигналы и комнаты переиспользуются через ссылки и карточки сообщений, но не становятся сообщениями/чатами сами по себе.

## 5. Требуемые миграции

Начальная миграция не редактируется. Нужна additive migration со следующими сущностями:

- `Conversation` (`DIRECT`, `GROUP`) и уникальный канонический ключ пары для direct;
- `ConversationMember` с ролями `OWNER`, `ADMIN`, `MEMBER`;
- `ConversationInvite`;
- `Message` с типом, `clientMessageId`, reply/forward ссылками, metadata, edit/delete timestamps;
- `MessageEdit`, `MessageAttachment`, `MessageReaction`;
- `MessageReadReceipt`, `MessageDelivery`, `PinnedMessage`;
- `ConversationDraft`, `ChatMute`, `ChatAuditEvent`.

Обязательны FK, `UNIQUE(sender_id, client_message_id)`, уникальный direct pair, индексы `(conversation_id, created_at, id)`, membership/unread/list indexes и CHECK-инварианты для direct/group. Typing state хранится только в Redis с коротким TTL.

Для жалоб на постоянные сообщения требуется отдельная связь `chatMessageId`; существующий `Report.messageId` продолжает ссылаться на `RoomMessage`.

## 6. Требуемый API

### Разговоры

- `GET /conversations`
- `POST /conversations/direct`
- `POST /conversations/group`
- `GET|PATCH|DELETE /conversations/:id`
- `POST /conversations/:id/members`
- `DELETE /conversations/:id/members/:userId`
- `POST /conversations/:id/leave`
- `POST|DELETE /conversations/:id/mute`

### Сообщения и состояние

- `GET|POST /conversations/:id/messages`
- `PATCH|DELETE /messages/:id`
- `POST /messages/:id/reactions`
- `DELETE /messages/:id/reactions/:reaction`
- `POST /messages/:id/read`
- `POST|DELETE /messages/:id/pin`
- `GET /conversations/:id/search`
- `POST /conversations/:id/typing`
- `POST|GET /conversations/:id/drafts`

Каждый запрос обязан брать actor/sender только из access token, проверять активное membership и блокировку в том же запросе к ресурсу, применять role policy, DTO validation, rate limit, idempotency и audit. Для чужого ресурса ответ не должен раскрывать его существование.

Realtime расширяется событиями `conversation.*`, `message.*`, `typing.*`, `message.delivered` и `message.read`. `conversation.subscribe` допускается только после серверной проверки membership.

## 7. Риски безопасности

- IDOR при чтении, отправке, поиске, подписке realtime и выдаче media URL.
- Подделка `senderId`, повтор запроса с тем же `clientMessageId` и конфликтующий replay.
- Украденный access token остаётся действителен до его короткого expiry, если guard не проверяет состояние сессии/пользователя.
- Обход двусторонней блокировки, scraping social graph, spam и oversized history queries.
- Process-local rate limits и sequence не подходят для нескольких API instances.
- Утечка message text, точной геолокации, токенов или signed URL через push, analytics, audit и application logs.
- Chat media требует purpose-aware authorization; простая публичная выдача object URL запрещена.
- Незашифрованный SQLite нельзя использовать для exact location или долговечных секретов.
- Admin должен видеть только объект жалобы и ограниченный контекст, а каждый просмотр обязан журналироваться.
- Dev Compose публикует сервисы и известные credentials на host; на общей машине порты должны bind-иться к loopback.
- Production SMS, push, storage, maps, antivirus и monitoring нельзя считать готовыми без реальной интеграции и device/infrastructure tests.

Подробная модель угроз находится в `docs/messenger-threat-model.md`.

## 8. Что нельзя переписывать или смешивать

- `TemporaryRoom`, `RoomMessage`, room reactions/polls/location и их API остаются контуром встречи.
- Существующие signal → Join/Approve → room → memory сценарии и немедленный location revoke остаются regression gate.
- `/api/v1` развивается additively; имена и семантика старых realtime events не переиспользуются.
- Нельзя ослаблять first-party network policy, production environment validation, session/token protection и запрет background location.
- Нельзя удалять существующие отчёты, audit records и причины решений модератора.
- Нельзя заявлять E2EE, production push/SMS/calls/media/maps/monitoring до их фактического подключения и тестирования.

## 9. План реализации

1. **Фаза 1 — основа:** отдельная схема conversations/messages, direct/group policy, текст, cursor pagination, read receipts, idempotency, block checks, realtime subscription, единый Flutter coordinator, пятираздельная навигация, Chats/Chat screens и persistent Demo Mode.
2. **Фаза 2 — надёжность UX:** reply/reactions/edit/delete/pin/search, полноценный offline outbox, retry/reconciliation и delivery state.
3. **Фаза 3 — media:** image/video/file/voice pipeline, membership authorization, quotas, antivirus, EXIF/GPS removal и local demo assets.
4. **Фаза 4 — аудиозвонок 1:1:** signaling authorization, expiring TURN credentials, WebRTC, native lifecycle и физические device tests.
5. **Фаза 5 — видеозвонок 1:1:** camera/PiP/network recovery/quality и безопасное закрытие tracks.
6. **Фаза 6 — закрытые истории:** audience, expiry, views/reactions/replies и story-to-direct-chat.
7. **Фаза 7 — beta:** SFU group calls только после стабильного 1:1, расширение privacy, observability и production readiness.

Read receipts и offline queue указаны в исходном плане как Фаза 2, но одновременно входят в критерий готовности Фазы 1. Для приёмки основы они реализуются и тестируются уже в первой фазе.
