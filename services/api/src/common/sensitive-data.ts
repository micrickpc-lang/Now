const sensitiveKeys = new Set(
  [
    "accessToken",
    "refreshToken",
    "authorization",
    "cookie",
    "setCookie",
    "phone",
    "phoneNumber",
    "phoneCiphertext",
    "otp",
    "otpCode",
    "devOtpCode",
    "stagingTestOtp",
    "password",
    "secret",
    "privateKey",
    "inviteToken",
    "latitude",
    "longitude",
    "lat",
    "lon",
    "accuracy",
    "accuracyMeters",
    "coordinates",
    "address",
    "fullAddress",
    "locationShare",
    "locationShares",
    "messageText",
    "privateMessage",
    "body",
    "content",
  ].map(normalizeKey),
);

function normalizeKey(value: string): string {
  return value.replace(/[^a-z0-9]/giu, "").toLocaleLowerCase("en-US");
}

function redactString(value: string): string {
  return value
    .replace(/Bearer\s+[A-Za-z0-9._~-]+/giu, "Bearer [REDACTED]")
    .replace(/\+?\d[\d\s()-]{7,}/gu, "[PHONE_REDACTED]")
    .replace(
      /([?&](?:lat|lon|latitude|longitude|accuracy|q)=)[^&\s]*/giu,
      "$1[REDACTED]",
    )
    .replace(
      /("(?:otp|otpCode|devOtpCode|stagingTestOtp|accessToken|refreshToken|password)"\s*:\s*")[^"]*(")/giu,
      "$1[REDACTED]$2",
    );
}

function visit(value: unknown, seen: WeakSet<object>, depth: number): unknown {
  if (typeof value === "string") return redactString(value);
  if (
    value === null ||
    value === undefined ||
    typeof value === "number" ||
    typeof value === "boolean" ||
    typeof value === "bigint"
  ) {
    return value;
  }
  if (depth > 12) return "[MAX_DEPTH]";
  if (value instanceof Error) {
    return {
      name: value.name,
      message: redactString(value.message),
    };
  }
  if (Buffer.isBuffer(value) || value instanceof Uint8Array) return "[BINARY]";
  if (Array.isArray(value))
    return value.map((item) => visit(item, seen, depth + 1));
  if (typeof value === "symbol" || typeof value === "function")
    return "[UNSERIALIZABLE]";
  if (seen.has(value)) return "[CIRCULAR]";
  seen.add(value);
  const output: Record<string, unknown> = {};
  for (const [key, nested] of Object.entries(value)) {
    output[key] = sensitiveKeys.has(normalizeKey(key))
      ? "[REDACTED]"
      : visit(nested, seen, depth + 1);
  }
  return output;
}

export function redactSensitive(value: unknown): unknown {
  return visit(value, new WeakSet<object>(), 0);
}
