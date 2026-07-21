# Приватность геолокации

По умолчанию сигнал создаётся с `NONE`. Разрешения background location в Android/iOS manifest отсутствуют. Приложение запрашивает/получает точку только при действии пользователя в map picker.

- `CITY`/`DISTRICT` содержат текстовый label, без координат.
- `APPROXIMATE` округляет координату на сервере до сетки примерно 1–2 км; исходное значение не сохраняется и не возвращается.
- `EXACT_ROOM` не является полем сигнала. Отдельная запись создаётся после explicit consent, шифруется envelope encryption и имеет TTL не позднее room expiry.

Exact read выполняется только для active room member после двустороннего block check и создаёт audit log. Revoke, leave владельца, block, completion и TTL физически удаляют записи. Ушедший участник сразу не проходит membership check. Worker повторяет cleanup каждую минуту как defense in depth.

Запрещено помещать координаты в logs, analytics, push и local cache. UI использует «место скрыто», «в этом районе», «примерно в 2–3 км», а не расстояние до метра. Attribution карты всегда видима.
