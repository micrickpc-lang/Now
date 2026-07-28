const requiredProductionSecrets = [
  "JWT_SECRET",
  "TOKEN_HASH_SECRET",
  "PHONE_HASH_SECRET",
  "LOCATION_MASTER_KEY_BASE64",
  "LOCATION_PRIVACY_SECRET",
] as const;

const knownDevelopmentMarkers = ["development-", "change-me", "AAAAAAAA"];
const authModes = ["local_test", "real_sms"] as const;

function validateConfiguredAuthMode(
  value: Record<string, string | undefined>,
  appEnvironment: string,
) {
  const authMode = value.AUTH_MODE;
  if (authMode === undefined) return;

  if (!authModes.includes(authMode as (typeof authModes)[number])) {
    throw new Error("AUTH_MODE must be local_test or real_sms");
  }

  if (authMode === "local_test") {
    if (value.NODE_ENV !== "development" || appEnvironment !== "development") {
      throw new Error(
        "AUTH_MODE=local_test is allowed only with NODE_ENV=development and APP_ENV=development",
      );
    }
    if (value.ALLOW_LOCAL_TEST_OTP !== "true") {
      throw new Error(
        "AUTH_MODE=local_test requires ALLOW_LOCAL_TEST_OTP=true",
      );
    }
    if (!/^\d{6}$/u.test(value.LOCAL_TEST_OTP ?? "")) {
      throw new Error(
        "AUTH_MODE=local_test requires a six-digit LOCAL_TEST_OTP",
      );
    }
    if (
      value.SMS_PROVIDER !== undefined &&
      value.SMS_PROVIDER !== "local_test"
    ) {
      throw new Error(
        "AUTH_MODE=local_test does not allow an external SMS_PROVIDER",
      );
    }
    value.SMS_PROVIDER = "local_test";
    return;
  }

  if (value.ALLOW_LOCAL_TEST_OTP === "true" || value.LOCAL_TEST_OTP) {
    throw new Error(
      "Local test OTP configuration is forbidden in real_sms mode",
    );
  }
  if (value.SMS_PROVIDER !== undefined && value.SMS_PROVIDER !== "http") {
    throw new Error("AUTH_MODE=real_sms requires SMS_PROVIDER=http");
  }
  value.SMS_PROVIDER = "http";

  let endpoint: URL;
  try {
    endpoint = new URL(value.SMS_API_BASE_URL ?? "");
  } catch {
    throw new Error("SMS_API_BASE_URL must be an absolute HTTP(S) URL");
  }
  if (
    !["http:", "https:"].includes(endpoint.protocol) ||
    (value.NODE_ENV === "production" && endpoint.protocol !== "https:")
  ) {
    throw new Error(
      "Production SMS_API_BASE_URL must use HTTPS (development may use HTTP)",
    );
  }

  const apiKey = value.SMS_API_KEY ?? "";
  if (
    apiKey.length < 16 ||
    /[\r\n]/u.test(apiKey) ||
    knownDevelopmentMarkers.some((marker) => apiKey.includes(marker))
  ) {
    throw new Error("SMS_API_KEY must contain a valid provider credential");
  }
  const sender = value.SMS_SENDER ?? "";
  if (!sender || sender.length > 32 || /[\r\n]/u.test(sender)) {
    throw new Error("SMS_SENDER must be a single-line sender name");
  }
  const template = value.SMS_TEMPLATE ?? "";
  if (
    template.length > 480 ||
    /[\r\n]/u.test(template) ||
    !template.includes("{code}")
  ) {
    throw new Error("SMS_TEMPLATE must contain {code} and be a single line");
  }
  const timeout = value.SMS_TIMEOUT_MS ?? "10000";
  if (
    !/^\d+$/u.test(timeout) ||
    Number(timeout) < 500 ||
    Number(timeout) > 15_000
  ) {
    throw new Error("SMS_TIMEOUT_MS must be between 500 and 15000");
  }
  value.SMS_TIMEOUT_MS = timeout;
}

