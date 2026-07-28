# Приватность геолокации

## Уровни раскрытия

Сигнал по умолчанию создаётся с `NONE`. Exact location не является полем сигнала и доступна только как отдельный временный share внутри активной комнаты.

| Режим         | Что поступает на backend при выборе              | Что хранится и возвращается участникам сигнала                                                       |
| ------------- | ------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `NONE`        | Ничего                                           | Координат и location label нет.                                                                      |
| `CITY`        | Исходная точка для server-side reverse geocoding | Только название города и безопасное описание; center и radius отсутствуют.                           |
| `DISTRICT`    | Исходная точка для server-side reverse geocoding | Только название района и безопасное описание; center и radius отсутствуют.                           |
| `APPROXIMATE` | Исходная точка и reported device accuracy        | Только огрублённый center и radius безопасной зоны; исходная точка не сохраняется и не возвращается. |

Backend нормализует radius `APPROXIMATE` с шагом 250 метров и ограничивает его диапазоном от 2 до 10 километров. Center привязывается к серверной смещённой сетке соответствующего размера. В PostgreSQL записываются только этот safe center, radius, описание и служебные идентификаторы.

Для `CITY` и `DISTRICT` backend вызывает private Nominatim и оставляет только административные поля. Reverse-geocoding cache живёт 5 минут: ключ содержит SHA-256 digest нормализованной точки, а value — только безопасный label и административный address. Raw source coordinate в safe-location record и cache value не сохраняется.

## Safe-location TTL

До публикации сигнала safe-location draft хранится не более 15 минут. При создании сигнала backend атомарно проверяет owner, mode, отсутствие предыдущего signal attachment и непросроченный TTL, затем устанавливает expiry зоны равным expiry сигнала. Допустимая продолжительность сигнала — от 15 минут до 6 часов; его абсолютный expiry также не может быть дальше чем через 24 часа от момента запроса.

Worker раз в минуту физически удаляет просроченные `safe_location_zones`. API не выдаёт удалённые или просроченные зоны.

## Exact location в комнате

Exact share создаётся только после отдельного явного подтверждения в UI и только если одновременно выполнены transport и server feature gates. На HTTP staging exact отключён мобильным клиентом, а текущий backend staging работает с `ALLOW_EXACT_LOCATION=false`. Backend также отклоняет exact read/write при выключенном флаге; включение флага допустимо только в production с публичным HTTPS API.

Exact payload хранится отдельно в `location_shares` с envelope encryption: для каждой записи используется data key, а координаты и необязательный label находятся только внутри ciphertext. Обычный `GET /rooms/:id` location shares не возвращает; для этого есть отдельный endpoint.

Мобильный клиент использует TTL 30 минут. Backend принимает TTL от 5 до 60 минут и всегда ограничивает expiry сроком комнаты. Повторная отправка обновляет единственную запись owner в этой комнате, не создавая историю точек.

Чтение разрешено только активному участнику активной непросроченной комнаты. Владелец share тоже должен оставаться активным участником; перед выдачей применяется двусторонняя block policy. Бывший участник сразу перестаёт проходить membership check.

Physical delete exact share выполняется при:

- явном revoke;
- выходе владельца share из комнаты;
- block между участниками;
- cancel/completion сигнала и завершении комнаты;
- удалении аккаунта или блокирующей moderation action;
- expiry share либо переходе комнаты в неактивное состояние.

Worker повторяет cleanup каждую минуту. Realtime-события об exact share содержат только owner identifier и expiry, но не location payload.

## Logs, audit и локальное хранение

Structured API logging записывает method, path без query string, status, duration, request id и pseudonymous user reference. Request body не логируется; общий redactor удаляет координаты, accuracy, address, credentials и другие sensitive fields из вложенных объектов и строк. Staging Nginx `safe_json` также пишет только нормализованный `$uri` без query, client IP, body, cookies и authorization headers. Worker логирует только счётчики очищенных записей.

Exact share создаёт audit events `location.exact_shared`, `location.exact_read` и `location.exact_revoked`. В audit metadata есть только resource identifiers и room identifier; координаты, label и decrypted payload туда не записываются. Каждое успешно выданное exact share создаёт отдельный read event.

Координаты запрещено помещать в analytics, push, incident notes и persistent mobile cache. Внутренний geocoder остаётся недоступным из public network; для него нельзя включать query-bearing debug/access logs. UI показывает выбранный privacy level и radius безопасной зоны, а не расстояние до пользователя с точностью до метра. Attribution `© OpenStreetMap contributors` остаётся видимой на карте.
