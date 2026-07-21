import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../../common/audit.service";
import { CryptoService } from "../../common/crypto.service";
import { PrismaService } from "../../common/prisma.service";
import type { CreateCircleDto, UpdateCircleDto } from "./social.dto";

function canonicalPair(left: string, right: string): [string, string] {
  return left < right ? [left, right] : [right, left];
}

@Injectable()
export class SocialService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly crypto: CryptoService,
    private readonly audit: AuditService,
  ) {}

  async createInvite(userId: string) {
    const activeCount = await this.prisma.friendshipInvite.count({
      where: {
        creatorId: userId,
        createdAt: { gte: new Date(Date.now() - 3_600_000) },
      },
    });
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: { limitedMode: true },
    });
    if (activeCount >= (user.limitedMode ? 3 : 10))
      throw new ForbiddenException("Лимит приглашений исчерпан");
    const token = this.crypto.randomToken(32);
    const shortCode = this.crypto
      .randomToken(6)
      .replace(/[-_]/g, "A")
      .slice(0, 8)
      .toUpperCase();
    const invite = await this.prisma.friendshipInvite.create({
      data: {
        creatorId: userId,
        tokenHash: this.crypto.hashToken(token),
        shortCode,
        expiresAt: new Date(Date.now() + 24 * 3_600_000),
      },
      select: { id: true, shortCode: true, expiresAt: true },
    });
    await this.audit.write({
      actorUserId: userId,
      action: "friend.invite_created",
      resourceType: "friendship_invite",
      resourceId: invite.id,
    });
    return {
      ...invite,
      token,
      deepLink: `https://join.example.invalid/i/${token}`,
    };
  }

  async acceptInvite(userId: string, tokenOrCode: string) {
    const invite = await this.prisma.friendshipInvite.findFirst({
      where: {
        OR: [
          { tokenHash: this.crypto.hashToken(tokenOrCode) },
          { shortCode: tokenOrCode.toUpperCase() },
        ],
        consumedAt: null,
        expiresAt: { gt: new Date() },
      },
    });
    if (!invite) throw new NotFoundException("Приглашение недействительно");
    if (invite.creatorId === userId)
      throw new BadRequestException("Нельзя принять собственное приглашение");
    const [userAId, userBId] = canonicalPair(invite.creatorId, userId);
    await this.prisma.$transaction(async (tx) => {
      const consumed = await tx.friendshipInvite.updateMany({
        where: { id: invite.id, consumedAt: null },
        data: { consumedAt: new Date(), consumedById: userId },
      });
      if (!consumed.count)
        throw new BadRequestException("Приглашение уже использовано");
      await tx.friendship.upsert({
        where: { userAId_userBId: { userAId, userBId } },
        create: {
          userAId,
          userBId,
          requestedById: invite.creatorId,
          status: "ACCEPTED",
        },
        update: { status: "ACCEPTED", requestedById: invite.creatorId },
      });
    });
    return { success: true };
  }

  async listFriends(userId: string) {
    const rows = await this.prisma.friendship.findMany({
      where: {
        status: "ACCEPTED",
        OR: [{ userAId: userId }, { userBId: userId }],
      },
      include: {
        userA: {
          select: {
            id: true,
            profile: {
              select: { displayName: true, emoji: true, avatarMediaId: true },
            },
          },
        },
        userB: {
          select: {
            id: true,
            profile: {
              select: { displayName: true, emoji: true, avatarMediaId: true },
            },
          },
        },
      },
      orderBy: { updatedAt: "desc" },
    });
    return rows.map((row) => (row.userAId === userId ? row.userB : row.userA));
  }

  async removeFriend(userId: string, otherId: string) {
    const [userAId, userBId] = canonicalPair(userId, otherId);
    await this.prisma.friendship.deleteMany({ where: { userAId, userBId } });
    return { success: true };
  }

  async block(userId: string, blockedId: string) {
    if (userId === blockedId)
      throw new BadRequestException("Нельзя заблокировать себя");
    await this.prisma.$transaction(async (tx) => {
      await tx.block.upsert({
        where: { blockerId_blockedId: { blockerId: userId, blockedId } },
        create: { blockerId: userId, blockedId },
        update: {},
      });
      const [userAId, userBId] = canonicalPair(userId, blockedId);
      await tx.friendship.deleteMany({ where: { userAId, userBId } });
      await tx.locationShare.deleteMany({
        where: {
          OR: [
            {
              ownerId: userId,
              room: { members: { some: { userId: blockedId, leftAt: null } } },
            },
            {
              ownerId: blockedId,
              room: { members: { some: { userId, leftAt: null } } },
            },
          ],
        },
      });
      await tx.roomMember.updateMany({
        where: {
          userId: blockedId,
          leftAt: null,
          room: { members: { some: { userId, leftAt: null } } },
        },
        data: { leftAt: new Date() },
      });
    });
    await this.audit.write({
      actorUserId: userId,
      action: "user.blocked",
      resourceType: "user",
      resourceId: blockedId,
    });
    return { success: true };
  }

  async unblock(userId: string, blockedId: string) {
    await this.prisma.block.deleteMany({
      where: { blockerId: userId, blockedId },
    });
    return { success: true };
  }

  async listBlocks(userId: string) {
    const rows = await this.prisma.block.findMany({
      where: { blockerId: userId },
      select: {
        blocked: {
          select: {
            id: true,
            profile: { select: { displayName: true, emoji: true } },
          },
        },
        createdAt: true,
      },
      orderBy: { createdAt: "desc" },
    });
    return rows.map(({ blocked, createdAt }) => ({
      id: blocked.id,
      displayName: blocked.profile?.displayName ?? "Пользователь",
      emoji: blocked.profile?.emoji,
      createdAt,
    }));
  }

  async createCircle(userId: string, dto: CreateCircleDto) {
    await this.assertAllFriends(userId, dto.memberIds);
    return this.prisma.circle.create({
      data: {
        ownerId: userId,
        name: dto.name.trim(),
        emoji: dto.emoji,
        members: {
          create: [
            { userId, role: "OWNER" },
            ...dto.memberIds.map((id) => ({
              userId: id,
              role: "MEMBER" as const,
            })),
          ],
        },
      },
      include: { members: true },
    });
  }

  listCircles(userId: string) {
    return this.prisma.circle.findMany({
      where: { members: { some: { userId } } },
      include: {
        members: { select: { userId: true, role: true, joinedAt: true } },
      },
      orderBy: { updatedAt: "desc" },
    });
  }

  async getCircle(userId: string, id: string) {
    const circle = await this.prisma.circle.findFirst({
      where: { id, members: { some: { userId } } },
      include: {
        members: {
          include: {
            user: {
              select: {
                id: true,
                profile: { select: { displayName: true, emoji: true } },
              },
            },
          },
        },
      },
    });
    if (!circle) throw new NotFoundException("Круг не найден");
    return circle;
  }

  async updateCircle(userId: string, id: string, dto: UpdateCircleDto) {
    await this.assertOwner(userId, id);
    return this.prisma.circle.update({ where: { id }, data: dto });
  }

  async deleteCircle(userId: string, id: string) {
    await this.assertOwner(userId, id);
    await this.prisma.circle.delete({ where: { id } });
    return { success: true };
  }

  async addMember(userId: string, circleId: string, memberId: string) {
    await this.assertOwner(userId, circleId);
    await this.assertAllFriends(userId, [memberId]);
    await this.prisma.circleMember.upsert({
      where: { circleId_userId: { circleId, userId: memberId } },
      create: { circleId, userId: memberId },
      update: {},
    });
    return { success: true };
  }

  async removeMember(userId: string, circleId: string, memberId: string) {
    await this.assertOwner(userId, circleId);
    if (userId === memberId)
      throw new BadRequestException("Владелец должен удалить весь круг");
    await this.prisma.circleMember.deleteMany({
      where: { circleId, userId: memberId },
    });
    return { success: true };
  }

  async areFriends(left: string, right: string): Promise<boolean> {
    const [userAId, userBId] = canonicalPair(left, right);
    return Boolean(
      await this.prisma.friendship.findFirst({
        where: { userAId, userBId, status: "ACCEPTED" },
      }),
    );
  }

  private async assertAllFriends(userId: string, ids: string[]) {
    const unique = [...new Set(ids)].filter((id) => id !== userId);
    const checks = await Promise.all(
      unique.map((id) => this.areFriends(userId, id)),
    );
    if (checks.some((ok) => !ok))
      throw new ForbiddenException(
        "В круг можно добавить только взаимных друзей",
      );
  }

  private async assertOwner(userId: string, circleId: string) {
    const circle = await this.prisma.circle.findFirst({
      where: { id: circleId, ownerId: userId },
    });
    if (!circle)
      throw new ForbiddenException("Только владелец может изменить круг");
  }
}
