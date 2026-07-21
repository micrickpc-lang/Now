import { Injectable, UnauthorizedException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import argon2 from "argon2";
import jwt from "jsonwebtoken";
import { PrismaService } from "../../common/prisma.service";

export interface AdminPayload {
  sub: string;
  role: string;
  typ: "admin";
}

@Injectable()
export class AdminAuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  async login(email: string, password: string) {
    const admin = await this.prisma.adminUser.findUnique({
      where: { email: email.toLocaleLowerCase("en-US") },
    });
    if (
      !admin?.active ||
      !(await argon2.verify(admin.passwordHash, password))
    ) {
      throw new UnauthorizedException("Неверные учетные данные");
    }
    const token = jwt.sign(
      { role: admin.role, typ: "admin" },
      this.config.getOrThrow<string>("ADMIN_SESSION_SECRET"),
      {
        algorithm: "HS256",
        subject: admin.id,
        issuer: "seychas-api",
        audience: "seychas-admin",
        expiresIn: "30m",
      },
    );
    return { token, expiresIn: 1800, role: admin.role };
  }

  verify(token: string): AdminPayload {
    try {
      const payload = jwt.verify(
        token,
        this.config.getOrThrow<string>("ADMIN_SESSION_SECRET"),
        {
          algorithms: ["HS256"],
          issuer: "seychas-api",
          audience: "seychas-admin",
        },
      );
      if (
        typeof payload === "string" ||
        payload.typ !== "admin" ||
        !payload.sub ||
        typeof payload.role !== "string"
      )
        throw new Error();
      return payload as unknown as AdminPayload;
    } catch {
      throw new UnauthorizedException("Admin session expired");
    }
  }
}
