# Модель угроз закрытого мессенджера

Дата: 22 июля 2026 года. Область: постоянные чаты, realtime, media и их интеграция с существующими сигналами/встречами. Звонки и истории уточняются отдельными review перед соответствующими фазами.

## Активы и границы доверия

Защищаемые активы:

- содержимое и metadata сообщений, черновики, вложения и read state;
- social graph, membership/roles, блокировки и аудитория;
- access/refresh tokens, device sessions и installation identity;
- точная геолокация встречи и ключи её envelope encryption;
- media object keys/signed URLs;
- admin credentials, moderation context и audit log.

Границы доверия: мобильное устройство ↔ API/Nginx, Socket.IO ↔ API instance, API ↔ PostgreSQL/Redis/MinIO/ClamAV, worker ↔ queues/datastores, admin browser ↔ admin/API. Client-supplied IDs, sender, role, state и MIME всегда считаются недоверенными.

## Угрозы, обязательные контроли и проверки

| Угроза                                 | Контроли                                                                                                      | Проверка                                                 |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| Чтение/поиск чужого чата (IDOR)        | Membership в одном DB predicate с ресурсом; одинаковый 404/403 без existence oracle                           | Non-member list/get/messages/search/media/realtime tests |
| Подделка senderId/role                 | Sender и actor только из verified token; role из DB                                                           | DTO с чужим senderId отклоняется/игнорируется            |
| Повторная отправка                     | `UNIQUE(senderId, clientMessageId)`; replay возвращает исходный результат; конфликт payload → 409             | Concurrent duplicate и conflicting replay tests          |
| Обход блокировки                       | Двусторонний block policy перед direct create/send/call/story/location; group membership не уничтожается      | Block в обоих направлениях и общий group test            |
| Scraping social graph/history          | Нет public search; cursor limits; per-user rate limit; minimal DTO                                            | Enumeration/rate tests и privacy review                  |
| Spam/call bombing                      | Redis atomic limits по user/conversation/device, более строгие limitedMode limits                             | Burst, multi-instance и cooldown tests                   |
| Чужая realtime-подписка/fake signaling | Server-side membership на subscribe и на event command; resubscribe revalidation                              | Socket isolation/revocation tests                        |
| Replay/out-of-order realtime           | Event ID, conversation sequence, dedup window, gap detection и API resync                                     | Reconnect/duplicate/gap tests                            |
| Media URL leakage                      | Purpose-aware authorization, random keys, short TTL, revoke check, no SVG, MIME+magic bytes                   | Cross-chat access и expiry tests                         |
| Вредоносное media                      | Quota, ClamAV, image re-encode, EXIF/GPS removal, thumbnail только после scan                                 | EICAR, polyglot, oversized и metadata tests              |
| Кража refresh/access token             | Secure storage, rotation/reuse detection, session/device revoke, short access TTL, session-aware guard        | Logout-all/revoked/suspended user tests                  |
| Утечка location                        | Explicit consent, encrypted exact value, room-only access, TTL и физическое удаление при leave/block/complete | Existing location regression E2E                         |
| Story scraping                         | Explicit audience predicate, block recheck, expiring/revocable media URL                                      | Audience/block/expiry tests (Фаза 6)                     |
| TURN abuse                             | Authenticated call membership, short-lived scoped credentials и quotas                                        | Expiry/scope tests (Фаза 4)                              |
| Небезопасное восстановление истории    | Versioned encrypted backup, integrity/account binding, no plaintext secrets                                   | Restore/replay tests до production backup                |
| Компрометация модератора               | Least privilege, MFA/session policy, object-scoped context, every view audited                                | Admin authorization/audit tests                          |

## Дополнительные правила

- Push не содержит точную геолокацию, токены, invite/TURN/call secrets или скрытый текст.
- Analytics и logs используют allowlist полей; message text, phone, coordinates и credentials запрещены.
- SQLite не хранит exact location, access/refresh tokens или бессрочные media credentials. Чувствительный media cache удаляется по expiry/revoke.
- Удаление для всех, group membership change, report/block/account deletion, звонок и exact location не исполняются автоматически из offline queue без повторной авторизации и актуальной policy-проверки.
- Limited mode допускает direct messages/calls только от друзей, запрещает public invite links и по умолчанию выключает exact location.
- TemporaryRoom сохраняет отдельный TTL lifecycle; постоянная история не наследует room expiry.

## Состояние контролей

Уже есть: JWT validation, refresh rotation, secure mobile token storage, DTO validation, global throttling, friendship/block models, audit service, ClamAV/Sharp/MinIO для аватара, encrypted exact room location и физический revoke.

Добавляется в первой фазе: conversation membership/roles, idempotent messages, cursor limits, read state, block-aware send, conversation realtime authorization, persistent demo/offline storage без sensitive fields и IDOR tests.

Остаётся до production: Redis multi-instance limits/adapter, production push/SMS/storage/maps/monitoring, full chat-media pipeline, coturn/WebRTC device tests, admin MFA/access logging coverage, encrypted backups и отдельно проверенный E2EE protocol.

## Реакция и наблюдаемость

- Denied membership/block/replay attempts пишутся в security metrics без message body и без перечислимого target state.
- Spike по send/subscribe/report/call приводит к rate limit и alert, а не к публикации чувствительных payload.
- Скомпрометированная session/device отзывается; refresh reuse отзывает token family.
- При утечке media key/URL доступ прекращается через короткий TTL и authorization recheck; affected object/key ротируется.
- При инциденте с location используются существующие процедуры `incident-response.md`, удаление shares и проверяемый audit trail.
