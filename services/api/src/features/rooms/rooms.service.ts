import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../../common/audit.service";
import { ContentPolicyService } from "../../common/content-policy.service";
import { CryptoService } from "../../common/crypto.service";
import { PrismaService } from "../../common/prisma.service";
import { RealtimeGateway } from "../../realtime/realtime.gateway";
import type { CreatePollDto, ShareLocationDto } from "./rooms.dto";

@Injectable()
export class RoomsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly crypto: CryptoService,
    private readonly audit: AuditService,
    private readonly content: ContentPolicyService,
    private readonly realtime: RealtimeGateway,
  ) {}

  async get(userId: string, roomId: string) {
    const room = await this.assertMember(userId, roomId);
    const shares = await this.prisma.locationShare.findMany({
      where: {
        roomId,
        expiresAt: { gt: new Date() },
        owner: {
          blocksCreated: { none: { blockedId: userId } },
          blocksReceived: { none: { blockerId: userId } },
        },
      },
    });
    const locations = shares.map((share) => ({
      id: share.id,
      ownerId: share.ownerId,
      expiresAt: share.expiresAt,
      value: this.crypto.envelopeDecrypt({
        ciphertext: share.ciphertext,
        iv: share.iv,
        authTag: share.authTag,
        encryptedDataKey: share.encryptedDataKey,
        keyIv: share.keyIv,
        keyAuthTag: share.keyAuthTag,
      }),
    }));
    await Promise.all(
      shares.map((share) =>
        this.audit.write({
          actorUserId: userId,
          action: "location.exact_read",
          resourceType: "location_share",
          resourceId: share.id,
          metadata: { roomId },
        }),
      ),
    );
    return { ...room, locationShares: locations };
  }

  async messages(userId: string, roomId: string) {
    await this.assertMember(userId, roomId);
    return this.prisma.roomMessage.findMany({
      where: { roomId, deletedAt: null },
      select: {
        id: true,
        authorId: true,
        body: true,
        system: true,
        createdAt: true,
        reactions: { select: { userId: true, emoji: true } },
      },
      orderBy: { createdAt: "desc" },
      take: 100,
    });
  }

  async createMessage(userId: string, roomId: string, body: string) {
    const room = await this.assertMember(userId, roomId);
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: { limitedMode: true },
    });
    await this.content.assertAllowed(body, user.limitedMode);
    const recent = await this.prisma.roomMessage.count({
      where: {
        authorId: userId,
        createdAt: { gte: new Date(Date.now() - 60_000) },
      },
    });
    if (recent >= 20) throw new ForbiddenException("Слишком много сообщений");
    const message = await this.prisma.roomMessage.create({
      data: { roomId, authorId: userId, body: body.trim() },
      select: { id: true, authorId: true, body: true, createdAt: true },
    });
    this.realtime.emitRoom(room.id, "room.message.created", { message });
    return message;
  }

  async leave(userId: string, roomId: string) {
    await this.assertMember(userId, roomId);
    await this.prisma.$transaction([
      this.prisma.roomMember.update({
        where: { roomId_userId: { roomId, userId } },
        data: { leftAt: new Date() },
      }),
      this.prisma.locationShare.deleteMany({
        where: { roomId, ownerId: userId },
      }),
    ]);
    this.realtime.emitRoom(roomId, "room.member.left", { roomId, userId });
    return { success: true };
  }

  async toggleReaction(
    userId: string,
    roomId: string,
    messageId: string,
    emoji: string,
  ) {
    await this.assertMember(userId, roomId);
    const message = await this.prisma.roomMessage.findFirst({
      where: { id: messageId, roomId, deletedAt: null },
      select: { id: true },
    });
    if (!message) throw new NotFoundException("Сообщение недоступно");

    const key = { messageId_userId_emoji: { messageId, userId, emoji } };
    const existing = await this.prisma.roomReaction.findUnique({ where: key });
    if (existing) {
      await this.prisma.roomReaction.delete({ where: key });
    } else {
      await this.prisma.roomReaction.create({
        data: { messageId, userId, emoji },
      });
    }
    const payload = { messageId, userId, emoji, active: !existing };
    this.realtime.emitRoom(roomId, "room.reaction.updated", payload);
    return payload;
  }

  async createPoll(userId: string, roomId: string, dto: CreatePollDto) {
    await this.assertMember(userId, roomId);
    const existing = await this.prisma.roomPoll.count({ where: { roomId } });
    if (existing)
      throw new BadRequestException(
        "В MVP доступно одно голосование на комнату",
      );
    const unique = [
      ...new Set(dto.options.map((option) => option.trim())),
    ].filter(Boolean);
    if (unique.length < 2)
      throw new BadRequestException("Нужно минимум два разных варианта");
    const poll = await this.prisma.roomPoll.create({
      data: {
        roomId,
        question: dto.question.trim(),
        closesAt: dto.closesAt ? new Date(dto.closesAt) : null,
        options: {
          create: unique.map((label, position) => ({
            label: label.slice(0, 100),
            position,
          })),
        },
      },
      include: { options: true },
    });
    this.realtime.emitRoom(roomId, "room.poll.updated", { pollId: poll.id });
    return poll;
  }

  async vote(userId: string, roomId: string, pollId: string, optionId: string) {
    await this.assertMember(userId, roomId);
    const option = await this.prisma.roomPollOption.findFirst({
      where: {
        id: optionId,
        pollId,
        poll: {
          roomId,
          OR: [{ closesAt: null }, { closesAt: { gt: new Date() } }],
        },
      },
    });
    if (!option) throw new NotFoundException("Вариант голосования недоступен");
    await this.prisma.$transaction(async (tx) => {
      await tx.roomPollVote.deleteMany({
        where: { userId, option: { pollId } },
      });
      await tx.roomPollVote.create({
        data: { userId, pollOptionId: optionId },
      });
    });
    this.realtime.emitRoom(roomId, "room.poll.updated", { pollId });
    return { success: true };
  }

  async shareLocation(userId: string, roomId: string, dto: ShareLocationDto) {
    if (!dto.explicitConsent)
      throw new BadRequestException("Нужно явное подтверждение");
    const room = await this.assertMember(userId, roomId);
    const requestedExpiry = new Date(Date.now() + dto.ttlMinutes * 60_000);
    const expiresAt =
      requestedExpiry < room.expiresAt ? requestedExpiry : room.expiresAt;
    const encrypted = this.crypto.envelopeEncrypt({
      latitude: dto.latitude,
      longitude: dto.longitude,
      label: dto.label?.slice(0, 120),
    });
    const share = await this.prisma.locationShare.upsert({
      where: { roomId_ownerId: { roomId, ownerId: userId } },
      create: { roomId, ownerId: userId, expiresAt, ...encrypted },
      update: { expiresAt, ...encrypted },
      select: { id: true, ownerId: true, expiresAt: true },
    });
    await this.audit.write({
      actorUserId: userId,
      action: "location.exact_shared",
      resourceType: "location_share",
      resourceId: share.id,
      metadata: { roomId },
    });
    this.realtime.emitRoom(roomId, "location.share.updated", {
      ownerId: userId,
      expiresAt,
    });
    return share;
  }

  async revokeLocation(userId: string, roomId: string) {
    const result = await this.prisma.locationShare.deleteMany({
      where: { roomId, ownerId: userId },
    });
    await this.audit.write({
      actorUserId: userId,
      action: "location.exact_revoked",
      resourceType: "temporary_room",
      resourceId: roomId,
    });
    if (result.count)
      this.realtime.emitRoom(roomId, "location.share.revoked", {
        ownerId: userId,
      });
    return { success: true };
  }

  private async assertMember(userId: string, roomId: string) {
    const room = await this.prisma.temporaryRoom.findFirst({
      where: {
        id: roomId,
        state: "ACTIVE",
        expiresAt: { gt: new Date() },
        members: { some: { userId, leftAt: null } },
      },
      include: {
        members: {
          where: { leftAt: null },
          select: { userId: true, joinedAt: true, mutedUntil: true },
        },
        polls: {
          include: {
            options: { include: { _count: { select: { votes: true } } } },
          },
        },
      },
    });
    if (!room) throw new ForbiddenException("Нет доступа к комнате");
    return room;
  }
}
