# Развёртывание

Local Compose описан в README. Production использует `docker-compose.production.yml` только как service overlay: PostgreSQL/PostGIS, Redis, object storage, secrets и TLS должны предоставляться управляемой private infrastructure или отдельным hardened stack.

1. Создать least-privilege DB roles и проверить PostGIS.
2. Загрузить секреты из KMS-backed secret manager; не использовать `.env` на shared host.
3. Запустить migration job от migrator role, затем smoke/compatibility check.
4. Развернуть API/worker/admin images по immutable digest с read-only FS/non-root.
5. Развернуть versioned tile/style assets, private Nominatim и Martin.
6. Включить TLS 1.2+, HSTS, strict CORS, WAF/ingress limits и admin IP/identity policy.
7. Проверить `/health`, `/ready`, metrics, synthetic OTP (не реальный пользователь), signal-room flow и location TTL.
8. Выполнить canary/rolling rollout; rollback приложения не откатывает необратимую миграцию.

Production secrets: JWT/hash/envelope keys, DB/Redis/MinIO credentials, SMS/Push credentials, admin SSO/session, TLS, backup keys, store signing credentials. Ротация JWT поддерживает overlap key ring перед отключением старого ключа; текущий MVP env использует один ключ и требует расширения key provider до multi-key до public production.

iOS собирается только на macOS/Xcode. Signing credentials находятся в CI secret store. Android release использует `--obfuscate --split-debug-info`, symbols загружаются в закрытое crash storage без PII.
