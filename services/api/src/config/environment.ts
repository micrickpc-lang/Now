const requiredProductionSecrets = [
  "JWT_SECRET",
  "TOKEN_HASH_SECRET",
  "PHONE_HASH_SECRET",
  "LOCATION_MASTER_KEY_BASE64",
] as const;

const knownDevelopmentMarkers = ["development-", "change-me", "AAAAAAAA"];

export function validateEnvironment(env: Record<string, unknown>) {
  const value = { ...env } as Record<string, string | undefined>;
  const production = value.NODE_ENV === "production";

  if (!value.DATABASE_URL) throw new Error("DATABASE_URL is required");
  if (!value.REDIS_URL) throw new Error("REDIS_URL is required");

  const trustProxyHops = value.TRUST_PROXY_HOPS ?? "0";
  if (!/^(0|[1-9]\d*)$/.test(trustProxyHops) || Number(trustProxyHops) > 10) {
    throw new Error("TRUST_PROXY_HOPS must be an integer between 0 and 10");
  }
  value.TRUST_PROXY_HOPS = trustProxyHops;

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
    const origins = (value.APP_ORIGINS ?? "").split(",").filter(Boolean);
    if (
      origins.length === 0 ||
      origins.some((origin) => !origin.startsWith("https://"))
    ) {
      throw new Error(
        "Production APP_ORIGINS must be a non-empty HTTPS allowlist",
      );
    }
  }

  return value;
}
