import { randomUUID } from "node:crypto";
import type { AddressInfo } from "node:net";
import { ValidationPipe, type INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import request from "supertest";
import { io, type Socket } from "socket.io-client";
import { AppModule } from "../src/app.module";
import { PrismaService } from "../src/common/prisma.service";
import { RealtimeGateway } from "../src/realtime/realtime.gateway";

interface TestUser {
  accessToken: string;
  user: { id: string };
}

function waitForEvent(socket: Socket, event: string) {
  return new Promise<Record<string, unknown>>((resolve, reject) => {
    const timeout = setTimeout(() => {
      socket.off(event, onEvent);
      reject(new Error(`Timed out waiting for ${event}`));
    }, 3_000);
    const onEvent = (payload: unknown) => {
      clearTimeout(timeout);
      resolve(
        payload && typeof payload === "object"
          ? (payload as Record<string, unknown>)
          : {},
      );
    };
    socket.once(event, onEvent);
  });
}

function expectNoEvent(socket: Socket, event: string) {
  return new Promise<void>((resolve, reject) => {
    const onEvent = () => {
      clearTimeout(timeout);
      reject(new Error(`Unexpected ${event} after access revocation`));
    };
    const timeout = setTimeout(() => {
      socket.off(event, onEvent);
      resolve();
    }, 300);
    socket.once(event, onEvent);
  });
}

function emitAck(
  socket: Socket,
  event: string,
  payload: Record<string, unknown>,
) {
  return new Promise<Record<string, unknown>>((resolve, reject) => {
    const timeout = setTimeout(
      () => reject(new Error(`Timed out waiting for ${event} acknowledgement`)),
      3_000,
    );
    socket.emit(event, payload, (response: unknown) => {
      clearTimeout(timeout);
      resolve(
        response && typeof response === "object"
          ? (response as Record<string, unknown>)
          : {},
      );
    });
  });
}

describe("Socket.IO realtime authorization", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let gateway: RealtimeGateway;
  let baseUrl: string;
  const sockets: Socket[] = [];
  const userIds: string[] = [];
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
    const address = app.getHttpServer().address() as AddressInfo;
    baseUrl = `http://127.0.0.1:${address.port}`;
    prisma = app.get(PrismaService);
    gateway = app.get(RealtimeGateway);
  });

  afterAll(async () => {
    for (const socket of sockets) socket.disconnect();
    try {
      if (userIds.length > 0) {
        await prisma.message.deleteMany({
          where: { senderId: { in: userIds } },
        });
        await prisma.user.deleteMany({ where: { id: { in: userIds } } });
      }
    } finally {
      if (app) await app.close();
    }
  });

  async function register(index: number): Promise<TestUser> {
    const phone = `+799${index}${suffix}`;
    const installationId = `realtime-${index}-${suffix}`;
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
    const user = response.body as TestUser;
    userIds.push(user.user.id);
    return user;
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

  function connect(accessToken: string) {
    return new Promise<Socket>((resolve, reject) => {
      const socket = io(`${baseUrl}/realtime`, {
        autoConnect: false,
        auth: { token: accessToken },
        transports: ["websocket"],
      });
      const timeout = setTimeout(
        () => reject(new Error("Timed out waiting for Socket.IO handshake")),
        3_000,
      );
      socket.once("ready", () => {
        clearTimeout(timeout);
        sockets.push(socket);
        resolve(socket);
      });
      socket.once("auth.error", () => {
        clearTimeout(timeout);
        reject(new Error("Socket.IO authentication failed"));
      });
      socket.once("connect_error", (error) => {
        clearTimeout(timeout);
        reject(error);
      });
      socket.connect();
    });
  }

  it("delivers an authorized push and immediately revokes removed/blocked subscribers", async () => {
    const [a, b, c] = await Promise.all([
      register(1),
      register(2),
      register(3),
    ]);
    await befriend(a, b);
    await befriend(a, c);
    const [directAB, directAC] = await Promise.all([
      request(app.getHttpServer())
        .post("/api/v1/conversations/direct")
        .set(auth(a))
        .send({ friendId: b.user.id })
        .expect(201),
      request(app.getHttpServer())
        .post("/api/v1/conversations/direct")
        .set(auth(a))
        .send({ friendId: c.user.id })
        .expect(201),
    ]);
    const abId = directAB.body.id as string;
    const acId = directAC.body.id as string;
    const [aSocket, bSocket, cSocket] = await Promise.all([
      connect(a.accessToken),
      connect(b.accessToken),
      connect(c.accessToken),
    ]);

    await expect(
      emitAck(bSocket, "conversation.subscribe", { conversationId: abId }),
    ).resolves.toEqual({ ok: true });
    await expect(
      emitAck(cSocket, "conversation.subscribe", { conversationId: acId }),
    ).resolves.toEqual({ ok: true });
    const delivered = waitForEvent(bSocket, "message.created");
    await expect(
      emitAck(aSocket, "message.send", {
        conversationId: abId,
        clientMessageId: randomUUID(),
        type: "TEXT",
        text: "Realtime delivery",
      }),
    ).resolves.toMatchObject({ ok: true });
    expect((await delivered).payload).toMatchObject({ conversationId: abId });

    const removal = waitForEvent(bSocket, "friendship.removed");
    await request(app.getHttpServer())
      .delete(`/api/v1/friends/${b.user.id}`)
      .set(auth(a))
      .expect(200);
    await removal;
    const afterRemoval = expectNoEvent(bSocket, "message.created");
    gateway.emitConversation(abId, "message.created", { conversationId: abId });
    await afterRemoval;
    await expect(
      emitAck(bSocket, "conversation.subscribe", { conversationId: abId }),
    ).resolves.toEqual({ ok: false });

    const blocked = waitForEvent(cSocket, "user.blocked");
    await request(app.getHttpServer())
      .post(`/api/v1/users/${c.user.id}/block`)
      .set(auth(a))
      .send({})
      .expect(201);
    await blocked;
    const afterBlock = expectNoEvent(cSocket, "message.created");
    gateway.emitConversation(acId, "message.created", { conversationId: acId });
    await afterBlock;
    await expect(
      emitAck(cSocket, "conversation.subscribe", { conversationId: acId }),
    ).resolves.toEqual({ ok: false });
  });
});
