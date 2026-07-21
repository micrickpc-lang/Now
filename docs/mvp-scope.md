# Границы MVP

Включено: OTP и устройства, возраст 14+, усиленный minor mode, взаимная дружба через одноразовое приглашение/QR/code, закрытые круги, временные сигналы, join/approve, временная room, короткий текст/reactions/одно голосование, block/report/moderation, exact room location consent+TTL, memories, account deletion, first-party MapLibre stack, admin, metrics/backups/runbooks.

Исключено: публичная лента/профили, discovery незнакомцев, people-nearby, постоянный messenger, файлы в chat, forwarding, calls/live/video, stories, ads/currency/crypto, background tracking, precise friend distance, public tiles/geocoder/router, routing в V1, AI без отдельной необходимости.

Не считаются production-ready без внешней настройки: SMS/Push providers, юридические тексты/consent flow, production domains/TLS/secret manager, store signing, полный pilot-region OSM import, admin SSO/MFA, sizing/мониторинг production ClamAV и lifecycle/backup policy для media bucket. Сам pipeline загрузки уже проверяет magic bytes, сканирует ClamAV, удаляет EXIF/GPS через re-encode, создаёт thumbnail и хранит объекты приватно.
