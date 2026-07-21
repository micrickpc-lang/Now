# Архитектура

Flutter-клиент разделён feature-first на presentation/domain/data. Riverpod управляет зависимостями и состоянием, Dio — REST, Socket.IO — realtime, secure storage — сессией, Drift/SQLite — только несекретным offline cache. Координаты не попадают в cache/outbox.

NestJS API — модульный монолит с модулями auth, users, social, signals, rooms, maps, moderation, memories и platform. PostgreSQL/PostGIS — system of record. Redis/BullMQ хранит только очередь и эфемерное состояние. Worker физически удаляет location share по TTL и закрывает временные сущности. Media предназначены для MinIO с антивирусной и re-encode обработкой перед публикацией.

Next.js admin обращается к API только server-side. Admin JWT хранится в HttpOnly SameSite=Strict cookie, browser не получает токен API. Все административные решения имеют обязательную причину и audit trail.

```text
Flutter ── REST / WebSocket ──> Nginx ──> NestJS ──> PostgreSQL/PostGIS
                                  │          │  └──> Redis/BullMQ ──> Worker
                                  │          └────> MinIO
                                  ├──> Next admin
                                  └──> Martin tiles
NestJS map gateway ── private network ──> Nominatim
```

См. ADR в `docs/adr`.
