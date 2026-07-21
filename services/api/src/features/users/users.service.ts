import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { AuditService } from "../../common/audit.service";
import { PrismaService } from "../../common/prisma.service";
import type { UpdatePrivacyDto, UpdateUserDto } from "./users.dto";
import { MediaService } from "../media/media.service";

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly media: MediaService,
  ) {}

  async me(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        birthDate: true,
        limitedMode: true,
        status: true,
        createdAt: true,
        profile: {
          select: {
            displayName: true,
            emoji: true,
            bio: true,
            avatarMediaId: true,
            showRecentActivity: true,
            privacySettings: true,
            notificationSettings: true,
          },
        },
      },
    });
    if (!user) throw new NotFoundException("User not found");
    return user;
  }

  update(userId: string, dto: UpdateUserDto) {
    return this.prisma.userProfile.update({
      where: { userId },
      data: {
        ...(dto.displayName && { displayName: dto.displayName.trim() }),
        ...(dto.emoji !== undefined && { emoji: dto.emoji }),
        ...(dto.bio !== undefined && { bio: dto.bio.trim() }),
      },
      select: {
        displayName: true,
        emoji: true,
        bio: true,
        avatarMediaId: true,
      },
    });
  }

  updatePrivacy(userId: string, dto: UpdatePrivacyDto) {
    const forbidden = [
      "backgroundLocation",
      "publicProfile",
      "discoverableByStrangers",
    ];
    if (forbidden.some((key) => dto.settings[key] === true)) {
      throw new BadRequestException(
        "Настройка несовместима с приватной моделью приложения",
      );
    }
    return this.prisma.userProfile.update({
      where: { userId },
      data: {
        showRecentActivity: dto.showRecentActivity,
        privacySettings: dto.settings,
      },
      select: { showRecentActivity: true, privacySettings: true },
    });
  }

  async deleteAccount(userId: string, confirmation: string) {
    if (confirmation !== "УДАЛИТЬ")
      throw new BadRequestException("Введите УДАЛИТЬ для подтверждения");
    const requestRef = randomUUID();
    await this.media.deleteAll(userId);
    await this.prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: userId },
        data: { status: "DELETING" },
      });
      await tx.authSession.updateMany({
        where: { userId },
        data: { revokedAt: new Date() },
      });
      await tx.notificationToken.deleteMany({ where: { userId } });
      await tx.locationShare.deleteMany({
        where: {
          OR: [
            { ownerId: userId },
            { room: { members: { some: { userId } } } },
          ],
        },
      });
      await tx.roomMessage.updateMany({
        where: { authorId: userId },
        data: { authorId: null, body: "[сообщение удалено]" },
      });
      await tx.report.updateMany({
        where: { reporterId: userId },
        data: { reporterId: null },
      });
      await tx.mediaFile.deleteMany({ where: { ownerId: userId } });
      await tx.deletionReport.create({
        data: {
          requestRef,
          categories: {
            sessions: "revoked",
            pushTokens: "deleted",
            exactLocations: "deleted",
            messages: "anonymized",
            media: "deleted",
            profile: "deleted",
            socialGraph: "deleted",
          },
          retainedBasis: {
            audit:
              "security and abuse prevention; legal review required before production",
          },
        },
      });
      await tx.user.delete({ where: { id: userId } });
    });
    await this.audit.write({
      action: "user.deleted",
      resourceType: "deletion_report",
      result: "success",
      metadata: { requestRef },
    });
    return { success: true, requestRef };
  }
}
