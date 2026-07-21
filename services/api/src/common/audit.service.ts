import { Injectable } from "@nestjs/common";
import { PrismaService } from "./prisma.service";

export interface AuditEvent {
  actorUserId?: string;
  actorAdminId?: string;
  action: string;
  resourceType: string;
  resourceId?: string;
  result?: "success" | "denied" | "failed";
  ipHash?: string;
  metadata?: Record<string, string | number | boolean | null>;
}

@Injectable()
export class AuditService {
  constructor(private readonly prisma: PrismaService) {}

  async write(event: AuditEvent): Promise<void> {
    await this.prisma.auditLog.create({
      data: {
        actorUserId: event.actorUserId,
        actorAdminId: event.actorAdminId,
        action: event.action,
        resourceType: event.resourceType,
        resourceId: event.resourceId,
        result: event.result ?? "success",
        ipHash: event.ipHash,
        metadata: event.metadata ?? {},
      },
    });
  }
}
