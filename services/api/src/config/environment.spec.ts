import { validateEnvironment } from "./environment";

const safeProduction = {
  NODE_ENV: "production",
  DATABASE_URL: "postgresql://db/app",
  REDIS_URL: "redis://redis",
  JWT_SECRET: "j".repeat(40),
  TOKEN_HASH_SECRET: "t".repeat(40),
  PHONE_HASH_SECRET: "p".repeat(40),
  LOCATION_MASTER_KEY_BASE64: "b".repeat(44),
  LOCATION_PRIVACY_SECRET: "privacy-secret-which-is-at-least-32-bytes",
  APP_ORIGINS: "https://admin.example.invalid",
  SMS_PROVIDER: "smsru",
  SMS_RU_API_ID: "unit-test-provider-credential",
};

const localTestEnvironment = {
  NODE_ENV: "development",
  APP_ENV: "development",
  DATABASE_URL: "postgresql://db/app",
  REDIS_URL: "redis://redis",
  AUTH_MODE: "local_test",
  ALLOW_LOCAL_TEST_OTP: "true",
  LOCAL_TEST_OTP: "123456",
};

const realSmsEnvironment = {
  ...safeProduction,
  AUTH_MODE: "real_sms",
  SMS_PROVIDER: "http",
  SMS_API_BASE_URL: "https://sms.example.invalid/v1/messages",
  SMS_API_KEY: "real-provider-credential-for-tests",
  SMS_SENDER: "Seichas",
  SMS_TEMPLATE: "Your code is {code}",
  SMS_TIMEOUT_MS: "10000",
};

