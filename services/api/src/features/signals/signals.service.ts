import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../../common/audit.service";
import { ContentPolicyService } from "../../common/content-policy.service";
import { PrismaService } from "../../common/prisma.service";
import { RealtimeGateway } from "../../realtime/realtime.gateway";
import { SocialService } from "../social/social.service";
import type { CreateSignalDto, UpdateSignalDto } from "./signals.dto";

@Injectable()
export class SignalsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly social: SocialService,
    private readonly realtime: RealtimeGateway,
    private readonly content: ContentPolicyService,
    private readonly audit: AuditService,
  ) {}

  async create(userId: string, dto: CreateSignalDto) {
    const activeCount = await this.prisma.signal.count({
      where: {
        authorId: userId,
        createdAt: { gte: new Date(Date.now() - 3_600_000) },
      },
    });
    if (activeCount >= 8)
      throw new ForbiddenException("Слишком много сигналов");
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: { limitedMode: true },
    });
    if (dto.text) await this.content.assertAllowed(dto.text, user.limitedMode);
    if (!dto.circleIds.length && !dto.userIds.length)
      throw new BadRequestException("Выберите круг или друзей");
    if (
      dto.locationMode === "APPROXIMATE" &&
      (dto.latitude === undefined || dto.longitude === undefined)
    ) {
      throw new BadRequestException("Для приблизительной зоны нужна точка");
    }
    if (
      dto.locationMode !== "APPROXIMATE" &&
      (dto.latitude !== undefined || dto.longitude !== undefined)
    ) {
      throw new BadRequestException(
        "Координаты допустимы только для приблизительной зоны",
      );
    }
    await this.assertVisibility(userId, dto.circleIds, dto.userIds);
    const startsAt = new Date(dto.startsAt);
    const expiresAt = new Date(
      startsAt.getTime() + dto.durationMinutes * 60_000,
    );
    if (
      expiresAt <= new Date() ||
      expiresAt > new Date(Date.now() + 24 * 3_600_000)
    ) {
      throw new BadRequestException("Некорректный срок сигнала");
    }
    const signal = await this.prisma.signal.create({
      data: {
        authorId: userId,
        category: dto.category,
        text: dto.text?.trim(),
        emoji: dto.emoji,
        startsAt,
        expiresAt,
        format: dto.format,
        locationMode: dto.locationMode,
        cityLabel: dto.locationMode === "CITY" ? dto.cityLabel : null,
        districtLabel:
          dto.locationMode === "DISTRICT" ? dto.districtLabel : null,
        maxParticipants: dto.maxParticipants,
        visibility: {
          create: [
            ...[...new Set(dto.circleIds)].map((circleId) => ({ circleId })),
            ...[...new Set(dto.userIds)].map((targetId) => ({
              userId: targetId,
            })),
          ],
        },
        participants: { create: { userId } },
      },
      select: this.publicSelect(),
    });
    if (dto.locationMode === "APPROXIMATE") {
      const [safeLon, safeLat] = this.reducePrecision(
        dto.longitude!,
        dto.latitude!,
      );
      await this.prisma.$executeRawUnsafe(
        "UPDATE signals SET approximate_point = ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography WHERE id = $3::uuid",
        safeLon,
        safeLat,
        signal.id,
      );
    }
    const recipients = await this.visibilityRecipients(signal.id);
    this.realtime.emitUsers(recipients, "signal.created", {
      signalId: signal.id,
    });
    await this.audit.write({
      actorUserId: userId,
      action: "signal.created",
      resourceType: "signal",
      resourceId: signal.id,
    });
    return signal;
  }

  async feed(userId: string) {
    const blocked = await this.blockedIds(userId);
    return this.prisma.signal.findMany({
      where: {
        state: { in: ["ACTIVE", "FULL"] },
        expiresAt: { gt: new Date() },
        authorId: { notIn: blocked },
        OR: [
          { authorId: userId },
          { visibility: { some: { userId } } },
          {
            visibility: { some: { circle: { members: { some: { userId } } } } },
          },
        ],
      },
      select: this.publicSelect(),
      orderBy: [{ startsAt: "asc" }, { createdAt: "desc" }],
      take: 100,
    });
  }

  async get(userId: string, id: string) {
    const signal = await this.findVisible(userId, id);
    if (!signal) throw new NotFoundException("Сигнал не найден");
    return signal;
  }

  async update(userId: string, id: string, dto: UpdateSignalDto) {
    const signal = await this.prisma.signal.findFirst({
      where: { id, authorId: userId, state: "ACTIVE" },
      include: { _count: { select: { participants: true } } },
    });
    if (!signal) throw new NotFoundException("Сигнал не найден");
    if (signal._count.participants > 1)
      throw new ForbiddenException("После присоединения сигнал нельзя менять");
    if (dto.text) await this.content.assertAllowed(dto.text);
    const updated = await this.prisma.signal.update({
      where: { id },
      data: {
        text: dto.text?.trim(),
        startsAt: dto.startsAt ? new Date(dto.startsAt) : undefined,
        maxParticipants: dto.maxParticipants,
      },
      select: this.publicSelect(),
    });
    this.realtime.emitUsers(
      await this.visibilityRecipients(id),
      "signal.updated",
      { signalId: id },
    );
    return updated;
  }

  async join(userId: string, id: string) {
    const signal = await this.findVisible(userId, id);
    if (!signal || signal.authorId === userId)
      throw new NotFoundException("Сигнал не найден");
    if (signal.state !== "ACTIVE" || signal.expiresAt <= new Date())
      throw new BadRequestException("Сигнал уже недоступен");
    await this.prisma.signalJoinRequest.upsert({
      where: { signalId_userId: { signalId: id, userId } },
      create: { signalId: id, userId },
      update: { state: "PENDING" },
    });
    this.realtime.emitUser(signal.authorId, "join.requested", {
      signalId: id,
      userId,
    });
    return { state: "PENDING" };
  }

  async decide(
    userId: string,
    signalId: string,
    targetId: string,
    approved: boolean,
  ) {
    const signal = await this.prisma.signal.findFirst({
      where: {
        id: signalId,
        authorId: userId,
        state: { in: ["ACTIVE", "FULL"] },
      },
      include: { _count: { select: { participants: true } } },
    });
    if (!signal) throw new NotFoundException("Сигнал не найден");
    if (approved && signal._count.participants >= signal.maxParticipants)
      throw new BadRequestException("Нет свободных мест");
    const request = await this.prisma.signalJoinRequest.findUnique({
      where: { signalId_userId: { signalId, userId: targetId } },
    });
    if (!request || request.state !== "PENDING")
      throw new NotFoundException("Запрос не найден");
    let roomId: string | undefined;
    await this.prisma.$transaction(async (tx) => {
      await tx.signalJoinRequest.update({
        where: { signalId_userId: { signalId, userId: targetId } },
        data: { state: approved ? "APPROVED" : "REJECTED" },
      });
      if (approved) {
        await tx.signalParticipant.upsert({
          where: { signalId_userId: { signalId, userId: targetId } },
          create: { signalId, userId: targetId },
          update: {},
        });
        const room = await tx.temporaryRoom.upsert({
          where: { signalId },
          create: {
            signalId,
            ownerId: userId,
            title: signal.category,
            scheduledAt: signal.startsAt,
            expiresAt: signal.expiresAt,
            members: { create: [{ userId }, { userId: targetId }] },
          },
          update: {},
        });
        roomId = room.id;
        await tx.roomMember.upsert({
          where: { roomId_userId: { roomId: room.id, userId: targetId } },
          create: { roomId: room.id, userId: targetId },
          update: { leftAt: null },
        });
        if (signal._count.participants + 1 >= signal.maxParticipants) {
          await tx.signal.update({
            where: { id: signalId },
            data: { state: "FULL" },
          });
        }
      }
    });
    const event = approved ? "join.approved" : "join.rejected";
    this.realtime.emitUser(targetId, event, {
      signalId,
      ...(roomId && { roomId }),
    });
    return { state: approved ? "APPROVED" : "REJECTED", roomId };
  }

  async cancel(userId: string, id: string) {
    const result = await this.prisma.signal.updateMany({
      where: { id, authorId: userId, state: { in: ["ACTIVE", "FULL"] } },
      data: { state: "CANCELLED" },
    });
    if (!result.count) throw new NotFoundException("Сигнал не найден");
    await this.prisma.locationShare.deleteMany({
      where: { room: { signalId: id } },
    });
    this.realtime.emitUsers(
      await this.visibilityRecipients(id),
      "signal.cancelled",
      { signalId: id },
    );
    return { success: true };
  }

  async complete(userId: string, id: string) {
    const signal = await this.prisma.signal.findFirst({
      where: { id, authorId: userId },
      include: { room: true },
    });
    if (!signal) throw new NotFoundException("Сигнал не найден");
    await this.prisma.$transaction(async (tx) => {
      await tx.signal.update({ where: { id }, data: { state: "COMPLETED" } });
      if (signal.room) {
        await tx.locationShare.deleteMany({
          where: { roomId: signal.room.id },
        });
        await tx.temporaryRoom.update({
          where: { id: signal.room.id },
          data: { state: "COMPLETED", completedAt: new Date() },
        });
      }
    });
    if (signal.room)
      this.realtime.emitRoom(signal.room.id, "room.completed", {
        roomId: signal.room.id,
      });
    return { success: true };
  }

  private async findVisible(userId: string, id: string) {
    const blocked = await this.blockedIds(userId);
    return this.prisma.signal.findFirst({
      where: {
        id,
        authorId: { notIn: blocked },
        OR: [
          { authorId: userId },
          { visibility: { some: { userId } } },
          {
            visibility: { some: { circle: { members: { some: { userId } } } } },
          },
        ],
      },
      select: this.publicSelect(),
    });
  }

  private async assertVisibility(
    ownerId: string,
    circleIds: string[],
    userIds: string[],
  ) {
    const circles = await this.prisma.circle.count({
      where: { id: { in: circleIds }, ownerId },
    });
    if (circles !== new Set(circleIds).size)
      throw new ForbiddenException("Недоступный круг");
    const friendChecks = await Promise.all(
      [...new Set(userIds)].map((id) => this.social.areFriends(ownerId, id)),
    );
    if (friendChecks.some((value) => !value))
      throw new ForbiddenException(
        "Сигнал можно показать только взаимным друзьям",
      );
  }

  private async visibilityRecipients(signalId: string): Promise<string[]> {
    const visibility = await this.prisma.signalVisibility.findMany({
      where: { signalId },
      include: {
        circle: { include: { members: { select: { userId: true } } } },
      },
    });
    return visibility
      .flatMap((item) => [
        item.userId,
        ...(item.circle?.members.map((member) => member.userId) ?? []),
      ])
      .filter((id): id is string => Boolean(id));
  }

  private async blockedIds(userId: string) {
    const blocks = await this.prisma.block.findMany({
      where: { OR: [{ blockerId: userId }, { blockedId: userId }] },
      select: { blockerId: true, blockedId: true },
    });
    return blocks.map((block) =>
      block.blockerId === userId ? block.blockedId : block.blockerId,
    );
  }

  private reducePrecision(
    longitude: number,
    latitude: number,
  ): [number, number] {
    const grid = 0.02;
    return [
      Math.round(longitude / grid) * grid,
      Math.round(latitude / grid) * grid,
    ];
  }

  private publicSelect() {
    return {
      id: true,
      authorId: true,
      category: true,
      text: true,
      emoji: true,
      startsAt: true,
      expiresAt: true,
      format: true,
      locationMode: true,
      cityLabel: true,
      districtLabel: true,
      maxParticipants: true,
      state: true,
      createdAt: true,
      author: {
        select: {
          profile: {
            select: { displayName: true, emoji: true, avatarMediaId: true },
          },
        },
      },
      _count: { select: { participants: true, joinRequests: true } },
    } as const;
  }
}
