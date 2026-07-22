import { ValidationPipe } from "@nestjs/common";
import type { INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { randomUUID } from "node:crypto";
import request from "supertest";
import { AppModule } from "../src/app.module";
import { PrismaService } from "../src/common/prisma.service";

interface TestUser {
  accessToken: string;
  user: { id: string };
}

describe("persistent conversation authorization and delivery", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let a: TestUser;
  let b: TestUser;
  let c: TestUser;
  let d: TestUser;
  let directId: string;
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
    // Bind once before issuing concurrent Supertest requests. Otherwise each
    // request may own and close the same ephemeral server independently.
    await app.listen(0, "127.0.0.1");
    prisma = app.get(PrismaService);
    [a, b, c, d] = await Promise.all([
      register(`+7993${suffix}`, `chat-a-${suffix}`, "192.0.2.10"),
      register(`+7994${suffix}`, `chat-b-${suffix}`, "192.0.2.11"),
      register(`+7995${suffix}`, `chat-c-${suffix}`, "192.0.2.12"),
      register(`+7996${suffix}`, `chat-d-${suffix}`, "192.0.2.13"),
    ]);
    await Promise.all([befriend(a, b), befriend(a, c), befriend(a, d)]);
  });

  afterAll(async () => {
    if (prisma && a && b && c && d) {
      const userIds = [a.user.id, b.user.id, c.user.id, d.user.id];
      await prisma.conversation.deleteMany({
        where: { members: { some: { userId: { in: userIds } } } },
      });
      await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    }
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

  it("returns one direct conversation for a canonical friend pair", async () => {
    const first = await request(app.getHttpServer())
      .post("/api/v1/conversations/direct")
      .set(auth(a))
      .send({ friendId: b.user.id })
      .expect(201);
    const second = await request(app.getHttpServer())
      .post("/api/v1/conversations/direct")
      .set(auth(b))
      .send({ friendId: a.user.id })
      .expect(201);
    expect(second.body.id).toBe(first.body.id);
    directId = first.body.id as string;
    expect(
      await prisma.conversation.count({
        where: { directPairKey: { not: null } },
      }),
    ).toBeGreaterThanOrEqual(1);
  });

  it("deduplicates matching clientMessageId and rejects conflicting replay", async () => {
    const clientMessageId = randomUUID();
    const body = { clientMessageId, type: "TEXT", text: "Надёжная доставка" };
    const first = await request(app.getHttpServer())
      .post(`/api/v1/conversations/${directId}/messages`)
      .set(auth(a))
      .send(body)
      .expect(201);
    const retry = await request(app.getHttpServer())
      .post(`/api/v1/conversations/${directId}/messages`)
      .set(auth(a))
      .send(body)
      .expect(201);
    expect(retry.body.id).toBe(first.body.id);
    await request(app.getHttpServer())
      .post(`/api/v1/conversations/${directId}/messages`)
      .set(auth(a))
      .send({ ...body, text: "Подменённое содержимое" })
      .expect(409);
  });

  it("denies a non-member both message reads and sends without exposing existence", async () => {
    await request(app.getHttpServer())
      .get(`/api/v1/conversations/${directId}/messages`)
      .set(auth(c))
      .expect(404);
    await request(app.getHttpServer())
      .post(`/api/v1/conversations/${directId}/messages`)
      .set(auth(c))
      .send({ clientMessageId: randomUUID(), type: "TEXT", text: "IDOR" })
      .expect(404);
  });

  it("enforces group roles", async () => {
    const group = await request(app.getHttpServer())
      .post("/api/v1/conversations/group")
      .set(auth(a))
      .send({ title: "Близкие", memberIds: [b.user.id] })
      .expect(201);
    await request(app.getHttpServer())
      .post(`/api/v1/conversations/${group.body.id as string}/members`)
      .set(auth(b))
      .send({ userId: c.user.id, role: "MEMBER" })
      .expect(403);
  });

  it("records read receipts up to the acknowledged message", async () => {
    const sent = await request(app.getHttpServer())
      .post(`/api/v1/conversations/${directId}/messages`)
      .set(auth(a))
      .send({
        clientMessageId: randomUUID(),
        type: "TEXT",
        text: "Прочитай меня",
      })
      .expect(201);
    const read = await request(app.getHttpServer())
      .post(`/api/v1/messages/${sent.body.id as string}/read`)
      .set(auth(b))
      .send({})
      .expect(201);
    expect(read.body).toMatchObject({ success: true, messageId: sent.body.id });
    expect(
      await prisma.messageReadReceipt.count({
        where: { messageId: sent.body.id, userId: b.user.id },
      }),
    ).toBe(1);
  });

  it("archives former-friend directs as history without allowing new messages", async () => {
    await request(app.getHttpServer())
      .delete(`/api/v1/friends/${b.user.id}`)
      .set(auth(a))
      .expect(200);

    await request(app.getHttpServer())
      .get(`/api/v1/conversations/${directId}/messages`)
      .set(auth(a))
      .expect(200);
    const archived = await request(app.getHttpServer())
      .get(`/api/v1/conversations/${directId}`)
      .set(auth(a))
      .expect(200);
    expect(archived.body.isArchived).toBe(true);

    // Limited mode must not weaken the mutual-friend requirement.
    await prisma.user.update({
      where: { id: a.user.id },
      data: { limitedMode: true },
    });
    try {
      await request(app.getHttpServer())
        .post(`/api/v1/conversations/${directId}/messages`)
        .set(auth(a))
        .send({
          clientMessageId: randomUUID(),
          type: "TEXT",
          text: "Former friends cannot write",
        })
        .expect(403);
    } finally {
      await prisma.user.update({
        where: { id: a.user.id },
        data: { limitedMode: false },
      });
    }
  });

  it("does not reactivate an old direct after block then unblock", async () => {
    const direct = await request(app.getHttpServer())
      .post("/api/v1/conversations/direct")
      .set(auth(a))
      .send({ friendId: c.user.id })
      .expect(201);
    const conversationId = direct.body.id as string;
    await request(app.getHttpServer())
      .post(`/api/v1/conversations/${conversationId}/messages`)
      .set(auth(a))
      .send({
        clientMessageId: randomUUID(),
        type: "TEXT",
        text: "History remains available",
      })
      .expect(201);

    await request(app.getHttpServer())
      .post(`/api/v1/users/${a.user.id}/block`)
      .set(auth(c))
      .send({})
      .expect(201);
    await request(app.getHttpServer())
      .delete(`/api/v1/users/${a.user.id}/block`)
      .set(auth(c))
      .expect(200);

    const archived = await request(app.getHttpServer())
      .get(`/api/v1/conversations/${conversationId}`)
      .set(auth(a))
      .expect(200);
    expect(archived.body.isArchived).toBe(true);
    await request(app.getHttpServer())
      .post(`/api/v1/conversations/${conversationId}/messages`)
      .set(auth(a))
      .send({
        clientMessageId: randomUUID(),
        type: "TEXT",
        text: "Unblock alone is not renewed friendship",
      })
      .expect(403);
  });

  it("makes a direct conversation unreadable and unwritable after a block", async () => {
    const direct = await request(app.getHttpServer())
      .post("/api/v1/conversations/direct")
      .set(auth(a))
      .send({ friendId: d.user.id })
      .expect(201);
    await request(app.getHttpServer())
      .post(`/api/v1/users/${a.user.id}/block`)
      .set(auth(d))
      .send({})
      .expect(201);
    await request(app.getHttpServer())
      .get(`/api/v1/conversations/${direct.body.id as string}`)
      .set(auth(a))
      .expect(404);
    await request(app.getHttpServer())
      .post(`/api/v1/conversations/${direct.body.id as string}/messages`)
      .set(auth(a))
      .send({ clientMessageId: randomUUID(), type: "TEXT", text: "Blocked" })
      .expect(404);
  });
});
