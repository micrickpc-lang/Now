# Authentication Runtime

## Modes

`AUTH_MODE` is explicit. The API rejects invalid combinations during startup.

| Mode | Purpose | SMS delivery |
| --- | --- | --- |
| `local_test` | Windows LAN development only | Never sent |
| `real_sms` | Configured HTTP SMS provider | Provider HTTP API |
| unset | Existing staging/SMS.ru compatibility path | Existing provider |

`local_test` requires all of the following:

```dotenv
NODE_ENV=development
APP_ENV=development
AUTH_MODE=local_test
ALLOW_LOCAL_TEST_OTP=true
LOCAL_TEST_OTP=123456
```

It accepts syntactically valid E.164 input such as `+79991234567`,
`+12025550123`, or `+442079460000`. It has no provider call and logs neither
the phone number nor the OTP. `APP_ENV=staging` and `APP_ENV=production`
cannot start with this mode.

`real_sms` requires `SMS_PROVIDER=http`, a fixed provider URL, key, sender,
template containing `{code}`, and a timeout. Production additionally requires
an HTTPS SMS endpoint. See [REAL_SMS_PROVIDER_SETUP.md](REAL_SMS_PROVIDER_SETUP.md).

## API Contract

- `POST /api/v1/auth/otp/request`
- `POST /api/v1/auth/otp/resend`
- `POST /api/v1/auth/otp/verify`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout`
- `GET /api/v1/auth/session`
- `GET /api/v1/auth/sessions`

OTP challenge values are hashed, expire, are consumed transactionally, and
have an attempt limit. Tokens are returned only by verify/refresh. Refresh
tokens rotate; use of an old token is rejected. Logout revokes the session.
The app keeps tokens in platform secure storage and sends them as bearer
credentials only to the configured API.
