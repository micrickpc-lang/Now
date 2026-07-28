import { ValidationPipe } from "@nestjs/common";
import type { INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { ConfigService } from "@nestjs/config";
import request from "supertest";
import { AppModule } from "../src/app.module";
import { PrismaService } from "../src/common/prisma.service";

describe("private social main flow (real PostGIS)", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  const suffix = String(Date.now()).slice(-7);
  const phoneA = `+7991${suffix}`;
  const phoneB = `+7992${suffix}`;
  const phoneC = `+7993${suffix}`;

  beforeAll(async () => {
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ConfigService)
      .useValue(
        new ConfigService({
          ...process.env,
          APP_ENV: process.env.APP_ENV ?? "development",
          // The transport is in-memory HTTP, but this isolated integration
          // fixture exercises the HTTPS-gated exact-share service contract.
          ALLOW_EXACT_LOCATION: "true",
          LOCATION_PRIVACY_SECRET:
            "integration-location-privacy-secret-at-least-32-bytes",
        }),
      )
      .compile();
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

  async function register(phone: string, installationId: string, ip: string) {
    await request(app.getHttpServer())
      .post("/api/v1/auth/otp/request")
      .set("X-Forwarded-For", ip)
      .send({ phone })
      .expect(201);
    const response = await request(app.getHttpServer())
      .post("/api/v1/auth/otp/verify")
      .set("X-Forwarded-For", ip)
      .send({
        phone,
        code: process.env.DEV_OTP_CODE ?? "123456",
        birthDate: "2001-05-10",
        displayName: installationId,
        installationId,
        platform: "android",
      })
      .expect(201);
    return response.body as {
      accessToken: string;
      refreshToken: string;
      user: { id: string };
    };
  }

  it("consumes one OTP only once under concurrent verification", async () => {
    const phone = `+7990${suffix}`;
    const ip = "198.51.100.9";
    await request(app.getHttpServer())
      .post("/api/v1/auth/otp/request")
      .set("X-Forwarded-For", ip)
      .send({ phone })
      .expect(201);
    const payload = (installationId: string) => ({
      phone,
      code: process.env.DEV_OTP_CODE ?? "123456",
      birthDate: "2001-05-10",
      displayName: "OTP race",
      installationId,
      platform: "android",
    });

    const responses = await Promise.all([
      request(app.getHttpServer())
        .post("/api/v1/auth/otp/verify")
        .set("X-Forwarded-For", ip)
        .send(payload(`otp-race-a-${suffix}`)),
      request(app.getHttpServer())
        .post("/api/v1/auth/otp/verify")
        .set("X-Forwarded-For", ip)
        .send(payload(`otp-race-b-${suffix}`)),
    ]);

    expect(responses.map((response) => response.status).sort()).toEqual([
      201, 401,
    ]);
    const success = responses.find((response) => response.status === 201);
    expect(success?.body.user.id).toEqual(expect.any(String));
    expect(
      await prisma.authSession.count({
        where: { userId: success?.body.user.id as string, revokedAt: null },
      }),
    ).toBe(1);
  });

  it("enforces friendship, room membership and exact-location revocation", async () => {
    const a = await register(phoneA, `e2e-a-${suffix}`, "198.51.100.10");
    const b = await register(phoneB, `e2e-b-${suffix}`, "198.51.100.11");
    const c = await register(phoneC, `e2e-c-${suffix}`, "198.51.100.12");
    const authA = { Authorization: `Bearer ${a.accessToken}` };
    const authB = { Authorization: `Bearer ${b.accessToken}` };
    const authC = { Authorization: `Bearer ${c.accessToken}` };

    const invite = await request(app.getHttpServer())
      .post("/api/v1/friends/invites")
      .set(authA)
      .send({})
      .expect(201);
    await request(app.getHttpServer())
      .post(`/api/v1/friends/invites/${invite.body.token}/accept`)
      .set(authB)
      .send({})
      .expect(201);

    const circle = await request(app.getHttpServer())
      .post("/api/v1/circles")
      .set(authA)
      .send({
        name: "E2E",
        emoji: "🧪",
        memberIds: [b.user.id],
      })
      .expect(201);

    const sourcePoint = { latitude: 43.7384, longitude: 7.4246 };
    const safeLocation = await request(app.getHttpServer())
      .post("/api/v1/maps/approximate-location")
      .set(authA)
      .send({
        mode: "APPROXIMATE",
        ...sourcePoint,
        accuracyMeters: 12,
      })
      .expect(201);
    expect(safeLocation.body.radiusMeters).toBeGreaterThanOrEqual(2_000);
    expect(safeLocation.body.center).not.toEqual(sourcePoint);
    const storedSafeLocation = await prisma.$queryRaw<
      Array<{ latitude: number; longitude: number; radiusMeters: number }>
    >`
      SELECT
        ST_Y("safe_center"::geometry) AS "latitude",
        ST_X("safe_center"::geometry) AS "longitude",
        "radius_meters" AS "radiusMeters"
      FROM "safe_location_zones"
      WHERE "id" = ${safeLocation.body.safeLocationId}::uuid
    `;
    expect(storedSafeLocation).toHaveLength(1);
    expect(storedSafeLocation[0]).not.toMatchObject(sourcePoint);
    expect(storedSafeLocation[0]?.radiusMeters).toBeGreaterThanOrEqual(2_000);

    const signal = await request(app.getHttpServer())
      .post("/api/v1/signals")
      .set(authA)
      .send({
        category: "walk",
        text: "Проверяем основной сценарий",
        startsAt: new Date().toISOString(),
        durationMinutes: 60,
        format: "OFFLINE",
        locationMode: "APPROXIMATE",
        safeLocationId: safeLocation.body.safeLocationId,
        maxParticipants: 4,
        circleIds: [circle.body.id],
        userIds: [],
      })
      .expect(201);

    const feed = await request(app.getHttpServer())
      .get("/api/v1/signals/feed")
      .set(authB)
      .expect(200);
    expect(
      feed.body.some((row: { id: string }) => row.id === signal.body.id),
    ).toBe(true);
    const visibleSignal = feed.body.find(
      (row: { id: string }) => row.id === signal.body.id,
    );
    expect(visibleSignal.safeLocation).toMatchObject({
      mode: "APPROXIMATE",
      radiusMeters: expect.any(Number),
    });
    expect(visibleSignal.safeLocation.center).not.toEqual(sourcePoint);
    await request(app.getHttpServer())
      .patch(`/api/v1/signals/${signal.body.id}`)
      .set(authB)
      .send({ text: "IDOR" })
      .expect(404);
    await request(app.getHttpServer())
      .post(`/api/v1/signals/${signal.body.id}/join`)
      .set(authB)
      .send({})
      .expect(201);
    const approval = await request(app.getHttpServer())
      .post(`/api/v1/signals/${signal.body.id}/approve/${b.user.id}`)
      .set(authA)
      .send({})
      .expect(201);
    const roomId = approval.body.roomId as string;

    const message = await request(app.getHttpServer())
      .post(`/api/v1/rooms/${roomId}/messages`)
      .set(authB)
      .send({ body: "Буду через 10 минут" })
      .expect(201);
    await request(app.getHttpServer())
      .post(`/api/v1/rooms/${roomId}/messages/${message.body.id}/reactions`)
      .set(authA)
      .send({ emoji: "👍" })
      .expect(201);
    expect(
      await prisma.roomReaction.count({
        where: { messageId: message.body.id, userId: a.user.id },
      }),
    ).toBe(1);
    const share = await request(app.getHttpServer())
      .post(`/api/v1/rooms/${roomId}/location-share`)
      .set(authA)
      .send({
        latitude: 55.7512,
        longitude: 37.6184,
        ttlMinutes: 30,
        explicitConsent: true,
      })
      .expect(201);
    const roomForB = await request(app.getHttpServer())
      .get(`/api/v1/rooms/${roomId}`)
      .set(authB)
      .expect(200);
    expect(roomForB.body).not.toHaveProperty("locationShares");
    const locationsForB = await request(app.getHttpServer())
      .get(`/api/v1/rooms/${roomId}/location-share`)
      .set(authB)
      .expect(200);
    expect(locationsForB.body[0].value).toMatchObject({
      latitude: 55.7512,
      longitude: 37.6184,
    });
    await request(app.getHttpServer())
      .get(`/api/v1/rooms/${roomId}/location-share`)
      .set(authC)
      .expect(403);
    expect(
      await prisma.auditLog.count({
        where: { action: "location.exact_read", resourceId: share.body.id },
      }),
    ).toBeGreaterThan(0);

    await request(app.getHttpServer())
      .post(`/api/v1/rooms/${roomId}/leave`)
      .set(authB)
      .send({})
      .expect(201);
    await request(app.getHttpServer())
      .get(`/api/v1/rooms/${roomId}`)
      .set(authB)
      .expect(403);
    await request(app.getHttpServer())
      .get(`/api/v1/rooms/${roomId}/location-share`)
      .set(authB)
      .expect(403);
    await request(app.getHttpServer())
      .post(`/api/v1/signals/${signal.body.id}/complete`)
      .set(authA)
      .send({})
      .expect(201);
    expect(await prisma.locationShare.count({ where: { roomId } })).toBe(0);

    await request(app.getHttpServer())
      .post("/api/v1/memories")
      .set(authA)
      .send({ roomId, title: "E2E прогулка", theme: "aurora" })
      .expect(201);
    await request(app.getHttpServer())
      .post(`/api/v1/users/${a.user.id}/block`)
      .set(authB)
      .send({})
      .expect(201);
    expect(
      await prisma.block.count({
        where: { blockerId: b.user.id, blockedId: a.user.id },
      }),
    ).toBe(1);
    await request(app.getHttpServer())
      .delete("/api/v1/users/me")
      .set(authB)
      .send({ confirmation: "УДАЛИТЬ" })
      .expect(200);
    await request(app.getHttpServer())
      .delete("/api/v1/users/me")
      .set(authA)
      .send({ confirmation: "УДАЛИТЬ" })
      .expect(200);
    await request(app.getHttpServer())
      .delete("/api/v1/users/me")
      .set(authC)
      .send({ confirmation: "УДАЛИТЬ" })
      .expect(200);
    expect(
      await prisma.user.count({
        where: { id: { in: [a.user.id, b.user.id, c.user.id] } },
      }),
    ).toBe(0);
  });
});
