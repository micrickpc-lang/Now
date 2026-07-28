import { forwardRef, Inject, Injectable, Logger } from "@nestjs/common";
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
import { ConversationsService } from "../features/conversations/conversations.service";
import { RoomsService } from "../features/rooms/rooms.service";

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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" && isUUID(value);
}

function isBoundedString(
  value: unknown,
  minLength: number,
  maxLength: number,
): value is string {
  return (
    typeof value === "string" &&
    value.length >= minLength &&
    value.length <= maxLength
  );
}

function isMessageMetadata(
  value: unknown,
): value is Record<string, string | number | boolean | null> {
  return (
    isRecord(value) &&
    Object.values(value).every(
      (entry) =>
        entry === null ||
        typeof entry === "string" ||
        typeof entry === "number" ||
        typeof entry === "boolean",
    )
  );
}

function isLatitude(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isFinite(value) &&
    value >= -90 &&
    value <= 90
  );
}

function isLongitude(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isFinite(value) &&
    value >= -180 &&
    value <= 180
  );
}

function isTtlMinutes(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isInteger(value) &&
    value >= 5 &&
    value <= 180
  );
}

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
    @Inject(forwardRef(() => ConversationsService))
    private readonly conversations: ConversationsService,
    @Inject(forwardRef(() => RoomsService))
    private readonly rooms: RoomsService,
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

  @SubscribeMessage("message.send")
  async sendMessage(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() body: unknown,
  ) {
    return this.runAuthenticated(socket, async () => {
      if (
        !isRecord(body) ||
        !isUuid(body.conversationId) ||
        !isUuid(body.clientMessageId)
      )
        return { ok: false };
      const type = body.type ?? "TEXT";
      if (type !== "TEXT" && type !== "SIGNAL") return { ok: false };
      if (type === "TEXT" && !isBoundedString(body.text, 1, 4000))
        return { ok: false };
      if (
        type === "SIGNAL" &&
        (!isRecord(body.metadata) || !isUuid(body.metadata.signalId))
      )
        return { ok: false };
      if (
        (body.replyToMessageId !== undefined &&
          !isUuid(body.replyToMessageId)) ||
        (body.forwardedFromMessageId !== undefined &&
          !isUuid(body.forwardedFromMessageId))
      )
        return { ok: false };
      const message = await this.conversations.createMessage(
        socket.data.userId,
        body.conversationId,
        {
          clientMessageId: body.clientMessageId,
          type,
          ...(typeof body.text === "string" && { text: body.text }),
          ...(isMessageMetadata(body.metadata) && { metadata: body.metadata }),
          ...(typeof body.replyToMessageId === "string" && {
            replyToMessageId: body.replyToMessageId,
          }),
          ...(typeof body.forwardedFromMessageId === "string" && {
            forwardedFromMessageId: body.forwardedFromMessageId,
          }),
        },
      );
      return { ok: true, message };
    });
  }

  @SubscribeMessage("message.edit")
  async editMessage(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() body: unknown,
  ) {
    return this.runAuthenticated(socket, async () => {
      if (
        !isRecord(body) ||
        !isUuid(body.messageId) ||
        !isBoundedString(body.text, 1, 4000)
      )
        return { ok: false };
      return {
        ok: true,
        message: await this.conversations.editMessage(
          socket.data.userId,
          body.messageId,
          body.text,
        ),
      };
    });
  }

  @SubscribeMessage("message.delete")
  async deleteMessage(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() body: unknown,
  ) {
    return this.runAuthenticated(socket, async () => {
      if (
        !isRecord(body) ||
        !isUuid(body.messageId) ||
        (body.mode !== "SELF" && body.mode !== "EVERYONE")
      )
        return { ok: false };
      return {
        ok: true,
        message: await this.conversations.deleteMessage(
          socket.data.userId,
          body.messageId,
          body.mode,
        ),
      };
    });
  }

  @SubscribeMessage("message.reaction.add")
  async addReaction(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() body: unknown,
  ) {
    return this.runAuthenticated(socket, async () => {
      if (
        !isRecord(body) ||
        !isUuid(body.messageId) ||
        !isBoundedString(body.reaction, 1, 32)
      )
        return { ok: false };
      return {
        ok: true,
        reaction: await this.conversations.addReaction(
          socket.data.userId,
          body.messageId,
          body.reaction,
        ),
      };
    });
  }

  @SubscribeMessage("message.reaction.remove")
  async removeReaction(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() body: unknown,
  ) {
    return this.runAuthenticated(socket, async () => {
      if (
        !isRecord(body) ||
        !isUuid(body.messageId) ||
        !isBoundedString(body.reaction, 1, 32)
      )
        return { ok: false };
      return {
        ok: true,
        result: await this.conversations.removeReaction(
          socket.data.userId,
          body.messageId,
          body.reaction,
        ),
      };
    });
  }

  @SubscribeMessage("message.read")
  async markRead(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() body: unknown,
  ) {
    return this.runAuthenticated(socket, async () => {
      if (!isRecord(body) || !isUuid(body.messageId)) return { ok: false };
      return {
        ok: true,
        result: await this.conversations.markRead(
          socket.data.userId,
          body.messageId,
        ),
      };
    });
  }

  @SubscribeMessage("conversation.typing")
  async setTyping(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() body: unknown,
  ) {
    return this.runAuthenticated(socket, async () => {
      if (
        !isRecord(body) ||
        !isUuid(body.conversationId) ||
        typeof body.active !== "boolean"
      )
        return { ok: false };
      return {
        ok: true,
        result: await this.conversations.typing(
          socket.data.userId,
          body.conversationId,
          body.active,
        ),
      };
    });
  }

  @SubscribeMessage("room.location.share")
  async shareRoomLocation(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() body: unknown,
  ) {
    return this.runAuthenticated(socket, async () => {
      if (
        !isRecord(body) ||
        !isUuid(body.roomId) ||
        !isLatitude(body.latitude) ||
        !isLongitude(body.longitude) ||
        !isTtlMinutes(body.ttlMinutes) ||
        body.explicitConsent !== true ||
        (body.label !== undefined && !isBoundedString(body.label, 0, 120))
      )
        return { ok: false };
      return {
        ok: true,
        share: await this.rooms.shareLocation(socket.data.userId, body.roomId, {
          latitude: body.latitude,
          longitude: body.longitude,
          ttlMinutes: body.ttlMinutes,
          explicitConsent: true,
          ...(typeof body.label === "string" && { label: body.label }),
        }),
      };
    });
  }

  @SubscribeMessage("room.location.revoke")
  async revokeRoomLocation(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() body: unknown,
  ) {
    return this.runAuthenticated(socket, async () => {
      if (!isRecord(body) || !isUuid(body.roomId)) return { ok: false };
      return {
        ok: true,
        result: await this.rooms.revokeLocation(
          socket.data.userId,
          body.roomId,
        ),
      };
    });
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

  evictUserFromRoom(userId: string, roomId: string) {
    this.server.in(`user:${userId}`).socketsLeave(`room:${roomId}`);
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

  private async runAuthenticated(
    socket: AuthenticatedSocket,
    action: () => Promise<Record<string, unknown>>,
  ) {
    if (!this.isAuthenticated(socket) || !this.assertRate(socket))
      return { ok: false };
    try {
      return await action();
    } catch (error) {
      this.logger.debug(
        `Realtime command rejected for user ${socket.data.userId}: ${error instanceof Error ? error.name : "unknown"}`,
      );
      return { ok: false };
    }
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
