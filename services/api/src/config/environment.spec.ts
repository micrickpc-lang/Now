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
};

describe("validateEnvironment", () => {
  it("rejects development OTP in production", () => {
    expect(() =>
      validateEnvironment({ ...safeProduction, ALLOW_DEV_OTP: "true" }),
    ).toThrow("Development OTP");
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
        PUBLIC_API_URL: "https://staging.example.invalid/api/v1",
        ALLOW_EXACT_LOCATION: "true",
        STAGING_TEST_PHONE_ALLOWLIST: "+79990000000",
        STAGING_TEST_OTP: "654321",
      }),
    ).toThrow("APP_ENV=production");
  });
});
