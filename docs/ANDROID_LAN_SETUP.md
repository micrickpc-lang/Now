# Android LAN Setup

1. Connect a physical Android phone by USB and authorize USB debugging.
2. Start the Windows LAN server with `scripts/windows/start-server.ps1`.
3. Run `scripts/windows/run-android.ps1`. With more than one device, add
   `-DeviceId <flutter-device-id>`.

The launcher selects only a physical Android device and injects:

```text
APP_ENV=development
API_BASE_URL=http://<LAN_IP>:8080/api/v1
WS_BASE_URL=ws://<LAN_IP>:8080
MAP_MODE=global_provider
MAP_STYLE_URL=<configured global style>
DEMO_MODE=false
```

`10.0.2.2` is emulator-only and is never used for this phone workflow. Android
cleartext HTTP is enabled only in the debug manifest; the main manifest keeps
cleartext disabled. Release and production builds must use HTTPS endpoints.

The map starts at world zoom and supports global search/reverse through the
authenticated API. GPS remains foreground-only: the app requests the regular
location permission only after the user chooses the location action and does
not declare background-location permission.
