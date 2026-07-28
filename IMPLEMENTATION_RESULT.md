# Implementation Result

Date: 2026-07-28

## Delivered

- Explicit `AUTH_MODE=local_test|real_sms` with startup validation, generic
  HTTP SMS delivery, E.164 local-test login, resend, session inspection,
  refresh rotation and logout revocation.
- Windows LAN local-test contour on `http://<LAN_IP>:8080`: Nginx is the only
  published service; database, Redis, API and worker stay on internal Docker
  networks. Private `.env.local-test` is generated with random secrets and a
  restricted ACL.
- `global_provider` map mode: world camera without Monaco bounds, global
  MapLibre style, fixed server-only geocoding endpoints, authenticated
  search/reverse, cache, throttling, one transient-upstream retry and no
  bearer token on external style requests.
- Foreground-only Android GPS is retained. The application requests location
  only from a user action and does not declare background location permission.
- Physical-device launcher, auth test and complete LAN smoke test are in
  `scripts/windows`.

## Live Windows Verification

`scripts/windows/start-server.ps1` completed against the detected LAN host:

```text
API:     http://192.168.1.68:8080/api/v1
WebSocket ws://192.168.1.68:8080
Docs:    http://192.168.1.68:8080/docs
Health:  200
Ready:   200
```

The smoke test passed request/resend/verify, authenticated session, refresh
rotation and old-token rejection, Socket.IO authentication, logout, global
style, global search and reverse geocoding. Docker status showed Nginx, API,
worker, PostgreSQL and Redis healthy; only Nginx published `8080`.

## Mobile Verification

- `flutter analyze`: passed.
- `flutter test`: 40 passed.
- Debug global-map/LAN APK built at
  `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`.
- The APK installed successfully on physical `Pixel 10 Pro`
  (`57011FDCH0018U`) and `ru.seychas.seychas.MainActivity` was launched.

The device was left on its system lock/notification surface, so no attempt was
made to bypass user authentication for further UI automation.

## Automated Verification

- API unit tests: 18 suites, 110 tests passed.
- API `typecheck` and production `build`: passed.
- Flutter `analyze`: passed.
- Flutter tests: 40 passed.
- Local Windows, staging/Windows and production Compose templates:
  `config --quiet` passed.
- `npm run security:secrets`: passed.

## Remaining Operational Constraint

The bundled Windows local-test defaults use public OpenFreeMap style and
public Nominatim endpoints for low-volume development only. A production
deployment must supply a licensed global style/geocoding provider and real
SMS credentials through its secret manager, as documented in
`docs/MAP_PROVIDER_SETUP.md` and `docs/REAL_SMS_PROVIDER_SETUP.md`.
