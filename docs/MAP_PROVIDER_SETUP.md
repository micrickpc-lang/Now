# Map Provider Contract

See [GLOBAL_MAP_SETUP.md](GLOBAL_MAP_SETUP.md) for the complete runtime and
Flutter configuration. This page defines the provider requirements before a
credential is added.

## Vector style

The provider must expose an HTTPS MapLibre Style Specification v8 document
with globally covered vector sources. Its style must include valid sprite and
glyph URLs with Cyrillic glyph coverage, and support zoom level 18 or higher.
The provider's attribution must remain in the style and MapLibre attribution
control must remain enabled in the app.

Set the style as `MAP_STYLE_URL`. A literal `{MAP_API_KEY}` in that URL is
replaced by the `MAP_API_KEY` dart-define at runtime. Do not put a production
server credential in this value: an APK is not a secret store. Use a scoped
client credential only when direct provider access is required.

## Geocoding

The API proxy accepts two fixed HTTPS provider URLs:

```dotenv
GEOCODING_BASE_URL=https://provider.example/search
REVERSE_GEOCODING_BASE_URL=https://provider.example/reverse
```

The provider must accept Nominatim-compatible query parameters:

- search: `q`, `limit`, `addressdetails`, `format=jsonv2`;
- reverse: `lat`, `lon`, `format=jsonv2`.

Search may return Nominatim rows (`place_id`, `display_name`, `lat`, `lon`) or
a GeoJSON feature collection. Reverse responses should contain an `address`
object with administrative names. Credentials are configured only in the API
environment via `GEOCODING_API_KEY` plus either
`GEOCODING_API_KEY_HEADER` or `GEOCODING_API_KEY_QUERY_PARAM`.

The proxy has no client-supplied upstream URL parameter. It validates input,
uses the configured upstream timeout, rate-limits requests, and does not log
the input coordinates. Public address results are cacheable; raw GPS values
are not stored as cache values.

For the Windows local-test default, the token-free development endpoints are:

```dotenv
GEOCODING_BASE_URL=https://nominatim.openstreetmap.org/search
REVERSE_GEOCODING_BASE_URL=https://nominatim.openstreetmap.org/reverse
```

Public Nominatim is suitable only for low-volume development and has provider
usage limits. Configure a credentialed, globally licensed compatible provider
for real traffic; its key stays solely in the API environment.
