# План реализации MVP

## Границы

MVP реализует закрытый социальный граф, круги, временные сигналы, join/approve, временную комнату, короткие сообщения, реакцию и одно голосование, управляемый location share, блокировки, жалобы, воспоминания и удаление аккаунта. Публичная лента, незнакомцы, звонки, постоянный чат, фоновая геолокация и внешние картографические API исключены.

## Последовательность

1. Монорепозиторий, contracts, design tokens, ADR, CI и локальная инфраструктура.
2. PostgreSQL/PostGIS-модель и миграции; auth с OTP и rotating refresh token.
3. Friends/circles/signals/rooms, server-side authorization и realtime.
4. Приватность геолокации, envelope encryption, TTL worker и audit.
5. Flutter UI/data/domain layers, offline cache, secure token storage и MapLibre.
6. RBAC admin, moderation queue, audit trail и Argon2id credentials.
7. Self-hosted OSM pipeline, Martin, Nominatim gateway, style/assets allowlist.
8. Unit/contract/integration/security/mobile tests, observability and runbooks.

## Проверяемый основной сценарий

Два тестовых пользователя получают OTP, создают сессии, принимают одноразовое приглашение, видят realtime-сигнал, проходят join/approve, входят в комнату, обмениваются сообщением, включают точный location share, проверяют отзыв после выхода/TTL, завершают комнату и создают приватное воспоминание.

## Definition of done

- Build/typecheck/test проходят одной документированной командой.
- Любая выдача точных координат делает membership/block/TTL check и audit запись.
- Production startup отклоняет development OTP и слабые/дефолтные секреты.
- Mobile production config принимает только HTTPS и разрешённые first-party domains.
- Код и конфигурация автоматически сканируются на запрещённые map endpoints и секреты.
