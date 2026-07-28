# Initial Implementation Audit

Date: 2026-07-28

## Baseline

- Source commit: `77c8bd57e571baca059a6a0bb73dee15a88493f9`
- Baseline branch: `origin/main`
- Implementation branch: `feat/secure-auth-chats-social-map`
- The prior `feat/server-maps-gps` work and uncommitted UX changes were kept in
  `stash@{0}` before the required clean baseline was created.

## Actual Architecture

- Flutter mobile client using Riverpod, GoRouter, Dio, Drift and
  `flutter_secure_storage`.
- NestJS REST and Socket.IO API with Prisma/PostgreSQL/PostGIS.
- Redis is provisioned by Docker Compose but is not used by the API runtime.
- Docker Compose provisions PostgreSQL, Redis, MinIO, ClamAV, API, worker,
  admin and nginx. The self-hosted regional map stack is an optional profile.
- MapLibre is present only as a place picker. It is not a primary social map.
- CI runs Node, Flutter, secret scanning, filesystem and container scanning.

## Database And Migrations

Existing migrations:

1. `202607210001_init`
2. `202607220001_persistent_conversations`

Existing Prisma models include users, SMS OTP challenges, sessions, devices,
friendships, circles, signals, temporary rooms, room location shares,
conversations, messages, media, moderation and deletion reports.

The schema is phone-centric. It has no `AuthIdentity`, `EmailLoginCode`,
email-normalized user identity, refresh-token family, user location history or
location-share recipients required by the master prompt.

## Working Features

- PostgreSQL/PostGIS and Redis services have persistent volumes and healthchecks.
- Prisma migration job precedes API startup in Compose.
- Signed access tokens, hashed refresh tokens, session listing, logout and
  session revocation exist.
- Direct/group conversations, message persistence, cursor pagination, Socket.IO
  events and a plaintext offline outbox exist.
- A privacy-focused temporary room location share model exists.
- API validation, global access-token guard, CORS allowlist and CI scans exist.

## Partial Or Missing Features

- Authentication is SMS OTP only. Email passwordless authentication, Mailpit/
  SMTP delivery, Google Sign-In and account linking are absent.
- Legacy SMS is visible in the mobile onboarding flow and development OTP is
  still an active primary route.
- Refresh rotation exists, but no token family/reuse-detection model exists.
- Redis is not used for rate limits, presence, WebSocket fanout or readiness.
- `/ready` verifies PostgreSQL only; it does not verify Redis or migration state.
- Profile has display name only. Username, email identity and account identity
  management are absent.
- Friendship and chat implementations predate the target request/accept and
  complete group-role contracts.
- Removing a friendship does not revoke active room shares, and blocking does
  not evict active Socket.IO room subscribers.
- The map route is a place picker. There is no permanent `/app/map` social-map
  entry point, friend marker layer or authorized friends-map endpoint.
- Location permission integration is absent from the baseline Android/iOS
  manifests. Exact sharing is room-only and has no general audience model.
- Drift stores messages, drafts and outbox payloads in plaintext SQLite.
- Android has a partial `FLAG_SECURE` implementation, but iOS has no equivalent
  method-channel implementation despite privacy UI copy that claims protection.
- Mobile demo mode can persist outside tests; it must remain explicitly opt-in
  and separated from real API repositories.

## Root Causes

1. The product was built around phone OTP and temporary-room coordination before
   the email/Google identity model was specified.
2. The initial local runtime exposed developer infrastructure directly and did
   not promote Redis into an application dependency.
3. The mobile application has accumulated working feature screens without the
   master route and persistence contracts for a social map.
4. Local offline support was introduced before encrypted-at-rest requirements.

## Change Plan

1. Add an additive Prisma migration for email identities, login codes, session
   families, user locations and recipient-scoped shares. Preserve legacy phone
   data only for compatibility.
2. Implement Mailpit/SMTP passwordless email, Google ID-token verification and
   safe linking. Hide SMS behind an explicit test-only compatibility mode.
3. Make Redis a verified runtime dependency, add Redis-backed rate limiting and
   correct refresh-token reuse handling.
4. Extend profile and friendship APIs, then verify chat membership/IDOR and
   WebSocket authorization with integration tests.
5. Add `/app/map` as a persistent MapLibre social map with server-authorized
   friend markers, GPS consent, expiry and revoke flows.
6. Replace plaintext mobile persistence with encrypted storage, add privacy
   logging controls, CI checks, documentation and release artifacts.

## P0 Implementation Update

Implemented after this baseline audit:

- Additive migration `202607230001_secure_auth_identities` adds encrypted/HMAC
  email identity data, email codes, linked provider identities, device app
  version and retained refresh-token rotation records.
- Mobile primary authentication is email code and Google. Legacy SMS endpoints
  return `403` unless the explicit test-only flag is set.
- Compose includes Mailpit; PostgreSQL and Redis are no longer host-published.
  `/ready` requires both PostgreSQL and Redis.
- A clean PostGIS migration plus 10 API integration tests passed, including
  SMTP delivery to Mailpit and refresh-token replay revocation. Server lint,
  48 unit tests, Flutter analysis and 21 Flutter tests passed.

Blocked verification: real Google authentication requires OAuth client IDs and
a test account. The verifier is implemented and fails closed when no audience
is configured; this is not recorded as an E2E pass.

## P1-P3 Implementation Update

- Realtime now supports validated message, typing and room-location commands.
  Removing a friendship or blocking revokes direct-conversation/room socket
  membership and relevant location recipients. A real Socket.IO integration test
  verifies delivery followed by immediate eviction.
- `/app/map` is a permanent MapLibre branch with world camera, authorized friend
  markers, foreground-only GPS update, selected/friends audience, explicit exact
  consent, TTL and revoke. `202607240001_global_location_sharing` separates this
  model from temporary-room shares and stores precise coordinates encrypted.
- Mobile offline cache uses AES-256-GCM payload envelopes with a Keychain/Keystore
  key, plaintext migration and logout/key-loss cleanup. Android backup/cleartext
  hardening and iOS backup/snapshot protections are in place.
- Map provider inputs now have typed validation, tighter throttling, timeout and
  bounded cache. Production dependency audit is clean and CI emits a CycloneDX
  SBOM artifact.

Residual verification remains intentionally open: real Google OAuth requires
registered client IDs/test accounts; global MBTiles coverage and physical Android/
iOS map and screenshot checks require infrastructure and devices not available in
this Windows workspace.
