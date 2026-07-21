# Incident response

Уровни: SEV-1 — утечка location/tokens, массовый takeover или child-safety emergency; SEV-2 — нарушение authorization/moderation; SEV-3 — availability без доказанной утечки.

1. Detect: alert/пользователь/report; назначить incident commander и закрытый канал.
2. Contain: revoke sessions/keys, disable feature flag, stop location reads, isolate service/admin, сохранить audit evidence.
3. Assess: период, субъекты, типы данных, exploit path; не помещать PII/coordinates в incident chat.
4. Eradicate: patch, rotate, scan images/dependencies, проверить persistence.
5. Recover: canary, authorization/location tests, усиленный monitoring.
6. Notify: юридическая команда определяет обязательные сроки/получателей; support использует утверждённый текст.
7. Learn: blameless postmortem, owner/due date, threat model/test update.

Команды быстрого containment: выключить `exact_room_location`, отозвать все сессии затронутого пользователя, удалить location shares, suspend compromised admin, сменить signing/hash keys по runbook. Нельзя удалять audit evidence без решения incident/legal owner.
