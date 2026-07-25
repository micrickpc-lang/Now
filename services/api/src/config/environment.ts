const requiredProductionSecrets = [
  "JWT_SECRET",
  "TOKEN_HASH_SECRET",
  "PHONE_HASH_SECRET",
  "LOCATION_MASTER_KEY_BASE64",
  "LOCATION_PRIVACY_SECRET",
] as const;

const knownDevelopmentMarkers = ["development-", "change-me", "AAAAAAAA"];

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

  if (!value.DATABASE_URL) throw new Error("DATABASE_URL is required");
  if (!value.REDIS_URL) throw new Error("REDIS_URL is required");

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
