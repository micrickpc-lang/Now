import { ConfigService } from "@nestjs/config";
import { CryptoService } from "./crypto.service";

describe("CryptoService", () => {
  const config = new ConfigService({
    TOKEN_HASH_SECRET: "token-secret-that-is-long-enough-for-tests",
    PHONE_HASH_SECRET: "phone-secret-that-is-long-enough-for-tests",
    LOCATION_MASTER_KEY_BASE64: Buffer.alloc(32, 7).toString("base64"),
  });
  const crypto = new CryptoService(config);

  it("round trips PII without exposing plaintext", () => {
    const encrypted = crypto.encryptPii("+79990000000");
    expect(encrypted).not.toContain("+79990000000");
    expect(crypto.decryptPii(encrypted)).toBe("+79990000000");
  });

  it("uses a fresh data key and IV for each exact location share", () => {
    const left = crypto.envelopeEncrypt({ latitude: 55.7, longitude: 37.6 });
    const right = crypto.envelopeEncrypt({ latitude: 55.7, longitude: 37.6 });
    expect(left.ciphertext).not.toBe(right.ciphertext);
    expect(left.encryptedDataKey).not.toBe(right.encryptedDataKey);
    expect(crypto.envelopeDecrypt(left)).toEqual({
      latitude: 55.7,
      longitude: 37.6,
    });
  });

  it("produces deterministic lookup hashes without storing the source", () => {
    expect(crypto.hashPhone("+79990000000")).toBe(
      crypto.hashPhone("+79990000000"),
    );
    expect(crypto.hashPhone("+79990000000")).not.toContain("9990000000");
  });
});
