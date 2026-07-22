import { Injectable, Logger } from "@nestjs/common";
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from "@nestjs/websockets";
import { randomUUID } from "node:crypto";
import type { Server, Socket } from "socket.io";
import { isUUID } from "class-validator";
import { PrismaService } from "../common/prisma.service";
import { TokenService } from "../features/auth/token.service";

interface AuthenticatedSocket extends Socket {
  data: {
    userId: string;
    sessionId: string;
    authenticated?: boolean;
    messageWindow?: { started: number; count: number };
    accessExpiryTimer?: ReturnType<typeof setTimeout>;
    sessionCheckTimer?: ReturnType<typeof setInterval>;
  };
}

const SESSION_RECHECK_MS = 60_000;

@Injectable()
@WebSocketGateway({
  namespace: "/realtime",
  cors: { origin: false },
  transports: ["websocket"],
})
export class RealtimeGateway
  implements OnGatewayConnection, OnGatewayDisconnect
{
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(RealtimeGateway.name);
  private sequence = 0;

  constructor(
    private readonly tokens: TokenService,
    private readonly prisma: PrismaService,
  ) {}

  async handleConnection(socket: AuthenticatedSocket) {
    // Socket.IO does not await this async hook before it can dispatch incoming
    // events. Every message handler therefore treats the socket as untrusted
    // until the server-side session check has completed.
    socket.data.authenticated = false;
    try {
      const raw: unknown = (
        socket.handshake.auth as Record<string, unknown> | undefined
      )?.token;
      if (typeof raw !== "string") throw new Error("Missing token");
      const payload = this.tokens.verifyAccess(raw);
      if (!(await this.isSessionActive(payload.sid, payload.sub)))
        throw new Error("Session revoked");
      if (!socket.connected) throw new Error("Socket disconnected");
      socket.data.userId = payload.sub;
      socket.data.sessionId = payload.sid;
      await socket.join(`user:${payload.sub}`);
      this.armSocketSecurity(socket, payload.exp);
      socket.data.authenticated = true;
      socket.emit("ready", { heartbeatSeconds: 25 });
    } catch {
      socket.data.authenticated = false;
      socket.emit("auth.error", { code: "unauthorized" });
      socket.disconnect(true);
    }
  }

  handleDisconnect(socket: AuthenticatedSocket) {
    socket.data.authenticated = false;
    this.clearSocketSecurity(socket);
  }

  @SubscribeMessage("room.subscribe")
  async subscribeRoom(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() body: { roomId?: string },
  ) {
    if (!this.isAuthenticated(socket)) return { ok: false };
    if (!this.assertRate(socket)) return { ok: false };
    const roomId = body?.roomId;
    if (typeof roomId !== "string" || !isUUID(roomId)) return { ok: false };
    const member = await this.prisma.roomMember.findFirst({
      where: {
        roomId,
        userId: socket.data.userId,
        leftAt: null,
        room: { state: "ACTIVE" },
      },
    });
    if (!member) return { ok: false };
    await socket.join(`room:${roomId}`);
    return { ok: true };
  }

  @SubscribeMessage("room.unsubscribe")
  async unsubscribeRoom(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() body: { roomId?: string },
  ) {
    if (!this.isAuthenticated(socket)) return { ok: false };
    if (!this.assertRate(socket)) return { ok: false };
    const roomId = body?.roomId;
    if (typeof roomId !== "string" || !isUUID(roomId)) return { ok: false };
    await socket.leave(`room:${roomId}`);
    return { ok: true };
  }

  @SubscribeMessage("heartbeat")
  heartbeat(@ConnectedSocket() socket: AuthenticatedSocket) {
    if (!this.isAuthenticated(socket)) return { ok: false };
    if (!this.assertRate(socket)) return { ok: false };
    return { serverTime: new Date().toISOString() };
  }

  @SubscribeMessage("conversation.subscribe")
  async subscribeConversation(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() body: { conversationId?: string },
  ) {
    if (!this.isAuthenticated(socket)) return { ok: false };
    if (!this.assertRate(socket)) return { ok: false };
    const conversationId = body?.conversationId;
    if (typeof conversationId !== "string" || !isUUID(conversationId))
      return { ok: false };
    const member = await this.prisma.conversationMember.findFirst({
      where: {
        conversationId,
        userId: socket.data.userId,
        leftAt: null,
        conversation: { deletedAt: null },
      },
      include: {
        conversation: {
          select: {
            type: true,
            members: {
              where: { leftAt: null },
              select: { userId: true },
            },
          },
        },
      },
    });
    if (!member) return { ok: false };
    if (member.conversation.type === "DIRECT") {
      const otherIds = member.conversation.members
        .map(({ userId }) => userId)
        .filter((userId) => userId !== socket.data.userId);
      if (otherIds.length !== 1) return { ok: false };
      const otherId = otherIds[0];
      const [left, right] =
        socket.data.userId < otherId
          ? [socket.data.userId, otherId]
          : [otherId, socket.data.userId];
      const [blocked, friendship] = await Promise.all([
        this.prisma.block.count({
          where: {
            OR: [
              { blockerId: socket.data.userId, blockedId: otherId },
              { blockerId: otherId, blockedId: socket.data.userId },
            ],
          },
        }),
        this.prisma.friendship.findFirst({
          where: { userAId: left, userBId: right, status: "ACCEPTED" },
          select: { id: true },
        }),
      ]);
      if (blocked || !friendship) return { ok: false };
    }
    await socket.join(`conversation:${conversationId}`);
    return { ok: true };
  }

  @SubscribeMessage("conversation.unsubscribe")
  async unsubscribeConversation(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() body: { conversationId?: string },
  ) {
    if (!this.isAuthenticated(socket)) return { ok: false };
    if (!this.assertRate(socket)) return { ok: false };
    const conversationId = body?.conversationId;
    if (typeof conversationId !== "string" || !isUUID(conversationId))
      return { ok: false };
    await socket.leave(`conversation:${conversationId}`);
    return { ok: true };
  }

  emitUser(userId: string, event: string, payload: Record<string, unknown>) {
    this.server.to(`user:${userId}`).emit(event, this.envelope(payload));
  }

  emitUsers(
    userIds: string[],
    event: string,
    payload: Record<string, unknown>,
  ) {
    for (const id of new Set(userIds)) this.emitUser(id, event, payload);
  }

  emitRoom(roomId: string, event: string, payload: Record<string, unknown>) {
    this.server.to(`room:${roomId}`).emit(event, this.envelope(payload));
  }

  emitConversation(
    conversationId: string,
    event: string,
    payload: Record<string, unknown>,
  ) {
    this.server
      .to(`conversation:${conversationId}`)
      .emit(event, this.envelope(payload));
  }

  evictUserFromConversation(userId: string, conversationId: string) {
    this.server
      .in(`user:${userId}`)
      .socketsLeave(`conversation:${conversationId}`);
  }

  private envelope(payload: Record<string, unknown>) {
    this.sequence += 1;
    return {
      id: randomUUID(),
      sequence: this.sequence,
      occurredAt: new Date().toISOString(),
      payload,
    };
  }

  private assertRate(socket: AuthenticatedSocket): boolean {
    const now = Date.now();
    const window = socket.data.messageWindow;
    if (!window || now - window.started > 10_000) {
      socket.data.messageWindow = { started: now, count: 1 };
      return true;
    }
    window.count += 1;
    if (window.count > 60) {
      this.logger.warn(
        `WebSocket rate limit exceeded by user ${socket.data.userId}`,
      );
      socket.disconnect(true);
      return false;
    }
    return true;
  }

  private isAuthenticated(socket: AuthenticatedSocket): boolean {
    return (
      socket.data.authenticated === true &&
      typeof socket.data.userId === "string" &&
      isUUID(socket.data.userId) &&
      typeof socket.data.sessionId === "string" &&
      isUUID(socket.data.sessionId)
    );
  }

  private async isSessionActive(sessionId: string, userId: string) {
    return Boolean(
      await this.prisma.authSession.findFirst({
        where: {
          id: sessionId,
          userId,
          revokedAt: null,
          expiresAt: { gt: new Date() },
          user: { status: "ACTIVE" },
        },
        select: { id: true },
      }),
    );
  }

  private armSocketSecurity(socket: AuthenticatedSocket, expiresAt: number) {
    this.clearSocketSecurity(socket);
    const expiryDelay = Math.max(1, expiresAt * 1000 - Date.now());
    socket.data.accessExpiryTimer = setTimeout(
      () => this.rejectSocket(socket, "access_expired"),
      expiryDelay,
    );
    socket.data.accessExpiryTimer.unref();
    socket.data.sessionCheckTimer = setInterval(
      () => void this.revalidateSocket(socket),
      SESSION_RECHECK_MS,
    );
    socket.data.sessionCheckTimer.unref();
  }

  private async revalidateSocket(socket: AuthenticatedSocket) {
    if (!socket.connected) {
      this.clearSocketSecurity(socket);
      return;
    }
    try {
      if (
        !(await this.isSessionActive(socket.data.sessionId, socket.data.userId))
      ) {
        this.rejectSocket(socket, "session_revoked");
      }
    } catch (error) {
      this.logger.warn(
        `WebSocket session recheck failed: ${error instanceof Error ? error.message : "unknown error"}`,
      );
    }
  }

  private rejectSocket(socket: AuthenticatedSocket, code: string) {
    socket.data.authenticated = false;
    this.clearSocketSecurity(socket);
    socket.emit("auth.error", { code });
    socket.disconnect(true);
  }

  private clearSocketSecurity(socket: AuthenticatedSocket) {
    if (socket.data.accessExpiryTimer)
      clearTimeout(socket.data.accessExpiryTimer);
    if (socket.data.sessionCheckTimer)
      clearInterval(socket.data.sessionCheckTimer);
    socket.data.accessExpiryTimer = undefined;
    socket.data.sessionCheckTimer = undefined;
  }
}
