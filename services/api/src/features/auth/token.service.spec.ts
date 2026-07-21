import { ConfigService } from "@nestjs/config";
import jwt from "jsonwebtoken";
import { CryptoService } from "../../common/crypto.service";
import { TokenService } from "./token.service";

describe("TokenService", () => {
  const secret = "jwt-secret-that-is-long-enough-for-unit-tests";
  const config = new ConfigService({
    JWT_SECRET: secret,
    TOKEN_HASH_SECRET: "hash-secret-that-is-long-enough-for-unit-tests",
    PHONE_HASH_SECRET: "phone-secret-that-is-long-enough-for-unit-tests",
    LOCATION_MASTER_KEY_BASE64: Buffer.alloc(32).toString("base64"),
  });
  const service = new TokenService(config, new CryptoService(config));

  it("accepts a valid short-lived access token", () => {
    expect(
      service.verifyAccess(service.issueAccess("user", "session")),
    ).toMatchObject({ sub: "user", sid: "session", typ: "access" });
  });

  it("rejects an expired access token", () => {
    const expired = jwt.sign({ sid: "session", typ: "access" }, secret, {
      subject: "user",
      issuer: "seychas-api",
      audience: "seychas-mobile",
      expiresIn: -1,
    });
    expect(() => service.verifyAccess(expired)).toThrow("Invalid or expired");
  });

  it("generates non-reusable refresh secrets represented by hashes", () => {
    const left = service.issueRefresh();
    const right = service.issueRefresh();
    expect(left.raw).not.toBe(right.raw);
    expect(left.hash).not.toBe(left.raw);
  });
});