describe("validateEnvironment", () => {
  it("accepts local_test only with its explicit development guard", () => {
    const value = validateEnvironment(localTestEnvironment);
    expect(value.AUTH_MODE).toBe("local_test");
    expect(value.SMS_PROVIDER).toBe("local_test");
  });

  it.each([
    {
      NODE_ENV: "production",
      APP_ENV: "production",
      error: "allowed only",
    },
    { ALLOW_LOCAL_TEST_OTP: "false", error: "ALLOW_LOCAL_TEST_OTP" },
    { LOCAL_TEST_OTP: "invalid", error: "LOCAL_TEST_OTP" },
    { SMS_PROVIDER: "http", error: "external SMS_PROVIDER" },
  ])("rejects unsafe local_test configuration", (override) => {
    const { error, ...environment } = override;
    expect(() =>
      validateEnvironment({ ...localTestEnvironment, ...environment }),
    ).toThrow(error);
  });

  it("validates the provider-neutral real SMS configuration", () => {
    expect(validateEnvironment(realSmsEnvironment).SMS_PROVIDER).toBe("http");
  });

  it.each([
    { SMS_API_BASE_URL: "not-a-url", error: "SMS_API_BASE_URL" },
    { SMS_API_KEY: "too-short", error: "SMS_API_KEY" },
    { SMS_TEMPLATE: "No code placeholder", error: "SMS_TEMPLATE" },
    { SMS_PROVIDER: "smsru", error: "SMS_PROVIDER=http" },
  ])("rejects incomplete real SMS configuration", (override) => {
    const { error, ...environment } = override;
    expect(() =>
      validateEnvironment({ ...realSmsEnvironment, ...environment }),
    ).toThrow(error);
  });

  it("requires HTTPS for a production real SMS endpoint", () => {
    expect(() =>
      validateEnvironment({
        ...realSmsEnvironment,
        SMS_API_BASE_URL: "http://sms.example.invalid/v1/messages",
      }),
    ).toThrow("HTTPS");
  });

  it("rejects development OTP in production", () => {
    expect(() =>
      validateEnvironment({ ...safeProduction, ALLOW_DEV_OTP: "true" }),
    ).toThrow("Development OTP");
  });

  it("requires a configured real SMS provider in production", () => {
    expect(() =>
      validateEnvironment({
        ...safeProduction,
        SMS_PROVIDER: "staging",
      }),
    ).toThrow("Production requires");
    expect(() =>
      validateEnvironment({
        ...safeProduction,
        SMS_RU_API_ID: "",
      }),
    ).toThrow("SMS_RU_API_ID");
  });

  it("requires an explicit auth mode for development", () => {
    expect(() =>
      validateEnvironment({
        NODE_ENV: "development",
        APP_ENV: "development",
        DATABASE_URL: "postgresql://db/app",
        REDIS_URL: "redis://redis",
        SMS_PROVIDER: "development",
        ALLOW_DEV_OTP: "false",
      }),
    ).toThrow("AUTH_MODE");
  });

  it("validates the OTP lifetime", () => {
    expect(() =>
      validateEnvironment({
        ...safeProduction,
        OTP_TTL_SECONDS: "forever",
      }),
    ).toThrow("OTP_TTL_SECONDS");
  });

  it("rejects non-HTTPS production origins", () => {
    expect(() =>
      validateEnvironment({
        ...safeProduction,
        APP_ORIGINS: "http://admin.example.invalid",
      }),
    ).toThrow("HTTPS");
  });

  it("rejects known development secret markers", () => {
    expect(() =>
      validateEnvironment({
        ...safeProduction,
        JWT_SECRET: "development-secret-that-must-never-ship",
      }),
    ).toThrow("secret manager");
  });

  it.each(["-1", "1.5", "true", "11"])(
    "rejects an invalid trusted proxy hop count: %s",
    (TRUST_PROXY_HOPS) => {
      expect(() =>
        validateEnvironment({ ...safeProduction, TRUST_PROXY_HOPS }),
      ).toThrow("TRUST_PROXY_HOPS");
    },
  );

  it("defaults to direct-client IP handling", () => {
    expect(validateEnvironment(safeProduction).TRUST_PROXY_HOPS).toBe("0");
  });

  it("fails closed when staging OTP configuration reaches production", () => {
    expect(() =>
      validateEnvironment({
        ...safeProduction,
        APP_ENV: "production",
        STAGING_TEST_PHONE_ALLOWLIST: "+79990000000",
        STAGING_TEST_OTP: "654321",
      }),
    ).toThrow("outside staging");
  });

  it("accepts staging OTP only with an explicit allowlist and secret", () => {
    expect(
      validateEnvironment({
        ...safeProduction,
        APP_ENV: "staging",
        SMS_PROVIDER: "staging",
        APP_ORIGINS: "http://192.0.2.10",
        PUBLIC_API_URL: "http://192.0.2.10/api/v1",
        STAGING_TEST_PHONE_ALLOWLIST: "+79990000000,+79990000001",
        STAGING_TEST_OTP: "654321",
      }).APP_ENV,
    ).toBe("staging");
  });

  it("keeps exact location disabled unless HTTPS is explicitly configured", () => {
    expect(validateEnvironment(safeProduction).ALLOW_EXACT_LOCATION).toBe(
      "false",
    );
    expect(() =>
      validateEnvironment({
        ...safeProduction,
        ALLOW_EXACT_LOCATION: "true",
        PUBLIC_API_URL: "http://staging.invalid/api/v1",
      }),
    ).toThrow("HTTPS");
  });

  it("keeps exact location disabled in staging even behind HTTPS", () => {
    expect(() =>
      validateEnvironment({
        ...safeProduction,
        APP_ENV: "staging",
        SMS_PROVIDER: "staging",
        PUBLIC_API_URL: "https://staging.example.invalid/api/v1",
        ALLOW_EXACT_LOCATION: "true",
        STAGING_TEST_PHONE_ALLOWLIST: "+79990000000",
        STAGING_TEST_OTP: "654321",
      }),
    ).toThrow("APP_ENV=production");
  });

  it("requires fixed HTTPS upstreams in global map mode", () => {
    expect(() =>
      validateEnvironment({
        ...safeProduction,
        MAP_MODE: "global_provider",
      }),
    ).toThrow("GEOCODING_BASE_URL");

    expect(
      validateEnvironment({
        ...safeProduction,
        MAP_MODE: "global_provider",
        GEOCODING_BASE_URL: "https://geocoder.example.invalid/search",
        REVERSE_GEOCODING_BASE_URL: "https://geocoder.example.invalid/reverse",
      }).MAP_MODE,
    ).toBe("global_provider");
  });

  it("rejects malformed global geocoder credential settings", () => {
    expect(() =>
      validateEnvironment({
        ...safeProduction,
        GEOCODING_API_KEY_HEADER: "invalid header",
      }),
    ).toThrow("GEOCODING_API_KEY_HEADER");
  });
});
