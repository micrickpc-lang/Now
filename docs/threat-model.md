# Threat model

| Угроза                          | Основной контроль                                                                     | Остаточный риск / следующий контроль                           |
| ------------------------------- | ------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| Кража аккаунта/SIM swap         | короткий access, rotating refresh, список устройств, revoke-all                       | step-up challenge при смене устройства                         |
| Перебор OTP/номеров             | одинаковые ответы, HMAC identifiers, cooldown, IP/phone limits, 5 попыток             | production CAPTCHA/risk engine                                 |
| Stalking/presence inference     | нет strangers, нет фонового tracking, last seen opt-in, безопасные distance labels    | продуктовые abuse-сигналы и support escalation                 |
| Утечка exact location           | room membership/block/TTL checks, envelope encryption, audit on read, physical delete | KMS key isolation и DB audit export                            |
| IDOR                            | owner/member predicates внутри queries; negative E2E test                             | регулярный authorization matrix fuzzing                        |
| Поддельный/replayed invite      | 256-bit token, hash in DB, atomic single use, expiry                                  | verified universal/app links                                   |
| Spam/mass registration          | invite/message/signal limits, forbidden content, limited minor mode                   | device/risk scoring и CAPTCHA adapter                          |
| Fraud/unsafe meeting            | report categories, block, revoke location, moderation trail                           | SLA, escalation runbook, trained moderators                    |
| Malicious admin                 | RBAC, short admin session, required reason, immutable-style audit                     | SSO/MFA, dual control for sensitive access                     |
| Backup leak                     | шифрование, restricted role, restore isolation                                        | external KMS and quarterly restore evidence                    |
| Malicious upload                | planned magic-byte/MIME/size/re-encode/EXIF strip/AV; SVG prohibited                  | media upload не считается production-ready до полного pipeline |
| Push token compromise           | encrypted token, hash index, no sensitive payload, delete on logout/account deletion  | provider credential rotation                                   |
| Social graph scraping           | no public lookup/profile, pagination caps, mutual graph only                          | anomaly detection                                              |
| Minor abuse/grooming            | 14+, minors only mutual/closed, exact off, contacts/links filter, fast report/block   | legal/child-safety review and guardian consent adapter         |
| Realtime replay/flood           | event UUID+sequence, reconnect auth, server membership, socket rate window            | Redis adapter/dedup ledger for multi-instance                  |
| Dependency/container compromise | lockfiles, audit, Dependabot, Trivy, gitleaks                                         | signed images/SBOM/provenance in release pipeline              |

Доверенные границы: mobile device недоверен; edge завершает TLS; API доверяет только validated identity; DB/Redis/MinIO находятся в private network; admin — отдельная привилегированная поверхность. Точные координаты, SMS credentials, signing keys и backups — критические активы.
