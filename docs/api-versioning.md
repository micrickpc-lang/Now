# Версионирование API

REST prefix — `/api/v1`. В пределах v1 разрешены добавление необязательных полей и новых endpoints/events. Удаление, смена типа/семантики или ужесточение обязательного DTO требует v2 либо заранее опубликованного migration window.

Realtime envelope содержит UUID, sequence и occurredAt. Новые event payload fields должны игнорироваться старым клиентом. Название/семантика события не переиспользуется.

Mobile отправляет semantic app version; `minimum_supported_version` feature flag обеспечивает forced update только при критической уязвимости. Deprecation включает telemetry без PII, release notes, минимум один поддерживаемый mobile release overlap и явную дату отключения.
