import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../../common/audit.service";
import {
  CryptoService,
  type EnvelopeCiphertext,
} from "../../common/crypto.service";
import { PrismaService } from "../../common/prisma.service";
import { RealtimeGateway } from "../../realtime/realtime.gateway";
import { GlobalLocationPrecision } from "../../generated/prisma/client";
import type {
  CreateGlobalLocationShareDto,
  UpdateMyLocationDto,
} from "./locations.dto";
import { LocationShareAudienceDto } from "./locations.dto";

const MAX_CAPTURE_AGE_MS = 24 * 60 * 60 * 1000;
const MAX_CAPTURE_FUTURE_MS = 5 * 60 * 1000;

type Coordinates = { latitude: number; longitude: number };

function canonicalPair(left: string, right: string): [string, string] {
  return left < right ? [left, right] : [right, left];
}

@Injectable()
export class LocationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly crypto: CryptoService,
    private readonly audit: AuditService,
    private readonly realtime: RealtimeGateway,
  ) {}

  async updateMyLocation(userId: string, dto: UpdateMyLocationDto) {
    const capturedAt = dto.capturedAt ? new Date(dto.capturedAt) : new Date();
    const now = Date.now();
    if (
      !Number.isFinite(capturedAt.getTime()) ||
      capturedAt.getTime() < now - MAX_CAPTURE_AGE_MS ||
      capturedAt.getTime() > now + MAX_CAPTURE_FUTURE_MS
    ) {
      throw new BadRequestException(
        "Location capture time is outside the allowed window",
      );
    }
    const encrypted = this.crypto.envelopeEncrypt({
      latitude: dto.latitude,
      longitude: dto.longitude,
    });
    await this.prisma.userLocation.upsert({
      where: { ownerId: userId },
      create: { ownerId: userId, ...encrypted, capturedAt },
      update: { ...encrypted, capturedAt },
    });
    await this.audit.write({
      actorUserId: userId,
      action: "location.updated",
      resourceType: "user_location",
      resourceId: userId,
    });
    const recipients = await this.prisma.globalLocationShareRecipient.findMany({
      where: {
        share: {
          ownerId: userId,
          revokedAt: null,
          expiresAt: { gt: new Date() },
        },
      },
      select: { recipientId: true },
    });
    this.realtime.emitUsers(
      recipients.map(({ recipientId }) => recipientId),
      "location.updated",
      { ownerId: userId },
    );
    return { capturedAt };
  }

  async createShare(userId: string, dto: CreateGlobalLocationShareDto) {
    if (dto.explicitConsent !== true)
      throw new BadRequestException(
        "Explicit consent is required for location sharing",
      );
    const recipientIds = await this.resolveRecipients(userId, dto);
    const expiresAt = new Date(Date.now() + dto.ttlMinutes * 60_000);
    const share = await this.prisma.globalLocationShare.create({
      data: {
        ownerId: userId,
        audience: dto.audience,
        precision: dto.precision,
        explicitConsentAt: new Date(),
        expiresAt,
        recipients: {
          create: recipientIds.map((recipientId) => ({ recipientId })),
        },
      },
      select: {
        id: true,
        audience: true,
        precision: true,
        expiresAt: true,
        createdAt: true,
      },
    });
    await this.audit.write({
      actorUserId: userId,
      action: "location.share_created",
      resourceType: "global_location_share",
      resourceId: share.id,
      metadata: {
        audience: dto.audience,
        precision: dto.precision,
        recipientCount: recipientIds.length,
      },
    });
    this.realtime.emitUsers(recipientIds, "location.share.available", {
      ownerId: userId,
      shareId: share.id,
    });
    return { ...share, recipientCount: recipientIds.length };
  }

  async listOwnShares(userId: string) {
    return this.prisma.globalLocationShare
      .findMany({
        where: {
          ownerId: userId,
          revokedAt: null,
          expiresAt: { gt: new Date() },
        },
        select: {
          id: true,
          audience: true,
          precision: true,
          expiresAt: true,
          createdAt: true,
          _count: { select: { recipients: true } },
        },
        orderBy: { createdAt: "desc" },
      })
      .then((shares) =>
        shares.map(({ _count, ...share }) => ({
          ...share,
          recipientCount: _count.recipients,
        })),
      );
  }

  async revokeShare(userId: string, shareId: string) {
    const share = await this.prisma.globalLocationShare.findFirst({
      where: { id: shareId, ownerId: userId, revokedAt: null },
      select: {
        id: true,
        recipients: { select: { recipientId: true } },
      },
    });
    if (!share) throw new NotFoundException("Location share not found");
    const result = await this.prisma.globalLocationShare.updateMany({
      where: { id: shareId, ownerId: userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    if (!result.count) throw new NotFoundException("Location share not found");
    await this.audit.write({
      actorUserId: userId,
      action: "location.share_revoked",
      resourceType: "global_location_share",
      resourceId: shareId,
    });
    this.realtime.emitUsers(
      [userId, ...share.recipients.map(({ recipientId }) => recipientId)],
      "location.share.revoked",
      { ownerId: userId, shareId },
    );
    return { success: true };
  }

  async mapFriends(userId: string) {
    const shares = await this.prisma.globalLocationShareRecipient.findMany({
      where: {
        recipientId: userId,
        share: { revokedAt: null, expiresAt: { gt: new Date() } },
      },
      select: {
        share: {
          select: {
            id: true,
            ownerId: true,
            precision: true,
            expiresAt: true,
            owner: {
              select: {
                profile: {
                  select: {
                    displayName: true,
                    emoji: true,
                    avatarMediaId: true,
                  },
                },
                currentLocation: {
                  select: {
                    ciphertext: true,
                    iv: true,
                    authTag: true,
                    encryptedDataKey: true,
                    keyIv: true,
                    keyAuthTag: true,
                    capturedAt: true,
                  },
                },
              },
            },
          },
        },
      },
      orderBy: { createdAt: "desc" },
    });
    const permittedOwners = await this.accessibleFriendIds(
      userId,
      shares.map(({ share }) => share.ownerId),
    );
    const seenOwners = new Set<string>();
    const markers = shares.flatMap(({ share }) => {
      if (!permittedOwners.has(share.ownerId) || seenOwners.has(share.ownerId))
        return [];
      seenOwners.add(share.ownerId);
      if (!share.owner.currentLocation) return [];
      const coordinates = this.decryptCoordinates(share.owner.currentLocation);
      const value =
        share.precision === GlobalLocationPrecision.APPROXIMATE
          ? {
              latitude: this.roundApproximate(coordinates.latitude),
              longitude: this.roundApproximate(coordinates.longitude),
            }
          : coordinates;
      return [
        {
          shareId: share.id,
          userId: share.ownerId,
          displayName: share.owner.profile?.displayName ?? "User",
          emoji: share.owner.profile?.emoji ?? null,
          avatarMediaId: share.owner.profile?.avatarMediaId ?? null,
          precision: share.precision,
          expiresAt: share.expiresAt,
          capturedAt: share.owner.currentLocation.capturedAt,
          ...value,
        },
      ];
    });
    await this.audit.write({
      actorUserId: userId,
      action: "location.map_read",
      resourceType: "global_location_share",
      resourceId: userId,
      metadata: { markerCount: markers.length },
    });
    return { markers };
  }

  private async resolveRecipients(
    userId: string,
    dto: CreateGlobalLocationShareDto,
  ) {
    const requested =
      dto.audience === LocationShareAudienceDto.SELECTED
        ? (dto.recipientIds ?? [])
        : await this.friendIds(userId);
    const recipientIds = [...new Set(requested)].filter((id) => id !== userId);
    if (!recipientIds.length)
      throw new BadRequestException("At least one eligible friend is required");
    const allowed = await this.accessibleFriendIds(userId, recipientIds);
    if (allowed.size !== recipientIds.length)
      throw new ForbiddenException(
        "Location can only be shared with unblocked accepted friends",
      );
    return recipientIds;
  }

  private async friendIds(userId: string) {
    const friendships = await this.prisma.friendship.findMany({
      where: {
        status: "ACCEPTED",
        OR: [{ userAId: userId }, { userBId: userId }],
      },
      select: { userAId: true, userBId: true },
    });
    return friendships.map((friendship) =>
      friendship.userAId === userId ? friendship.userBId : friendship.userAId,
    );
  }

  private async accessibleFriendIds(userId: string, candidateIds: string[]) {
    const candidates = [...new Set(candidateIds)].filter((id) => id !== userId);
    if (!candidates.length) return new Set<string>();
    const friendships = await this.prisma.friendship.findMany({
      where: {
        status: "ACCEPTED",
        OR: candidates.map((otherId) => {
          const [userAId, userBId] = canonicalPair(userId, otherId);
          return { userAId, userBId };
        }),
      },
      select: { userAId: true, userBId: true },
    });
    const friends = new Set(
      friendships.map((friendship) =>
        friendship.userAId === userId ? friendship.userBId : friendship.userAId,
      ),
    );
    if (!friends.size) return friends;
    const blocks = await this.prisma.block.findMany({
      where: {
        OR: [...friends].flatMap((otherId) => [
          { blockerId: userId, blockedId: otherId },
          { blockerId: otherId, blockedId: userId },
        ]),
      },
      select: { blockerId: true, blockedId: true },
    });
    for (const block of blocks)
      friends.delete(
        block.blockerId === userId ? block.blockedId : block.blockerId,
      );
    return friends;
  }

  private decryptCoordinates(value: EnvelopeCiphertext): Coordinates {
    const decrypted = this.crypto.envelopeDecrypt(value);
    if (
      typeof decrypted !== "object" ||
      decrypted === null ||
      typeof (decrypted as Coordinates).latitude !== "number" ||
      typeof (decrypted as Coordinates).longitude !== "number"
    )
      throw new Error("Invalid encrypted location payload");
    return decrypted as Coordinates;
  }

  private roundApproximate(value: number) {
    return Math.round(value * 100) / 100;
  }
}
