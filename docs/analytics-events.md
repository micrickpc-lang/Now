# Analytics events

Собственный endpoint принимает только allowlist: `onboarding_started`, `onboarding_completed`, `friend_invite_created`, `friend_invite_accepted`, `circle_created`, `signal_created`, `signal_viewed`, `join_requested`, `join_approved`, `activity_completed`, `memory_created`, `day_1_return`, `day_7_return`, `day_30_return`.

User id преобразуется в pseudonym HMAC. Properties — только плоские boolean/number/короткие categorical strings. API отклоняет ключи phone, name, message, latitude, longitude, coordinates, address, contacts, access/refresh/invite token. Тексты, precise time/location и contact book не допускаются.

Event schema version добавляется при первой несовместимой смене. Product dashboards используют агрегаты с порогом минимального размера группы; raw access ограничен analytics role. Retention утверждается в data-retention/legal review.
