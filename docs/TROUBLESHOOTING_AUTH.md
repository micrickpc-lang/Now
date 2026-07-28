# Authentication Troubleshooting

| Symptom | Check |
| --- | --- |
| API exits on startup | `AUTH_MODE=local_test` needs development `NODE_ENV` and `APP_ENV`, allow flag, and six-digit local OTP. |
| `401` after refresh | The refresh token was rotated or revoked. Clear the local session and sign in again. |
| `429` during repeated OTP checks | Wait for the ingress challenge rate limit instead of weakening it. |
| Phone cannot reach API | Verify phone and PC use the same private LAN, `status-server.ps1` passes, and the Private firewall rule allows TCP 8080. |
| Real SMS unavailable | Verify provider URL, sender approval, credential, template `{code}`, and provider delivery logs without copying secrets into application logs. |

Use `scripts/windows/test-auth.ps1` for an isolated local-test verification and
`scripts/windows/smoke-test.ps1` for the complete authenticated API check.
