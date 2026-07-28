import { createHmac } from "node:crypto";
import { ValidationPipe, type INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import request from "supertest";
import { AppModule } from "../src/app.module";
import { PrismaService } from "../src/common/prisma.service";

function hmac(value: string, secret: string) {
  return createHmac("sha256", secret).update(value).digest("base64url");
}

describe("secure passwordless email authentication", () => {
  let app: INestApplication;
  let prisma: PrismaService;

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = module.createNestApplication();
    app.getHttpAdapter().getInstance().set("trust proxy", 1);
    app.setGlobalPrefix("api/v1");
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    await app.listen(0, "127.0.0.1");
    prisma = app.get(PrismaService);
  });

  afterAll(async () => {
    if (app) await app.close();
  });

  it("does not disclose the email code and revokes the family on refresh reuse", async () => {
    const email = `auth-${Date.now()}@example.test`;
    const emailHash = hmac(
      email,
      process.env.EMAIL_HASH_SECRET ??
        "development-only-change-to-at-least-32-bytes",
    );
    const requestCode = await request(app.getHttpServer())
      .post("/api/v1/auth/email/request-code")
      .set("X-Forwarded-For", "198.51.100.42")
      .send({ email })
      .expect(201);
    expect(requestCode.body).toEqual({ accepted: true, retryAfterSeconds: 60 });
    expect(JSON.stringify(requestCode.body)).not.toContain("code");

    const challenge = await prisma.emailLoginCode.findFirstOrThrow({
      where: { emailHash },
      orderBy: { createdAt: "desc" },
    });
    const testCode = "654321";
    await prisma.emailLoginCode.update({
      where: { id: challenge.id },
      data: {
        codeHash: hmac(
          `${emailHash}:${testCode}`,
          process.env.TOKEN_HASH_SECRET ??
            "development-only-change-to-at-least-32-bytes",
        ),
      },
    });

    const signIn = await request(app.getHttpServer())
      .post("/api/v1/auth/email/verify-code")
      .set("X-Forwarded-For", "198.51.100.42")
      .send({
        email,
        code: testCode,
        installationId: `email-auth-${Date.now()}`,
        platform: "android",
        appVersion: "1.0.0-test",
      })
      .expect(201);
    expect(signIn.body.user.profileComplete).toBe(false);
    expect(signIn.body.user.id).toBeTruthy();
    const originalRefresh = signIn.body.refreshToken as string;

    const user = await prisma.user.findUniqueOrThrow({
      where: { id: signIn.body.user.id },
      include: { identities: true },
    });
    expect(user.emailCiphertext).not.toBe(email);
    expect(user.identities.map((identity) => identity.provider)).toContain(
      "EMAIL",
    );

    const rotated = await request(app.getHttpServer())
      .post("/api/v1/auth/refresh")
      .set("X-Forwarded-For", "198.51.100.42")
      .send({ refreshToken: originalRefresh })
      .expect(201);
    const currentRefresh = rotated.body.refreshToken as string;

    await request(app.getHttpServer())
      .post("/api/v1/auth/refresh")
      .set("X-Forwarded-For", "198.51.100.42")
      .send({ refreshToken: originalRefresh })
      .expect(401);
    await request(app.getHttpServer())
      .post("/api/v1/auth/refresh")
      .set("X-Forwarded-For", "198.51.100.42")
      .send({ refreshToken: currentRefresh })
      .expect(401);
  });
});
