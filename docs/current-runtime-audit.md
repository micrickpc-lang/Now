# Runtime Audit

Audit date: 2026-07-28

## Baseline

- Branch: `feat/server-maps-gps`
- Baseline commit: `a2c4c97dfef5143c9c60056d246f38445deec288`
- Windows runtime: Docker Desktop PC stack, ingress published through Nginx only.
- Observed LAN runtime at audit start: `/health` and `/ready` returned `200`; PostgreSQL, Redis, Martin and Nominatim reported healthy.
- Applied Prisma migrations at audit start: `202607210001_init`, `202607220001_persistent_conversations`, `202607220002_server_maps_privacy`, `202607280001_exact_location_sharing`, `202607280002_signal_exact_location`.

## Authentication Flow Found

The existing application already has these backend endpoints:

- `POST /api/v1/auth/otp/request`
- `POST /api/v1/auth/otp/verify`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`
- `GET /api/v1/auth/sessions`

The Flutter flow is phone screen -> `otp/request` -> OTP screen -> `otp/verify` -> secure token storage -> GoRouter redirect to authenticated routes. `ApiClient` adds bearer tokens, serializes refresh requests, retries one failed request after a successful refresh, and clears tokens on failed refresh. The splash screen restores a session from the stored refresh token.

The backend normalizes phone input through `libphonenumber-js`, persists only a phone hash plus encrypted PII, stores a hash of the OTP challenge, limits verification attempts, consumes the challenge transactionally, registers a device, rotates refresh tokens and writes audit events without OTP values.

## Why The Requested Local Login Did Not Work

The shipped PC stack is a `staging` contour. It requires `STAGING_TEST_PHONE_ALLOWLIST` and `STAGING_TEST_OTP`; its provider rejects every valid international number outside that allowlist. This is deliberate for staging but does not satisfy the requested `AUTH_MODE=local_test` flow.

The existing development provider uses `ALLOW_DEV_OTP` and `DEV_OTP_CODE`, but it is not a separately validated auth mode, is not documented as a LAN workflow, and is not protected by the exact production/local-test configuration contract requested in this task.

## Mobile Network Facts

- Default Flutter development URL is `http://10.0.2.2:3000/api/v1`, valid only for an Android emulator.
- The physical-device helper injects the detected LAN address using `dart-define`, so it does not use `10.0.2.2` on a phone.
- Android debug explicitly permits cleartext HTTP; main/release manifest keeps cleartext disabled.
- The current staging helper targets HTTP port `80`; the requested Windows local-test ingress is port `8080`.
- Flutter now has a country-code picker, E.164 normalization, a visible resend timer, and network error display. It calls the dedicated resend endpoint.

## Map Facts

The current default is a self-hosted Monaco pilot:

- MapLibre style, tiles, glyphs and sprites are served through first-party routes.
- Martin serves a Monaco MBTiles extract; Nominatim searches the same regional extract.
- Flutter config has Monaco center and bounds, and the map widgets apply those bounds and a minimum zoom of `8`.
- This makes the map work on the local stack, but it cannot show the whole world or find addresses outside the Monaco extract.

## Implemented Corrections

This audit led to the following changes:

1. Added strictly validated `local_test` and provider-neutral `real_sms` modes without exposing OTPs or tokens in logs.
2. Added a Windows LAN local-test stack on port `8080`, runtime smoke tests and a physical-phone launcher.
3. Added `global_provider` map mode with no regional camera bounds, global search/reverse proxy configuration and provider documentation.
4. Kept the existing self-hosted Monaco stack as an explicit regional fallback.
5. Repeated API, Flutter, Compose and live Windows LAN checks; results are recorded in `IMPLEMENTATION_RESULT.md`.
