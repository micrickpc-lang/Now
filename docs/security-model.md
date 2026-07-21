# Модель безопасности

## Идентичность и сессии

OTP нормализуется до E.164, challenge живёт 5 минут, число попыток и частота запросов ограничены по keyed hash номера и IP. Ответ запроса одинаков для любого номера. Access JWT действует 15 минут. Refresh token — 384-bit random value; БД хранит только HMAC hash, при refresh значение атомарно заменяется. Повторное использование или гонка отзывает сессии. Устройства и отдельные сессии видимы пользователю.

Development OTP активируется только сочетанием `NODE_ENV=development` и `ALLOW_DEV_OTP=true`; production startup с этими параметрами завершается ошибкой. Production SMS реализуется адаптером `ProductionOtpProvider` и до выбора провайдера намеренно не настроен.

## Авторизация

Все REST endpoints закрыты глобальным access guard, кроме явно помеченных health, базовых map tiles/style и admin login. Каждый social query ограничивает выдачу взаимной дружбой, закрытой visibility и двусторонней block policy. Room operations каждый раз проверяют активное членство, состояние и TTL. WebSocket повторно валидирует access token и незавершённую server-side session; room subscribe проверяет membership.

## Криптография

Телефон шифруется AES-256-GCM и индексируется отдельным keyed HMAC. Exact location использует envelope encryption: случайный data key на запись, AES-256-GCM payload, затем wrapping key. В production master key должен поступать из KMS-backed secret manager и ротироваться re-wrap процедурой. Собственные криптоалгоритмы не применяются.

## Mobile transport

Production-конфигурация запрещает HTTP и endpoints вне first-party allowlist. MVP использует системное TLS validation и certificate transparency/platform trust store вместо жёсткого pinning. Причина: pinning без заранее развернутых backup pins создаёт риск массовой блокировки приложения при аварийной ротации; backend mTLS/internal network, HSTS, короткие токены и first-party allowlist снижают риск. Перед production команда может включить pinning только с двумя независимыми SPKI pins, remote kill-switch и перекрывающимися сроками ротации.

Android `FLAG_SECURE` включается только при отображении exact room location. Токены хранятся в Keychain/Keystore-backed secure storage, очищаются вместе с local cache при logout. Root/jailbreak detection может использоваться только как риск-сигнал и не заменяет server authorization.

## Ограничения

Обфускация mobile release не защищает API. Rate limit в одном API instance работает локально; production ingress и Redis-backed distributed limiter обязательны при горизонтальном масштабировании. Юридические основания retention/audit требуют утверждения до запуска.
