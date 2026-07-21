import { Injectable, NotFoundException } from "@nestjs/common";
import { AuditService } from "../../common/audit.service";
import { PrismaService } from "../../common/prisma.service";
import type { CreateMemoryDto } from "./memories.dto";

@Injectable()
export class MemoriesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
  ) {}

  list(userId: string) {
    return this.prisma.memory.findMany({
      where: { ownerId: userId },
      select: {
        id: true,
        title: true,
        category: true,
        occurredAt: true,
        durationMin: true,
        theme: true,
        private: true,
        participants: { select: { userId: true } },
      },
      orderBy: { occurredAt: "desc" },
      take: 100,
    });
  }

  async create(userId: string, dto: CreateMemoryDto) {
    const room = await this.prisma.temporaryRoom.findFirst({
      where: {
        id: dto.roomId,
        state: { in: ["COMPLETED", "ARCHIVED"] },
        members: { some: { userId } },
      },
      include: { signal: true, members: { select: { userId: true } } },
    });
    if (!room) throw new NotFoundException("Завершённая комната не найдена");
    const existing = await this.prisma.memory.findFirst({
      where: {
        ownerId: userId,
        title: dto.title,
        occurredAt: room.completedAt ?? room.expiresAt,
      },
    });
    if (existing) return existing;
    const memory = await this.prisma.memory.create({
      data: {
        ownerId: userId,
        title: dto.title.trim(),
        category: room.signal.category,
        occurredAt: room.completedAt ?? room.expiresAt,
        durationMin: Math.max(
          1,
          Math.round(
            (room.expiresAt.getTime() - room.signal.startsAt.getTime()) /
              60_000,
          ),
        ),
        theme: dto.theme,
        private: true,
        participants: {
          create: room.members.map((member) => ({ userId: member.userId })),
        },
      },
      select: {
        id: true,
        title: true,
        category: true,
        occurredAt: true,
        durationMin: true,
        theme: true,
        private: true,
      },
    });
    await this.audit.write({
      actorUserId: userId,
      action: "memory.created",
      resourceType: "memory",
      resourceId: memory.id,
    });
    return memory;
  }
}
