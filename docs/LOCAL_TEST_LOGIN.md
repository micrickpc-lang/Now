# Local Test Login

This flow is only for the private Windows LAN development contour. It is not a
real SMS integration.

1. Run `powershell -ExecutionPolicy Bypass -File scripts/windows/start-server.ps1`.
2. On the phone, run `powershell -ExecutionPolicy Bypass -File scripts/windows/run-android.ps1`.
3. Enter any syntactically valid international E.164 number. The onboarding
   screen provides a country calling-code picker for local input; a complete
   `+` number is also accepted.
4. Enter `123456` as the OTP in the generated default local environment.

The private `.env.local-test` is generated once with random database and
cryptographic secrets and restricted file ACLs. It is ignored by Git. Change
`LOCAL_TEST_OTP` only in that file, never in `.env.example` or source code.

`scripts/windows/test-auth.ps1` verifies request, resend, verify, session,
refresh rotation, WebSocket authentication, logout, and rejection of the old
refresh token without printing tokens or phone numbers.
