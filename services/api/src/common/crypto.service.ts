import { Injectable } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import {
  createCipheriv,
  createDecipheriv,
  createHmac,
  randomBytes,
  timingSafeEqual,
} from "node:crypto";

export interface EnvelopeCiphertext {
  ciphertext: string;
  iv: string;
  authTag: string;
  encryptedDataKey: string;
  keyIv: string;
  keyAuthTag: string;
}

@Injectable()
export class CryptoService {
  constructor(private readonly config: ConfigService) {}

  hashToken(value: string): string {
    return this.hmac(value, this.require("TOKEN_HASH_SECRET"));
  }

  hashPhone(value: string): string {
    return this.hmac(value, this.require("PHONE_HASH_SECRET"));
  }

  hashIp(value: string): string {
    return this.hmac(value, this.require("TOKEN_HASH_SECRET"));
  }

  constantTimeEqual(left: string, right: string): boolean {
    const a = Buffer.from(left);
    const b = Buffer.from(right);
    return a.length === b.length && timingSafeEqual(a, b);
  }

  encryptPii(value: string): string {
    const key = this.masterKey();
    const encrypted = this.encrypt(Buffer.from(value, "utf8"), key);
    return [encrypted.iv, encrypted.authTag, encrypted.ciphertext].join(".");
  }

  decryptPii(value: string): string {
    const [iv, authTag, ciphertext] = value.split(".");
    if (!iv || !authTag || !ciphertext)
      throw new Error("Invalid encrypted PII");
    return this.decrypt({ iv, authTag, ciphertext }, this.masterKey()).toString(
      "utf8",
    );
  }

  envelopeEncrypt(value: unknown): EnvelopeCiphertext {
    const dataKey = randomBytes(32);
    const payload = this.encrypt(
      Buffer.from(JSON.stringify(value), "utf8"),
      dataKey,
    );
    const wrappedKey = this.encrypt(dataKey, this.masterKey());
    dataKey.fill(0);
    return {
      ...payload,
      encryptedDataKey: wrappedKey.ciphertext,
      keyIv: wrappedKey.iv,
      keyAuthTag: wrappedKey.authTag,
    };
  }

  envelopeDecrypt(value: EnvelopeCiphertext): unknown {
    const dataKey = this.decrypt(
      {
        ciphertext: value.encryptedDataKey,
        iv: value.keyIv,
        authTag: value.keyAuthTag,
      },
      this.masterKey(),
    );
    try {
      return JSON.parse(
        this.decrypt(value, dataKey).toString("utf8"),
      ) as unknown;
    } finally {
      dataKey.fill(0);
    }
  }

  randomToken(bytes = 32): string {
    return randomBytes(bytes).toString("base64url");
  }

  private hmac(value: string, secret: string): string {
    return createHmac("sha256", secret).update(value).digest("base64url");
  }

  private encrypt(plain: Buffer, key: Buffer) {
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", key, iv);
    const ciphertext = Buffer.concat([cipher.update(plain), cipher.final()]);
    return {
      ciphertext: ciphertext.toString("base64"),
      iv: iv.toString("base64"),
      authTag: cipher.getAuthTag().toString("base64"),
    };
  }

  private decrypt(
    value: { ciphertext: string; iv: string; authTag: string },
    key: Buffer,
  ) {
    const decipher = createDecipheriv(
      "aes-256-gcm",
      key,
      Buffer.from(value.iv, "base64"),
    );
    decipher.setAuthTag(Buffer.from(value.authTag, "base64"));
    return Buffer.concat([
      decipher.update(Buffer.from(value.ciphertext, "base64")),
      decipher.final(),
    ]);
  }

  private masterKey(): Buffer {
    const key = Buffer.from(
      this.require("LOCATION_MASTER_KEY_BASE64"),
      "base64",
    );
    if (key.length !== 32)
      throw new Error("LOCATION_MASTER_KEY_BASE64 must decode to 32 bytes");
    return key;
  }

  private require(key: string): string {
    const value = this.config.get<string>(key);
    if (!value) throw new Error(`${key} is required`);
    return value;
  }
}
