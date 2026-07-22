import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../../common/audit.service";
import { PrismaService } from "../../common/prisma.service";
import type { CreateReportDto, ModerateReportDto } from "./moderation.dto";

@Injectable()
export class ModerationService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  async report(userId: string, dto: CreateReportDto) {
    const subjects = [
      dto.reportedUserId,
      dto.signalId,
      dto.messageId,
      dto.chatMessageId,
    ].filter(Boolean);
    if (subjects.length !== 1)
      throw new BadRequestException("Выберите один объект жалобы");
    if (dto.chatMessageId) {
      const visible = await this.prisma.message.findFirst({
        where: {
          id: dto.chatMessageId,
          conversation: {
            deletedAt: null,
            members: { some: { userId, leftAt: null } },
          },
        },
        select: { id: true },
      });
      if (!visible) throw new NotFoundException("Message not found");
    }
    const report = await this.prisma.report.create({
      data: { reporterId: userId, ...dto },
      select: { id: true, category: true, state: true, createdAt: true },
    });
    await this.audit.write({
      actorUserId: userId,
      action: "report.created",
      resourceType: "report",
      resourceId: report.id,
    });
    return report;
  }

  listMine(userId: string) {
    return this.prisma.report.findMany({
      where: { reporterId: userId },
      select: {
        id: true,
        category: true,
        state: true,
        createdAt: true,
        updatedAt: true,
      },
      orderBy: { createdAt: "desc" },
    });
  }

  queue(state?: string) {
    return this.prisma.report.findMany({
      where: state
        ? { state: state as never }
        : { state: { in: ["OPEN", "INVESTIGATING", "APPEALED"] } },
      select: {
        id: true,
        category: true,
        details: true,
        state: true,
        reportedUserId: true,
        signalId: true,
        messageId: true,
        chatMessageId: true,
        createdAt: true,
        actions: {
          select: { action: true, reason: true, createdAt: true },
          orderBy: { createdAt: "desc" },
        },
      },
      orderBy: { createdAt: "asc" },
      take: 100,
    });
  }

  async moderate(adminId: string, reportId: string, dto: ModerateReportDto) {
    const report = await this.prisma.report.findUnique({
      where: { id: reportId },
    });
    if (!report) throw new NotFoundException("Жалоба не найдена");
    await this.prisma.$transaction(async (tx) => {
      const state =
        dto.action === "dismiss"
          ? "DISMISSED"
          : dto.action === "investigate"
            ? "INVESTIGATING"
            : "ACTIONED";
      await tx.report.update({ where: { id: reportId }, data: { state } });
      await tx.moderationAction.create({
        data: { reportId, adminId, action: dto.action, reason: dto.reason },
      });
      if (dto.action === "suspend" && report.reportedUserId) {
        await tx.user.update({
          where: { id: report.reportedUserId },
          data: { status: "SUSPENDED" },
        });
        await tx.authSession.updateMany({
          where: { userId: report.reportedUserId },
          data: { revokedAt: new Date() },
        });
        await tx.locationShare.deleteMany({
          where: { ownerId: report.reportedUserId },
        });
      }
      if (dto.action === "restore" && report.reportedUserId) {
        await tx.user.update({
          where: { id: report.reportedUserId },
          data: { status: "ACTIVE" },
        });
      }
    });
    await this.audit.write({
      actorAdminId: adminId,
      action: `moderation.${dto.action}`,
      resourceType: "report",
      resourceId: reportId,
      metadata: { reason: dto.reason },
    });
    return { success: true };
  }
}
