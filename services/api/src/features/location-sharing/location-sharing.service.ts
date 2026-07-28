import {
  BadRequestException,
  ForbiddenException,
  HttpException,
  HttpStatus,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { AuditService } from "../../common/audit.service";
import { CryptoService } from "../../common/crypto.service";
import { PrismaService } from "../../common/prisma.service";
import { RealtimeGateway } from "../../realtime/realtime.gateway";
import type { Prisma } from "../../generated/prisma/client";
import type {
  CreateExactLocationShareDto,
  UpdateExactLocationShareDto,
} from "./location-sharing.dto";

type ExactPoint = {
  latitude: number;
  longitude: number;
  label?: string;
};

type AudienceResolution = {
  viewerIds: string[];
  summary: { type: string; label: string; viewerCount: number };
  circleId?: string;
  roomId?: string;
  roomExpiresAt?: Date;
};

const MAX_ACTIVE_SHARES_PER_OWNER = 10;
const MIN_UPDATE_INTERVAL_MS = 5_000;

@Injectable()
export class LocationSharingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly crypto: CryptoService,
    private readonly audit: AuditService,
    private readonly realtime: RealtimeGateway,
    private readonly config: ConfigService,
  ) {}

  async mine(userId: string) {
    this.assertEnabled();
    const shares = await this.prisma.exactLocationShare.findMany({
      where: { ownerId: userId, ...this.activeWhere() },
      include: this.shareInclude(),
      orderBy: { updatedAt: "desc" },
    });
    return shares.map((share) => this.mapOwnerShare(share));
  }

  async visibleTo(viewerId: string) {
    this.assertEnabled();
    const shares = await this.prisma.exactLocationShare.findMany({
      where: {
        ownerId: { not: viewerId },
        ...this.activeWhere(),
        OR: [
          {
            audience: "SELECTED_FRIENDS",
            recipients: { some: { viewerId } },
            owner: {
              OR: [
                {
                  friendshipsA: {
                    some: { userBId: viewerId, status: "ACCEPTED" },
                  },
                },
                {
                  friendshipsB: {
                    some: { userAId: viewerId, status: "ACCEPTED" },
                  },
                },
              ],
            },
          },
          {
            audience: "CIRCLE",
            circle: { members: { some: { userId: viewerId } } },
          },
          {
            audience: "ROOM",
            room: {
              state: "ACTIVE",
              expiresAt: { gt: new Date() },
              members: { some: { userId: viewerId, leftAt: null } },
            },
          },
        ],
        owner: {
          blocksCreated: { none: { blockedId: viewerId } },
          blocksReceived: { none: { blockerId: viewerId } },
        },
      },
      include: this.shareInclude(),
      orderBy: { updatedAt: "desc" },
    });
    await Promise.all(
      shares.map((share) =>
        this.audit.write({
          actorUserId: viewerId,
          action: "location.exact_read",
          resourceType: "exact_location_share",
          resourceId: share.id,
        }),
      ),
    );
    return shares.map((share) => this.mapVisibleShare(share));
  }

  async create(userId: string, dto: CreateExactLocationShareDto) {
    this.assertEnabled();
    if (!dto.explicitConsent) {
      throw new BadRequestException("Explicit consent is required");
    }
    const activeCount = await this.prisma.exactLocationShare.count({
      where: { ownerId: userId, ...this.activeWhere() },
    });
    if (activeCount >= MAX_ACTIVE_SHARES_PER_OWNER) {
      throw new HttpException(
        "Too many active exact location shares",
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    const audience = await this.resolveAudience(userId, dto);
    const expiresAt = this.resolveExpiry(dto.expiryMode, audience);
    const encrypted = this.crypto.envelopeEncrypt({
      latitude: dto.latitude,
      longitude: dto.longitude,
      ...(dto.label?.trim() ? { label: dto.label.trim() } : {}),
    });
    const share = await this.prisma.exactLocationShare.create({
      data: {
        ownerId: userId,
        audience: dto.audience,
        expiryMode: dto.expiryMode,
        circleId: audience.circleId,
        roomId: audience.roomId,
        backgroundUpdatesEnabled: dto.backgroundUpdatesEnabled,
        expiresAt,
        ...encrypted,
        ...(dto.audience === "SELECTED_FRIENDS"
          ? {
              recipients: {
                create: audience.viewerIds.map((viewerId) => ({ viewerId })),
              },
            }
          : {}),
      },
      include: this.shareInclude(),
    });
    await this.audit.write({
      actorUserId: userId,
      action: "location.exact_shared",
      resourceType: "exact_location_share",
      resourceId: share.id,
      metadata: {
        audience: dto.audience,
        expiryMode: dto.expiryMode,
        backgroundUpdatesEnabled: dto.backgroundUpdatesEnabled,
      },
    });
    await this.emitUpdate(share);
    return this.mapOwnerShare(share);
  }

  async update(
    userId: string,
    shareId: string,
    dto: UpdateExactLocationShareDto,
  ) {
    this.assertEnabled();
    const share = await this.prisma.exactLocationShare.findFirst({
      where: { id: shareId, ownerId: userId, ...this.activeWhere() },
      include: this.shareInclude(),
    });
    if (!share) throw new NotFoundException("Exact location share is unavailable");

    const encrypted = this.crypto.envelopeEncrypt({
      latitude: dto.latitude,
      longitude: dto.longitude,
      ...(dto.label?.trim() ? { label: dto.label.trim() } : {}),
    });
    const updatedResult = await this.prisma.exactLocationShare.updateMany({
      where: {
        id: share.id,
        ownerId: userId,
        ...this.activeWhere(),
        updatedAt: { lte: new Date(Date.now() - MIN_UPDATE_INTERVAL_MS) },
      },
      data: {
        ...encrypted,
        ...(dto.backgroundUpdatesEnabled === undefined
          ? {}
          : { backgroundUpdatesEnabled: dto.backgroundUpdatesEnabled }),
      },
    });
    if (!updatedResult.count) {
      throw new HttpException(
        "Exact location updates are limited to one every five seconds",
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    const updated = await this.prisma.exactLocationShare.findUniqueOrThrow({
      where: { id: share.id },
      include: this.shareInclude(),
    });
    await this.audit.write({
      actorUserId: userId,
      action: "location.exact_updated",
      resourceType: "exact_location_share",
      resourceId: share.id,
      metadata: {
        backgroundUpdatesEnabled: updated.backgroundUpdatesEnabled,
      },
    });
    await this.emitUpdate(updated);
    return this.mapOwnerShare(updated);
  }

  async revoke(userId: string, shareId: string) {
    this.assertEnabled();
    const share = await this.prisma.exactLocationShare.findFirst({
      where: { id: shareId, ownerId: userId },
      include: this.shareInclude(),
    });
    if (!share) throw new NotFoundException("Exact location share is unavailable");
    await this.prisma.exactLocationShare.delete({ where: { id: share.id } });
    await this.audit.write({
      actorUserId: userId,
      action: "location.exact_revoked",
      resourceType: "exact_location_share",
      resourceId: share.id,
    });
    this.realtime.emitUsers(
      await this.permittedViewerIds(share),
      "location.exact.revoked",
      { shareId: share.id, ownerId: userId },
    );
    return { success: true };
  }

  private assertEnabled() {
    if (this.config.get<string>("ALLOW_EXACT_LOCATION") !== "true") {
      throw new ForbiddenException("Exact location sharing is disabled");
    }
  }

  private activeWhere(): Prisma.ExactLocationShareWhereInput {
    const now = new Date();
    return {
      AND: [
        { OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] },
        {
          OR: [
            { signal: { is: null } },
            {
              signal: {
                is: {
                  expiresAt: { gt: now },
                  state: { in: ["ACTIVE", "FULL"] },
                },
              },
            },
          ],
        },
      ],
    };
  }

  private async resolveAudience(
    userId: string,
    dto: CreateExactLocationShareDto,
  ): Promise<AudienceResolution> {
    if (dto.audience === "SELECTED_FRIENDS") {
      if (dto.circleId || dto.roomId) {
        throw new BadRequestException("Selected friends cannot include a circle or room");
      }
      const viewerIds = [...new Set(dto.recipientIds ?? [])];
      if (!viewerIds.length || viewerIds.includes(userId)) {
        throw new BadRequestException("Select one or more other friends");
      }
      await this.assertFriends(userId, viewerIds);
      return {
        viewerIds,
        summary: {
          type: dto.audience,
          label: this.selectedFriendsLabel(viewerIds.length),
          viewerCount: viewerIds.length,
        },
      };
    }

    if (dto.audience === "CIRCLE") {
      if (!dto.circleId || dto.roomId || dto.recipientIds?.length) {
        throw new BadRequestException("Choose one circle without separate recipients");
      }
      const circle = await this.prisma.circle.findFirst({
        where: { id: dto.circleId, members: { some: { userId } } },
        include: { members: { select: { userId: true } } },
      });
      if (!circle) throw new ForbiddenException("Circle is unavailable");
      const viewerIds = circle.members
        .map(({ userId: memberId }) => memberId)
        .filter((memberId) => memberId !== userId);
      return {
        viewerIds,
        circleId: circle.id,
        summary: {
          type: dto.audience,
          label: circle.name,
          viewerCount: viewerIds.length,
        },
      };
    }

    if (!dto.roomId || dto.circleId || dto.recipientIds?.length) {
      throw new BadRequestException("Choose one active room without separate recipients");
    }
    const room = await this.prisma.temporaryRoom.findFirst({
      where: {
        id: dto.roomId,
        state: "ACTIVE",
        expiresAt: { gt: new Date() },
        members: { some: { userId, leftAt: null } },
      },
      include: { members: { where: { leftAt: null }, select: { userId: true } } },
    });
    if (!room) throw new ForbiddenException("Room is unavailable");
    const viewerIds = room.members
      .map(({ userId: memberId }) => memberId)
      .filter((memberId) => memberId !== userId);
    return {
      viewerIds,
      roomId: room.id,
      roomExpiresAt: room.expiresAt,
      summary: {
        type: dto.audience,
        label: room.title,
        viewerCount: viewerIds.length,
      },
    };
  }

  private async assertFriends(userId: string, viewerIds: string[]) {
    const pairs = viewerIds.map((viewerId) =>
      userId < viewerId
        ? { userAId: userId, userBId: viewerId }
        : { userAId: viewerId, userBId: userId },
    );
    const [friendshipCount, blockCount] = await Promise.all([
      this.prisma.friendship.count({
        where: { status: "ACCEPTED", OR: pairs },
      }),
      this.prisma.block.count({
        where: {
          OR: [
            { blockerId: userId, blockedId: { in: viewerIds } },
            { blockerId: { in: viewerIds }, blockedId: userId },
          ],
        },
      }),
    ]);
    if (friendshipCount !== viewerIds.length || blockCount > 0) {
      throw new ForbiddenException("Exact location is available only to mutual friends");
    }
  }

  private resolveExpiry(
    expiryMode: string,
    audience: AudienceResolution,
  ) {
    if (expiryMode === "THIRTY_MINUTES") {
      return new Date(Date.now() + 30 * 60_000);
    }
    if (expiryMode === "ONE_HOUR") {
      return new Date(Date.now() + 60 * 60_000);
    }
    if (expiryMode === "MEETING_END") {
      if (!audience.roomExpiresAt) {
        throw new BadRequestException("Meeting-end expiry requires an active room");
      }
      return audience.roomExpiresAt;
    }
    if (expiryMode === "MANUAL") return null;
    throw new BadRequestException("Unsupported exact location expiry");
  }

  private shareInclude() {
    return {
      owner: {
        select: {
          id: true,
          profile: { select: { displayName: true, emoji: true } },
        },
      },
      recipients: {
        select: {
          viewerId: true,
          viewer: {
            select: {
              profile: { select: { displayName: true, emoji: true } },
            },
          },
        },
      },
      circle: {
        select: {
          id: true,
          name: true,
          emoji: true,
          members: { select: { userId: true } },
        },
      },
      room: {
        select: {
          id: true,
          title: true,
          expiresAt: true,
          state: true,
          members: { where: { leftAt: null }, select: { userId: true } },
        },
      },
    } as const;
  }

  private mapOwnerShare(share: any) {
    const point = this.decrypt(share);
    return {
      id: share.id,
      ownerId: share.ownerId,
      audience: share.audience,
      expiryMode: share.expiryMode,
      expiresAt: share.expiresAt,
      updatedAt: share.updatedAt,
      backgroundUpdatesEnabled: share.backgroundUpdatesEnabled,
      point,
      audienceSummary: this.audienceSummaryFromShare(share),
    };
  }

  private mapVisibleShare(share: any) {
    const point = this.decrypt(share);
    return {
      id: share.id,
      ownerId: share.ownerId,
      owner: {
        displayName: share.owner.profile?.displayName ?? "Friend",
        emoji: share.owner.profile?.emoji ?? null,
      },
      expiresAt: share.expiresAt,
      updatedAt: share.updatedAt,
      point,
    };
  }

  private decrypt(share: any): ExactPoint {
    return this.crypto.envelopeDecrypt({
      ciphertext: share.ciphertext,
      iv: share.iv,
      authTag: share.authTag,
      encryptedDataKey: share.encryptedDataKey,
      keyIv: share.keyIv,
      keyAuthTag: share.keyAuthTag,
    }) as ExactPoint;
  }

  private audienceSummaryFromShare(share: any) {
    if (share.audience === "SELECTED_FRIENDS") {
      const names = share.recipients
        .map((recipient: any) => recipient.viewer.profile?.displayName)
        .filter(Boolean);
      return {
        type: share.audience,
        label: names.join(", ") || this.selectedFriendsLabel(share.recipients.length),
        viewerCount: share.recipients.length,
      };
    }
    if (share.audience === "CIRCLE") {
      const viewers = share.circle?.members.filter(
        ({ userId }: { userId: string }) => userId !== share.ownerId,
      ).length ?? 0;
      return {
        type: share.audience,
        label: share.circle?.name ?? "Circle",
        viewerCount: viewers,
      };
    }
    const viewers = share.room?.members.filter(
      ({ userId }: { userId: string }) => userId !== share.ownerId,
    ).length ?? 0;
    return {
      type: share.audience,
      label: share.room?.title ?? "Room",
      viewerCount: viewers,
    };
  }

  private viewerIdsFromShare(share: any): string[] {
    if (share.audience === "SELECTED_FRIENDS") {
      return share.recipients.map((recipient: any) => recipient.viewerId);
    }
    if (share.audience === "CIRCLE") {
      return (share.circle?.members ?? [])
        .map(({ userId }: { userId: string }) => userId)
        .filter((userId: string) => userId !== share.ownerId);
    }
    return (share.room?.members ?? [])
      .map(({ userId }: { userId: string }) => userId)
      .filter((userId: string) => userId !== share.ownerId);
  }

  private async emitUpdate(share: any, viewerIds?: string[]) {
    this.realtime.emitUsers(
      viewerIds ?? (await this.permittedViewerIds(share)),
      "location.exact.updated",
      {
        shareId: share.id,
        ownerId: share.ownerId,
        expiresAt: share.expiresAt?.toISOString() ?? null,
      },
    );
  }

  private async permittedViewerIds(share: any): Promise<string[]> {
    const candidateIds = this.viewerIdsFromShare(share);
    if (!candidateIds.length) return [];

    const [friendships, blocks] = await Promise.all([
      share.audience === "SELECTED_FRIENDS"
        ? this.prisma.friendship.findMany({
            where: {
              status: "ACCEPTED",
              OR: candidateIds.map((viewerId) =>
                share.ownerId < viewerId
                  ? { userAId: share.ownerId, userBId: viewerId }
                  : { userAId: viewerId, userBId: share.ownerId },
              ),
            },
            select: { userAId: true, userBId: true },
          })
        : Promise.resolve([]),
      this.prisma.block.findMany({
        where: {
          OR: [
            { blockerId: share.ownerId, blockedId: { in: candidateIds } },
            { blockerId: { in: candidateIds }, blockedId: share.ownerId },
          ],
        },
        select: { blockerId: true, blockedId: true },
      }),
    ]);
    const friendIds = new Set(
      friendships.map(({ userAId, userBId }) =>
        userAId === share.ownerId ? userBId : userAId,
      ),
    );
    const blockedIds = new Set(
      blocks.map(({ blockerId, blockedId }) =>
        blockerId === share.ownerId ? blockedId : blockerId,
      ),
    );
    return candidateIds.filter(
      (viewerId) =>
        !blockedIds.has(viewerId) &&
        (share.audience !== "SELECTED_FRIENDS" || friendIds.has(viewerId)),
    );
  }

  private selectedFriendsLabel(count: number) {
    return count === 1 ? "1 friend" : `${count} friends`;
  }
}
