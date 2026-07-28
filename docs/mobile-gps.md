# GPS в мобильном приложении

## Разрешения и действие пользователя

Приложение использует только foreground location:

- Android manifest содержит `ACCESS_COARSE_LOCATION` и `ACCESS_FINE_LOCATION`, но не содержит `ACCESS_BACKGROUND_LOCATION` или разрешение location foreground service.
- iOS содержит только `NSLocationWhenInUseUsageDescription`; разрешение `Always` и background location mode не объявлены.
- Системная approximate/reduced accuracy считается нормальным разрешённым состоянием и отдельно показывается в UI.

Открытие карты само по себе не запускает GPS и не показывает системный запрос. В map picker пользователь может выбрать место поиском или нажатием на карту без разрешения геолокации. Только нажатие кнопки `Моё местоположение` выполняет такой поток:

1. приложение объясняет, зачем нужна точка;
2. после подтверждения проверяет, включена ли геолокация на устройстве;
3. при необходимости запрашивает foreground-разрешение у ОС;
4. получает одну текущую точку и перемещает к ней карту.

Отказ, постоянный отказ, системное ограничение, выключенная служба, timeout и временная недоступность обрабатываются отдельно. При отказе ручной выбор места остаётся доступен.

## Действие `Готово`

Для сигнала по умолчанию выбран `NONE`. При выборе `CITY`, `DISTRICT` или `APPROXIMATE` picker отправляет выбранную исходную точку first-party API, получает созданную сервером безопасную зону и возвращает в composer только её идентификатор и безопасное описание. Исходная точка не прикрепляется к payload сигнала.

Для exact room location нажатие `Готово` только возвращает выбранную точку экрану комнаты в памяти. Перед первой отправкой показывается отдельное подтверждение `Поделиться`. После успешного создания share приложение открывает foreground GPS stream и обновляет сервер не чаще одного раза в 10 секунд. Мобильный клиент запрашивает TTL 30 минут.

Stream останавливается при отзыве, выходе или завершении комнаты, закрытии экрана комнаты, logout и уничтожении app-scoped coordinator. Сначала останавливается локальная подписка, затем выполняется best-effort server revoke. Координаты не записываются мобильным приложением в persistent local cache, analytics или push payload.

## HTTP staging и release

Текущий bare-IP staging предназначен для временного Android debug-тестирования:

| Клиент                  | HTTP staging                             | Причина                                                                                                                           |
| ----------------------- | ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Android debug           | Поддерживается для теста                 | Debug manifest переопределяет `android:usesCleartextTraffic` в `true`.                                                            |
| Android profile/release | Заблокирован платформой                  | Main manifest задаёт `android:usesCleartextTraffic="false"`; release override отсутствует.                                        |
| iOS                     | Публичный bare-IP HTTP не поддерживается | Из HTTP-исключений ATS настроено только local networking через `NSAllowsLocalNetworking`; публичное HTTP-исключение не добавлено. |

Для iOS и распространяемых Android-сборок нужен first-party DNS host с HTTPS. В non-development конфигурации Flutter также проверяет host по `FIRST_PARTY_DOMAINS`; production принимает только HTTPS endpoints.

## Когда exact отключён

Mobile и backend применяют независимые проверки:

- Flutter разрешает exact только при HTTPS transport (или в полностью локальном Demo Mode). Поэтому на HTTP staging кнопки exact недоступны, exact endpoint не опрашивается, а picker показывает причину блокировки.
- Backend при `ALLOW_EXACT_LOCATION=false` запрещает и запись, и чтение exact share. Значение по умолчанию — `false`; текущий staging явно оставляет его выключенным.
- Backend принимает `ALLOW_EXACT_LOCATION=true` только для `APP_ENV=production` с HTTPS `PUBLIC_API_URL`. В staging включить exact одной сменой флага нельзя.

`CITY`, `DISTRICT` и `APPROXIMATE` не зависят от exact feature flag и остаются безопасными режимами для Android debug HTTP staging.
