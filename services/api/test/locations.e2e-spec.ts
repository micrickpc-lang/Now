import { ValidationPipe, type INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import request from "supertest";
import { AppModule } from "../src/app.module";
import { PrismaService } from "../src/common/prisma.service";

interface TestUser {
  accessToken: string;
  user: { id: string };
}

describe("global location sharing", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  const suffix = String(Date.now()).slice(-7);

  const auth = (user: TestUser) => ({
    Authorization: `Bearer ${user.accessToken}`,
  });

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

  async function register(index: number): Promise<TestUser> {
    const phone = `+798${index}${suffix}`;
    const installationId = `location-e2e-${index}-${suffix}`;
    await request(app.getHttpServer())
      .post("/api/v1/auth/otp/request")
      .set("X-Forwarded-For", `198.51.100.${index}`)
      .send({ phone })
      .expect(201);
    const response = await request(app.getHttpServer())
      .post("/api/v1/auth/otp/verify")
      .set("X-Forwarded-For", `198.51.100.${index}`)
      .send({
        phone,
        code: process.env.DEV_OTP_CODE ?? "123456",
        birthDate: "2001-05-10",
        displayName: installationId,
        installationId,
        platform: "android",
      })
      .expect(201);
    return response.body as TestUser;
  }

  async function befriend(left: TestUser, right: TestUser) {
    const invite = await request(app.getHttpServer())
      .post("/api/v1/friends/invites")
      .set(auth(left))
      .send({})
      .expect(201);
    await request(app.getHttpServer())
      .post(`/api/v1/friends/invites/${invite.body.token as string}/accept`)
      .set(auth(right))
      .send({})
      .expect(201);
  }

  it("encrypts a location and exposes an approximate marker only to an active friend", async () => {
    const [owner, friend, stranger] = await Promise.all([
      register(4),
      register(5),
      register(6),
    ]);
    await befriend(owner, friend);

    await request(app.getHttpServer())
      .put("/api/v1/locations/me")
      .set(auth(owner))
      .send({ latitude: 55.75581, longitude: 37.61734 })
      .expect(200);
    const stored = await prisma.userLocation.findUniqueOrThrow({
      where: { ownerId: owner.user.id },
    });
    expect(JSON.stringify(stored)).not.toContain("55.75581");
    expect(JSON.stringify(stored)).not.toContain("37.61734");

    await request(app.getHttpServer())
      .post("/api/v1/location-shares")
      .set(auth(owner))
      .send({
        audience: "FRIENDS",
        precision: "APPROXIMATE",
        ttlMinutes: 30,
        explicitConsent: true,
      })
      .expect(201);

    const friendMap = await request(app.getHttpServer())
      .get("/api/v1/map/friends")
      .set(auth(friend))
      .expect(200);
    expect(friendMap.body.markers).toEqual([
      expect.objectContaining({
        userId: owner.user.id,
        precision: "APPROXIMATE",
        latitude: 55.76,
        longitude: 37.62,
      }),
    ]);
    await request(app.getHttpServer())
      .get("/api/v1/map/friends")
      .set(auth(stranger))
      .expect(200)
      .expect({ markers: [] });

    await request(app.getHttpServer())
      .post("/api/v1/location-shares")
      .set(auth(owner))
      .send({
        audience: "SELECTED",
        recipientIds: [stranger.user.id],
        precision: "EXACT",
        ttlMinutes: 30,
        explicitConsent: true,
      })
      .expect(403);

    await request(app.getHttpServer())
      .delete(`/api/v1/friends/${friend.user.id}`)
      .set(auth(owner))
      .expect(200);
    await request(app.getHttpServer())
      .get("/api/v1/map/friends")
      .set(auth(friend))
      .expect(200)
      .expect({ markers: [] });
  });
});
