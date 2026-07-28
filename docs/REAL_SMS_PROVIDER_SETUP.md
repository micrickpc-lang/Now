# Real SMS Provider

Set these values in the private runtime environment, not in Git:

```dotenv
NODE_ENV=production
APP_ENV=production
AUTH_MODE=real_sms
SMS_PROVIDER=http
SMS_API_BASE_URL=https://sms-provider.example/v1/messages
SMS_API_KEY=<provider-secret>
SMS_SENDER=SEYCHAS
SMS_TEMPLATE=Your verification code is {code}
SMS_TIMEOUT_MS=10000
```

The generic adapter sends a JSON `POST` with `Authorization: Bearer
<SMS_API_KEY>`, `Idempotency-Key`, and this body shape:

```json
{"to":"+12025550123","from":"SEYCHAS","message":"Your verification code is 123456","requestId":"uuid"}
```

A 2xx response is accepted unless its JSON body explicitly contains
`success: false` or `error`. The adapter never logs the OTP, phone number, API
key, or complete provider payload. Provider timeouts and failures return a
generic unavailable response to the client.

Use a real delivery account and a sender approved for every target country.
Set `AUTH_MODE=real_sms`; do not set `ALLOW_LOCAL_TEST_OTP` or
`LOCAL_TEST_OTP`. The API fails startup if local-test settings coexist with
real SMS. Staging/SMS.ru remains available only when `AUTH_MODE` is unset.
