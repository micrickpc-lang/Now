import { Injectable, Logger } from "@nestjs/common";
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from "@nestjs/websockets";
import { randomUUID } from "node:crypto";
import type { Server, Socket } from "socket.io";
import { PrismaService } from "../common/prisma.service";
import { TokenService } from "../features/auth/token.service";

interface AuthenticatedSocket extends Socket {
  data: {
    userId: string;
    sessionId: string;
    messageWindow?: { started: number; count: number };
  };
}

@Injectable()
@WebSocketGateway({
  namespace: "/realtime",
  cors: { origin: false },
  transports: ["websocket"],
})
export class RealtimeGateway implements OnGatewayConnection {
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(RealtimeGateway.name);
  private sequence = 0;

  constructor(
    private readonly tokens: TokenService,
    private readonly prisma: PrismaService,
  ) {}

  async handleConnection(socket: AuthenticatedSocket) {
    try {
      const raw: unknown = (
        socket.handshake.auth as Record<string, unknown> | undefined
      )?.token;
      if (typeof raw !== "string") throw new Error("Missing token");
      const payload = this.tokens.verifyAccess(raw);
      const session = await this.prisma.authSession.findFirst({
        where: {
          id: payload.sid,
          userId: payload.sub,
          revokedAt: null,
          expiresAt: { gt: new Date() },
        },
      });
      if (!session) throw new Error("Session revoked");
      socket.data.userId = payload.sub;
      socket.data.sessionId = payload.sid;
      await socket.join(`user:${payload.sub}`);
      socket.emit("ready", { heartbeatSeconds: 25 });
    } catch {
      socket.emit("auth.error", { code: "unauthorized" });
      socket.disconnect(true);
    }
  }

  @SubscribeMessage("room.subscribe")
  async subscribeRoom(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() body: { roomId?: string },
  ) {
    this.assertRate(socket);
    if (!body.roomId) return { ok: false };
    const member = await this.prisma.roomMember.findFirst({
      where: {
        roomId: body.roomId,
        userId: socket.data.userId,
        leftAt: null,
        room: { state: "ACTIVE" },
      },
    });
    if (!member) return { ok: false };
    await socket.join(`room:${body.roomId}`);
    return { ok: true };
  }

  @SubscribeMessage("heartbeat")
  heartbeat(@ConnectedSocket() socket: AuthenticatedSocket) {
    this.assertRate(socket);
    return { serverTime: new Date().toISOString() };
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

  private envelope(payload: Record<string, unknown>) {
    this.sequence += 1;
    return {
      id: randomUUID(),
      sequence: this.sequence,
      occurredAt: new Date().toISOString(),
      payload,
    };
  }

  private assertRate(socket: AuthenticatedSocket) {
    const now = Date.now();
    const window = socket.data.messageWindow;
    if (!window || now - window.started > 10_000) {
      socket.data.messageWindow = { started: now, count: 1 };
      return;
    }
    window.count += 1;
    if (window.count > 60) {
      this.logger.warn(
        `WebSocket rate limit exceeded by user ${socket.data.userId}`,
      );
      socket.disconnect(true);
    }
  }
}
