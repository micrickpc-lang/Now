# Backup и восстановление

Ежедневно: encrypted `pg_basebackup`/managed snapshot, WAL/PITR, versioned encrypted object-storage backup. Redis не является system of record. Ключ backup encryption отделён от storage credentials и хранится в KMS. Backups не логируют и не экспортируют decrypted exact location отдельно.

Restore drill не реже квартала:

1. Создать изолированную сеть и fresh database.
2. Восстановить snapshot + WAL до выбранной точки.
3. Проверить checksums, миграционную версию, FK/row counts и PostGIS indexes.
4. Запустить privacy smoke: expired location отсутствует; активная зашифрована; доступ проверяется.
5. Восстановить случайную выборку media и проверить hashes/AV status.
6. Зафиксировать RPO/RTO и уничтожить drill environment с отчётом.

Цели MVP: RPO ≤ 24 часа, RTO ≤ 4 часа; до production подтвердить нагрузочным restore drill. Удалённые пользователем данные могут оставаться в backup до истечения backup retention, но не должны возвращаться в active system после restore: deletion tombstone/report replay применяется до открытия трафика.
