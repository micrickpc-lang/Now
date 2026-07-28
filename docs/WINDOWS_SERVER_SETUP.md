# Windows LAN Server

## Start

Prerequisites: Docker Desktop with Compose v2, a private LAN adapter, and
outbound Internet access for the selected global map provider.

```powershell
powershell -ExecutionPolicy Bypass -File scripts/windows/start-server.ps1
```

On the first run the script creates ignored `.env.local-test`, detects the LAN
IPv4, validates Compose, builds images, applies Prisma migrations, starts the
stack, and executes the complete smoke test. The ingress is:

```text
http://<LAN_IP>:8080/api/v1
ws://<LAN_IP>:8080
http://<LAN_IP>:8080/docs
http://<LAN_IP>:8080/health
http://<LAN_IP>:8080/ready
```

Only Nginx binds a host port (`8080`). PostgreSQL, Redis, API, worker, and
migration services use the internal Docker network and have no published
ports.

Use these operational commands:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/windows/status-server.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/smoke-test.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/stop-server.ps1
```

To expose the development contour on a trusted Wi-Fi only, create a Private
profile firewall rule deliberately:

```powershell
New-NetFirewallRule -DisplayName 'Seychas local-test LAN' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8080 -Profile Private
```

Do not create a Public-profile rule. The local-test contour is HTTP debug
traffic only; production requires HTTPS and `AUTH_MODE=real_sms`.
