# ADR-0001: модульный монолит для MVP

Статус: принято.

NestJS API реализуется как модульный монолит, а TTL/notification jobs вынесены в отдельный worker. Границы auth, social graph, signals, rooms, moderation, maps и privacy выражены модулями и сервисами. Это уменьшает операционную стоимость MVP, сохраняет транзакции вокруг join/room/location и позволяет позднее выделять сервисы по наблюдаемой нагрузке. PostgreSQL — system of record, Redis — ephemeral rate-limit/queue/realtime support, S3-compatible storage — media.
