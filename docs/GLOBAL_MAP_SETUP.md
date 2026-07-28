# Global Map Provider

`self_hosted_regional` remains the default mode for the existing regional PC
stack. It uses the Monaco Martin and Nominatim services and is useful without
an external map account. The `windows-local-test` contour explicitly uses
`global_provider` for a world-wide MapLibre-compatible vector style and
geocoder.

The application never downloads a planet extract. Map rendering comes from a
provider style, while address search and reverse geocoding still go through
the authenticated `GET /api/v1/maps/search` and `GET /api/v1/maps/reverse`
API endpoints.

## Server configuration

Keep provider credentials in the private environment file used by the API,
never in `.env.example`, source code, or logs.

```dotenv
MAP_MODE=global_provider
GEOCODING_BASE_URL=https://geocoder.example.invalid/search
REVERSE_GEOCODING_BASE_URL=https://geocoder.example.invalid/reverse
GEOCODING_API_KEY=
GEOCODING_API_KEY_HEADER=
GEOCODING_API_KEY_QUERY_PARAM=key
MAP_GLOBAL_FALLBACK_TO_SELF_HOSTED=false
MAP_GEOCODER_RETRY_DELAY_MS=1200
```

Both endpoint URLs must be fixed HTTPS URLs for the provider, not a user
supplied URL. They are full operation URLs, such as
`https://provider.example/search` and `https://provider.example/reverse`. The
current proxy expects a Nominatim-compatible `q` search and `lat`/`lon`
reverse contract, and also accepts a GeoJSON feature collection response. Set either `GEOCODING_API_KEY_HEADER` or
`GEOCODING_API_KEY_QUERY_PARAM` according to the provider contract. The key
is sent only from the API process. Search and reverse requests are
authenticated, throttled, time-limited, and cached using hashed cache keys.
One safe retry handles a temporary `408`, `429`, or `5xx` upstream result.

`MAP_GLOBAL_FALLBACK_TO_SELF_HOSTED=true` is a temporary outage fallback only.
It returns to the regional dataset and does not make its results world-wide.
Use `false` for a global deployment that must fail visibly when its provider
is unavailable.

The production/staging Compose API environment must pass all variables above.
The existing Martin and Nominatim services can remain deployed as the
regional fallback; global mode does not expose either service publicly.

## Flutter configuration

Pass the global style and camera settings only at build/run time. No provider
token is committed to the mobile project.

```powershell
cd apps/mobile
flutter run `
  --dart-define=APP_ENV=development `
  --dart-define=API_BASE_URL=http://<LAN_IP>/api/v1 `
  --dart-define=WS_BASE_URL=http://<LAN_IP> `
  --dart-define=MAP_MODE=global_provider `
  --dart-define=MAP_STYLE_URL='https://tiles.example.invalid/styles/basic.json?key={MAP_API_KEY}' `
  --dart-define=MAP_API_KEY='<provider-scoped-mobile-key>' `
  --dart-define=MAP_DEFAULT_LAT=20 `
  --dart-define=MAP_DEFAULT_LNG=0 `
  --dart-define=MAP_DEFAULT_ZOOM=1.5 `
  --dart-define=MAP_MIN_ZOOM=1 `
  --dart-define=MAP_MAX_ZOOM=20 `
  --dart-define=FIRST_PARTY_DOMAINS=<LAN_IP>,tiles.example.invalid
```

`{MAP_API_KEY}` is URL-encoded by `AppConfig` before MapLibre receives the
style URL. Omit `MAP_API_KEY` when the style does not require one. A key in a
mobile build can be extracted, so use a provider key restricted to the app,
style/tile origins, and intended quota. Prefer a first-party style URL or a
provider configuration without a client credential when its terms permit it.

In `global_provider` mode both MapLibre screens use
`CameraTargetBounds.unbounded`; the default camera and min/max zoom use the
defines above. `MAP_MIN_ZOOM` must be from 0 through 2, and
`MAP_MAX_ZOOM` must be from 18 through 24. The regional Monaco bounds are
used only by `self_hosted_regional`.

`GEOCODING_BASE_URL` and `REVERSE_GEOCODING_BASE_URL` are server settings, not
mobile URLs: the Flutter client always calls the authenticated API proxy. This
keeps the geocoding provider credential out of the APK.

## Return to regional maps

Set the API environment back to `MAP_MODE=self_hosted` and launch Flutter
with `MAP_MODE=self_hosted` (or the legacy
`MAP_PROVIDER_MODE=self_hosted_regional`). Use the regular first-party style:

```text
MAP_STYLE_URL=http://<LAN_IP>/api/v1/maps/style.json
```

The regional mode retains the Monaco camera bounds and zoom range because its
local tiles do not cover the rest of the world.
