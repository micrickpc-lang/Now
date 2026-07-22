import { randomUUID } from "node:crypto";
import type { PrismaService } from "../common/prisma.service";
import type { TokenService } from "../features/auth/token.service";
import { RealtimeGateway } from "./realtime.gateway";

describe("RealtimeGateway authorization", () => {
  const userId = randomUUID();
  const sessionId = randomUUID();
  const conversationId = randomUUID();
  const otherId = randomUUID();
  const tokensMock = { verifyAccess: jest.fn() };
  const prismaMock = {
    authSession: { findFirst: jest.fn() },
    roomMember: { findFirst: jest.fn() },
    conversationMember: { findFirst: jest.fn() },
    block: { count: jest.fn() },
    friendship: { findFirst: jest.fn() },
  };
  const gateway = new RealtimeGateway(
    tokensMock as unknown as TokenService,
    prismaMock as unknown as PrismaService,
  );

  function socket(token = "access") {
    return {
      data: {},
      connected: true,
      handshake: { auth: { token } },
      join: jest.fn().mockResolvedValue(undefined),
      leave: jest.fn().mockResolvedValue(undefined),
      emit: jest.fn(),
      disconnect: jest.fn(function disconnect(this: { connected: boolean }) {
        this.connected = false;
      }),
    };
  }

  beforeEach(() => {
    jest.clearAllMocks();
    tokensMock.verifyAccess.mockReturnValue({
      sub: userId,
      sid: sessionId,
      typ: "access",
      exp: Math.floor(Date.now() / 1000) + 3600,
    });
    prismaMock.authSession.findFirst.mockResolvedValue({ id: sessionId });
    prismaMock.block.count.mockResolvedValue(0);
    prismaMock.friendship.findFirst.mockResolvedValue({ id: randomUUID() });
  });

  it("rejects a valid token whose server session is revoked", async () => {
    prismaMock.authSession.findFirst.mockResolvedValue(null);
    const client = socket();
    await gateway.handleConnection(client as never);
    expect(client.emit).toHaveBeenCalledWith("auth.error", {
      code: "unauthorized",
    });
    expect(client.disconnect).toHaveBeenCalledWith(true);
  });

  it("rejects malformed subscription identifiers before querying Prisma", async () => {
    const client = socket();
    Object.assign(client.data, { userId, sessionId, authenticated: true });
    await expect(
      gateway.subscribeConversation(client as never, {
        conversationId: "not-a-uuid",
      }),
    ).resolves.toEqual({ ok: false });
    expect(prismaMock.conversationMember.findFirst).not.toHaveBeenCalled();
  });

  it("does not subscribe a blocked direct-conversation member", async () => {
    const client = socket();
    Object.assign(client.data, { userId, sessionId, authenticated: true });
    prismaMock.conversationMember.findFirst.mockResolvedValue({
      conversation: {
        type: "DIRECT",
        members: [{ userId }, { userId: otherId }],
      },
    });
    prismaMock.block.count.mockResolvedValue(1);
    await expect(
      gateway.subscribeConversation(client as never, { conversationId }),
    ).resolves.toEqual({ ok: false });
    expect(client.join).not.toHaveBeenCalled();
  });

  it("fails closed when a subscription races the async handshake", async () => {
    let releaseSession!: (value: { id: string }) => void;
    prismaMock.authSession.findFirst.mockReturnValueOnce(
      new Promise((resolve) => {
        releaseSession = resolve;
      }),
    );
    const client = socket();
    const connecting = gateway.handleConnection(client as never);

    await expect(
      gateway.subscribeRoom(client as never, { roomId: randomUUID() }),
    ).resolves.toEqual({ ok: false });
    await expect(
      gateway.subscribeConversation(client as never, { conversationId }),
    ).resolves.toEqual({ ok: false });
    expect(prismaMock.roomMember.findFirst).not.toHaveBeenCalled();
    expect(prismaMock.conversationMember.findFirst).not.toHaveBeenCalled();
    expect(client.join).not.toHaveBeenCalled();

    releaseSession({ id: sessionId });
    await connecting;
    gateway.handleDisconnect(client as never);
  });

  it("does not subscribe a former friend to an archived direct conversation", async () => {
    const client = socket();
    Object.assign(client.data, { userId, sessionId, authenticated: true });
    prismaMock.conversationMember.findFirst.mockResolvedValue({
      conversation: {
        type: "DIRECT",
        members: [{ userId }, { userId: otherId }],
      },
    });
    prismaMock.friendship.findFirst.mockResolvedValue(null);

    await expect(
      gateway.subscribeConversation(client as never, { conversationId }),
    ).resolves.toEqual({ ok: false });
    expect(client.join).not.toHaveBeenCalled();
  });

  it("evicts every socket of a removed user from the conversation room", () => {
    const socketsLeave = jest.fn();
    const inRoom = jest.fn().mockReturnValue({ socketsLeave });
    gateway.server = { in: inRoom } as never;

    gateway.evictUserFromConversation(userId, conversationId);

    expect(inRoom).toHaveBeenCalledWith(`user:${userId}`);
    expect(socketsLeave).toHaveBeenCalledWith(`conversation:${conversationId}`);
  });

  it("periodically disconnects a socket after its session is revoked", async () => {
    jest.useFakeTimers();
    try {
      const client = socket();
      prismaMock.authSession.findFirst
        .mockResolvedValueOnce({ id: sessionId })
        .mockResolvedValueOnce(null);
      await gateway.handleConnection(client as never);
      await jest.advanceTimersByTimeAsync(60_000);
      expect(client.emit).toHaveBeenCalledWith("auth.error", {
        code: "session_revoked",
      });
      expect(client.disconnect).toHaveBeenCalledWith(true);
      gateway.handleDisconnect(client as never);
    } finally {
      jest.useRealTimers();
    }
  });
});
