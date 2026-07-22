import { validateEnvironment } from "./environment";

const safeProduction = {
  NODE_ENV: "production",
  DATABASE_URL: "postgresql://db/app",
  REDIS_URL: "redis://redis",
  JWT_SECRET: "j".repeat(40),
  TOKEN_HASH_SECRET: "t".repeat(40),
  PHONE_HASH_SECRET: "p".repeat(40),
  LOCATION_MASTER_KEY_BASE64: "b".repeat(44),
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
});
