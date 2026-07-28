# Security Threat Model

## Assets

- Email and Google identities, access tokens, refresh-token families and
  session/device metadata.
- Profile data, friendships, conversations, messages, drafts and attachments.
- Exact and approximate locations, audience grants and expiry/revocation state.
- PostgreSQL, Redis, object storage, Mailpit/SMTP and map-provider credentials.

## Trust Boundaries

1. Flutter device to HTTPS/WSS API.
2. API to PostgreSQL, Redis, mail provider, object storage and map provider.
3. API to Socket.IO connections authenticated by Now access tokens.
4. Local encrypted mobile persistence to Android Keystore/iOS Keychain.
5. Windows LAN ingress to internal Compose services.

## Threats And Required Controls

| Threat                                          | Required control                                                                        | Baseline state           |
| ----------------------------------------------- | --------------------------------------------------------------------------------------- | ------------------------ |
| Account enumeration, OTP replay and brute force | Neutral email responses, hash-only codes, TTL, attempt/cooldown and Redis rate limits   | Implemented              |
| OAuth token substitution                        | Verify Google signature, issuer, audience, expiry and verified email server-side        | Implemented, E2E blocked |
| Refresh replay                                  | Token family, rotation, consumed-token detection and family revoke                      | Implemented              |
| IDOR/BOLA in chats and shares                   | Server-derived identity, membership/friendship/block checks and negative tests          | Implemented              |
| Location disclosure                             | Explicit consent, server-computed recipients, TTL, revoke and no background tracking    | Implemented              |
| Local device extraction                         | Encrypted DB keys in Keystore/Keychain, logout clearing and backup exclusion            | Implemented              |
| Infrastructure exposure                         | Ingress-only LAN API, private DB/Redis/Mailpit and production TLS                       | Implemented              |
| Sensitive observability leak                    | Sanitized logger and analytics schema rejecting identity, message and coordinate fields | Implemented              |
| Dependency compromise                           | Locked dependencies, secret scan, SAST, container scan and SBOM                         | Runtime gate implemented |

## Security Decisions

- E2EE is not claimed. It remains BLOCKED until a vetted protocol and complete
  multi-device lifecycle can be implemented and tested.
- Exact location is foreground-only, opt-in, audience-scoped and time-limited.
- Google OAuth client secrets never enter the Flutter artifact; backend
  verification uses environment-provided allowed client IDs.
- Development LAN HTTP is limited to debug builds and private networks; release
  traffic requires HTTPS/WSS and first-party allowlisted domains.
