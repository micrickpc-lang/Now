# Map Troubleshooting

| Symptom | Check |
| --- | --- |
| Map is limited to Monaco | Launch server and Flutter with `MAP_MODE=global_provider`. |
| Style does not load | `MAP_STYLE_URL` must be an HTTPS MapLibre v8 style reachable by the phone. Restrict any mobile key at the provider. |
| Search/reverse returns `502` | Set full fixed HTTPS endpoints, for example `.../search` and `.../reverse`, not only a provider domain. Verify provider quota and key server-side. |
| Search/reverse returns `401` | Sign in first. These endpoints are intentionally authenticated. |
| Provider returns `429` or temporary `5xx` | The API retries one safe geocoding GET. Configure a credentialed provider for sustained usage. |
| GPS has no position | Enable system location, grant foreground permission, and retry from the map control. Background tracking is deliberately unavailable. |

Use [MAP_PROVIDER_SETUP.md](MAP_PROVIDER_SETUP.md) for the provider request
contract and [GLOBAL_MAP_SETUP.md](GLOBAL_MAP_SETUP.md) for runtime defines.
