import { ValidationPipe } from "@nestjs/common";
import type { INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import request from "supertest";
import { AppModule } from "../src/app.module";
import { PrismaService } from "../src/common/prisma.service";

describe("private social main flow (real PostGIS)", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  const suffix = String(Date.now()).slice(-7);
  const phoneA = `+7991${suffix}`;
  const phoneB = `+7992${suffix}`;

  beforeAll(async () => {
    const module = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = module.createNestApplication();
    app.setGlobalPrefix("api/v1");
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    await app.init();
    prisma = app.get(PrismaService);
  });

  afterAll(async () => app.close());

  async function register(phone: string, installationId: string) {
    await request(app.getHttpServer())
      .post("/api/v1/auth/otp/request")
      .send({ phone })
      .expect(201);
    const response = await request(app.getHttpServer())
      .post("/api/v1/auth/otp/verify")
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

  it("enforces friendship, room membership and exact-location revocation", async () => {
    const a = await register(phoneA, `e2e-a-${suffix}`);
    const b = await register(phoneB, `e2e-b-${suffix}`);
    const authA = { Authorization: `Bearer ${a.accessToken}` };
    const authB = { Authorization: `Bearer ${b.accessToken}` };

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

    const signal = await request(app.getHttpServer())
      .post("/api/v1/signals")
      .set(authA)
      .send({
        category: "walk",
        text: "Проверяем основной сценарий",
        startsAt: new Date().toISOString(),
        durationMinutes: 60,
        format: "OFFLINE",
        locationMode: "NONE",
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
    expect(roomForB.body.locationShares[0].value).toMatchObject({
      latitude: 55.7512,
      longitude: 37.6184,
    });
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
    expect(
      await prisma.user.count({
        where: { id: { in: [a.user.id, b.user.id] } },
      }),
    ).toBe(0);
  });
});
