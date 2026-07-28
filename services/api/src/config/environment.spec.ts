import { validateEnvironment } from "./environment";

const safeProduction = {
  NODE_ENV: "production",
  DATABASE_URL: "postgresql://db/app",
  REDIS_URL: "redis://redis",
  JWT_SECRET: "j".repeat(40),
  TOKEN_HASH_SECRET: "t".repeat(40),
  PHONE_HASH_SECRET: "p".repeat(40),
  EMAIL_HASH_SECRET: "e".repeat(40),
  LOCATION_MASTER_KEY_BASE64: "b".repeat(44),
  APP_ORIGINS: "https://admin.example.invalid",
  SMTP_URL: "smtps://smtp.example.invalid",
  EMAIL_FROM: "noreply@example.invalid",
  GOOGLE_CLIENT_IDS: "client-id.apps.googleusercontent.com",
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

  it("requires real email and Google providers in production", () => {
    expect(() =>
      validateEnvironment({
        ...safeProduction,
        EMAIL_DELIVERY_MODE: "disabled",
      }),
    ).toThrow("Disabled email delivery");
    expect(() =>
      validateEnvironment({ ...safeProduction, SMTP_URL: "" }),
    ).toThrow("SMTP_URL");
    expect(() =>
      validateEnvironment({ ...safeProduction, GOOGLE_CLIENT_IDS: "" }),
    ).toThrow("GOOGLE_CLIENT_IDS");
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
