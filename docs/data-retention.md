# Хранение данных

| Категория              |                                                                   MVP retention | Удаление                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------: | ----------------------------------------------------------------------------------------- |
| OTP challenge          |                                      TTL 5 минут; technical cleanup до 24 часов | physical delete                                                                           |
| Access token           |                                               15 минут, не хранится server-side | expiry                                                                                    |
| Refresh session        |                                                              30 дней или revoke | hash удаляется/сессия очищается после grace period                                        |
| Signal                 |                      до 6 часов; metadata остаётся для memory/moderation policy | state expiry, затем policy cleanup                                                        |
| Exact location         |                                             до 180 минут и не позже room expiry | physical delete по revoke/leave/block/complete/TTL                                        |
| Approximate location   |                                             только необратимо огрублённая точка | вместе с signal policy                                                                    |
| Room messages          |                                                  ограниченная временная комната | account deletion anonymizes; финальный срок требует legal approval                        |
| Conversation messages  | до удаления пользователем/аккаунтом и по утверждённой policy постоянной истории | soft delete для пользовательского UX; physical/anonymized cleanup по account/legal policy |
| Message edits/receipts |                              не дольше связанного сообщения и membership policy | cascade/physical cleanup либо минимизация до неидентифицируемого состояния                |
| Conversation drafts    |                    пока участник хранит черновик; очищаются при отправке/выходе | physical delete                                                                           |
| Typing state           |                             Redis TTL в несколько секунд, без PostgreSQL/backup | automatic expiry                                                                          |
| Offline outbox         |                             до успешной отправки или ограниченного retry window | physical local delete; logout очищает pending sensitive payload                           |
| Media                  |                                                  пока memory/account существует | object + thumbnail delete; lifecycle defense in depth                                     |
| Push tokens            |                                                         пока устройство активно | logout-all/account deletion/provider invalidation                                         |
| Audit/anti-fraud       |                                                     минимально необходимый срок | срок и правовое основание утвердить до production                                         |
| Analytics              |                                        pseudonymous, без content/location/phone | агрегирование и удаление raw по утверждённому сроку                                       |

Soft delete не применяется к exact location. Account deletion создаёт минимальный deletion report без телефона/координат и перечисляет категории операций.