export function validateEnvironment(env: Record<string, unknown>) {
  const value = { ...env } as Record<string, string | undefined>;
  const production = value.NODE_ENV === "production";
  const appEnvironment =
    value.APP_ENV ?? (production ? "production" : "development");
  if (!["development", "staging", "production"].includes(appEnvironment)) {
    throw new Error("APP_ENV must be development, staging or production");
  }
  if (appEnvironment !== "development" && !production) {
    throw new Error(
      "staging and production APP_ENV require NODE_ENV=production",
    );
  }
  value.APP_ENV = appEnvironment;

  validateConfiguredAuthMode(value, appEnvironment);

  if (!value.DATABASE_URL) throw new Error("DATABASE_URL is required");
  if (!value.REDIS_URL) throw new Error("REDIS_URL is required");

  const otpTtl = value.OTP_TTL_SECONDS ?? "300";
  if (!/^\d+$/u.test(otpTtl) || Number(otpTtl) < 60 || Number(otpTtl) > 900) {
    throw new Error("OTP_TTL_SECONDS must be between 60 and 900");
  }
  value.OTP_TTL_SECONDS = otpTtl;
  if (value.AUTH_MODE === undefined) {
    if (appEnvironment === "development") {
      throw new Error(
        "Development requires AUTH_MODE=local_test or AUTH_MODE=real_sms",
      );
    }
    const smsProvider =
      value.SMS_PROVIDER ??
      (appEnvironment === "production"
        ? "smsru"
        : appEnvironment === "staging"
          ? "staging"
          : "development");
    if (!["development", "staging", "smsru"].includes(smsProvider)) {
      throw new Error("SMS_PROVIDER must be development, staging or smsru");
    }
    if (appEnvironment === "production" && smsProvider !== "smsru") {
      throw new Error("Production requires the smsru SMS provider");
    }
    if (smsProvider === "development" && appEnvironment !== "development") {
      throw new Error(
        "Development SMS provider is forbidden outside development",
      );
    }
    if (smsProvider === "staging" && appEnvironment !== "staging") {
      throw new Error("Staging SMS provider is available only in staging");
    }
    value.SMS_PROVIDER = smsProvider;

    const smsTimeout = value.SMS_RU_TIMEOUT_MS ?? "5000";
    if (
      !/^\d+$/u.test(smsTimeout) ||
      Number(smsTimeout) < 500 ||
      Number(smsTimeout) > 15_000
    ) {
      throw new Error("SMS_RU_TIMEOUT_MS must be between 500 and 15000");
    }
    value.SMS_RU_TIMEOUT_MS = smsTimeout;
    if (smsProvider === "smsru") {
      const apiId = value.SMS_RU_API_ID ?? "";
      if (
        apiId.length < 16 ||
        /\s/u.test(apiId) ||
        knownDevelopmentMarkers.some((marker) => apiId.includes(marker))
      ) {
        throw new Error(
          "SMS_RU_API_ID must contain a valid provider credential",
        );
      }
      const sender = value.SMS_RU_FROM ?? "";
      if (sender.length > 32 || /[\r\n]/u.test(sender)) {
        throw new Error("SMS_RU_FROM must be a single-line sender name");
      }
    }
  }

  const trustProxyHops = value.TRUST_PROXY_HOPS ?? "0";
  if (!/^(0|[1-9]\d*)$/.test(trustProxyHops) || Number(trustProxyHops) > 10) {
    throw new Error("TRUST_PROXY_HOPS must be an integer between 0 and 10");
  }
  value.TRUST_PROXY_HOPS = trustProxyHops;

  const exactLocation = value.ALLOW_EXACT_LOCATION ?? "false";
  if (!/^(true|false)$/u.test(exactLocation)) {
    throw new Error("ALLOW_EXACT_LOCATION must be true or false");
  }
  if (
    exactLocation === "true" &&
    (appEnvironment !== "production" ||
      !(value.PUBLIC_API_URL ?? "").startsWith("https://"))
  ) {
    throw new Error(
      "Exact location requires APP_ENV=production and an HTTPS PUBLIC_API_URL",
    );
  }
  value.ALLOW_EXACT_LOCATION = exactLocation;

  const upstreamTimeout = value.MAP_UPSTREAM_TIMEOUT_MS ?? "3000";
  if (
    !/^\d+$/u.test(upstreamTimeout) ||
    Number(upstreamTimeout) < 250 ||
    Number(upstreamTimeout) > 15_000
  ) {
    throw new Error("MAP_UPSTREAM_TIMEOUT_MS must be between 250 and 15000");
  }
  value.MAP_UPSTREAM_TIMEOUT_MS = upstreamTimeout;

  const geocoderRetryDelay = value.MAP_GEOCODER_RETRY_DELAY_MS ?? "1200";
  if (
    !/^\d+$/u.test(geocoderRetryDelay) ||
    Number(geocoderRetryDelay) < 250 ||
    Number(geocoderRetryDelay) > 3_000
  ) {
    throw new Error(
      "MAP_GEOCODER_RETRY_DELAY_MS must be between 250 and 3000",
    );
  }
  value.MAP_GEOCODER_RETRY_DELAY_MS = geocoderRetryDelay;

  const mapMode = value.MAP_MODE ?? "self_hosted";
  if (!["self_hosted", "global_provider"].includes(mapMode)) {
    throw new Error("MAP_MODE must be self_hosted or global_provider");
  }
  value.MAP_MODE = mapMode;

  if (mapMode === "global_provider") {
    for (const key of ["GEOCODING_BASE_URL", "REVERSE_GEOCODING_BASE_URL"]) {
      const rawUrl = value[key] ?? "";
      try {
        const url = new URL(rawUrl);
        if (
          url.protocol !== "https:" ||
          !url.hostname ||
          url.username ||
          url.password ||
          url.hash
        ) {
          throw new Error("invalid URL");
        }
      } catch {
        throw new Error(`${key} must be an absolute HTTPS provider URL`);
      }
    }
  }

  const geocodingKey = value.GEOCODING_API_KEY ?? "";
  if (geocodingKey.length > 4096 || /[\r\n]/u.test(geocodingKey)) {
    throw new Error(
      "GEOCODING_API_KEY must be a single-line provider credential",
    );
  }
  const geocodingKeyHeader = value.GEOCODING_API_KEY_HEADER ?? "";
  if (
    geocodingKeyHeader &&
    !/^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/u.test(geocodingKeyHeader)
  ) {
    throw new Error(
      "GEOCODING_API_KEY_HEADER must be a valid HTTP header name",
    );
  }
  const geocodingKeyParam = value.GEOCODING_API_KEY_QUERY_PARAM ?? "key";
  if (!/^[A-Za-z][A-Za-z0-9_.-]{0,63}$/u.test(geocodingKeyParam)) {
    throw new Error(
      "GEOCODING_API_KEY_QUERY_PARAM must be a valid provider parameter name",
    );
  }
  value.GEOCODING_API_KEY_QUERY_PARAM = geocodingKeyParam;

  const globalFallback = value.MAP_GLOBAL_FALLBACK_TO_SELF_HOSTED ?? "false";
  if (!/^(true|false)$/u.test(globalFallback)) {
    throw new Error("MAP_GLOBAL_FALLBACK_TO_SELF_HOSTED must be true or false");
  }
  value.MAP_GLOBAL_FALLBACK_TO_SELF_HOSTED = globalFallback;

  const stagingAllowlist = value.STAGING_TEST_PHONE_ALLOWLIST ?? "";
  const stagingOtp = value.STAGING_TEST_OTP ?? "";
  if (appEnvironment === "staging") {
    const phones = stagingAllowlist
      .split(",")
      .map((phone) => phone.trim())
      .filter(Boolean);
    if (
      !phones.length ||
      phones.some((phone) => !/^\+\d{8,15}$/u.test(phone))
    ) {
      throw new Error("A normalized staging test phone allowlist is required");
    }
    if (!/^\d{6}$/u.test(stagingOtp)) {
      throw new Error("A six-digit staging test OTP secret is required");
    }
    if (value.ALLOW_DEV_OTP === "true" || value.DEV_OTP_CODE) {
      throw new Error("Development OTP is forbidden in staging");
    }
  } else if (stagingAllowlist || stagingOtp) {
    throw new Error("Staging OTP configuration is forbidden outside staging");
  }

  if (production) {
    if (value.ALLOW_DEV_OTP === "true" || value.DEV_OTP_CODE) {
      throw new Error("Development OTP is forbidden in production");
    }
    if (value.ALLOW_UNSCANNED_UPLOADS === "true") {
      throw new Error("Unscanned uploads are forbidden in production");
    }
    for (const key of requiredProductionSecrets) {
      const secret = value[key] ?? "";
      if (
        secret.length < 32 ||
        knownDevelopmentMarkers.some((marker) => secret.includes(marker))
      ) {
        throw new Error(
          `${key} must be supplied by a production secret manager`,
        );
      }
    }
    const origins = (value.APP_ORIGINS ?? "")
      .split(",")
      .map((origin) => origin.trim())
      .filter(Boolean);
    if (origins.length === 0) {
      throw new Error("APP_ORIGINS must be a non-empty allowlist");
    }
    const invalidOrigin = origins.some((origin) => {
      try {
        const parsed = new URL(origin);
        return (
          parsed.origin !== origin ||
          !["http:", "https:"].includes(parsed.protocol) ||
          (appEnvironment === "production" && parsed.protocol !== "https:")
        );
      } catch {
        return true;
      }
    });
    if (invalidOrigin) {
      throw new Error(
        appEnvironment === "production"
          ? "Production APP_ORIGINS must be a non-empty HTTPS allowlist"
          : "APP_ORIGINS must contain valid HTTP(S) origins",
      );
    }
  }

  return value;
}
