import { Injectable, UnauthorizedException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import jwt from "jsonwebtoken";
import { CryptoService } from "../../common/crypto.service";

export interface AccessPayload {
  sub: string;
  sid: string;
  typ: "access";
  exp: number;
}

@Injectable()
export class TokenService {
  constructor(
    private readonly config: ConfigService,
    private readonly crypto: CryptoService,
  ) {}

  issueAccess(userId: string, sessionId: string): string {
    return jwt.sign({ sid: sessionId, typ: "access" }, this.secret(), {
      algorithm: "HS256",
      subject: userId,
      audience: "seychas-mobile",
      issuer: "seychas-api",
      expiresIn: Number(this.config.get("ACCESS_TOKEN_TTL_SECONDS") ?? 900),
    });
  }

  verifyAccess(token: string): AccessPayload {
    try {
      const payload = jwt.verify(token, this.secret(), {
        algorithms: ["HS256"],
        audience: "seychas-mobile",
        issuer: "seychas-api",
      });
      if (
        typeof payload === "string" ||
        payload.typ !== "access" ||
        !payload.sub ||
        typeof payload.sid !== "string" ||
        typeof payload.exp !== "number"
      ) {
        throw new Error("Invalid access token");
      }
      return payload as unknown as AccessPayload;
    } catch {
      throw new UnauthorizedException("Invalid or expired access token");
    }
  }

  issueRefresh(): { raw: string; hash: string } {
    const raw = this.crypto.randomToken(48);
    return { raw, hash: this.crypto.hashToken(raw) };
  }

  private secret(): string {
    return this.config.getOrThrow<string>("JWT_SECRET");
  }
}
