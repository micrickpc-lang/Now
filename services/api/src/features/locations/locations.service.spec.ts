import { ForbiddenException } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import type { AuditService } from "../../common/audit.service";
import type { CryptoService } from "../../common/crypto.service";
import type { PrismaService } from "../../common/prisma.service";
import type { RealtimeGateway } from "../../realtime/realtime.gateway";
import {
  LocationShareAudienceDto,
  LocationSharePrecisionDto,
} from "./locations.dto";
import { LocationsService } from "./locations.service";

describe("LocationsService", () => {
  const ownerId = randomUUID();
  const friendId = randomUUID();
  const shareId = randomUUID();
  let locationWrite: { create: Record<string, unknown> } | undefined;
  const envelope = {
    ciphertext: "ciphertext",
    iv: "iv",
    authTag: "tag",
    encryptedDataKey: "key",
    keyIv: "key-iv",
    keyAuthTag: "key-tag",
  };
  const prismaMock = {
    userLocation: {
      upsert: jest.fn((value: { create: Record<string, unknown> }) => {
        locationWrite = value;
        return Promise.resolve(undefined);
      }),
    },
    globalLocationShare: {
      create: jest.fn(),
      findFirst: jest.fn(),
      findMany: jest.fn(),
      updateMany: jest.fn(),
    },
    globalLocationShareRecipient: { findMany: jest.fn() },
    friendship: { findMany: jest.fn() },
    block: { findMany: jest.fn() },
  };
  const cryptoMock = {
    envelopeEncrypt: jest.fn(),
    envelopeDecrypt: jest.fn(),
  };
  const auditMock = { write: jest.fn() };
  const realtimeMock = { emitUser: jest.fn(), emitUsers: jest.fn() };
  const service = new LocationsService(
    prismaMock as unknown as PrismaService,
    cryptoMock as unknown as CryptoService,
    auditMock as unknown as AuditService,
    realtimeMock as unknown as RealtimeGateway,
  );

  beforeEach(() => {
    jest.clearAllMocks();
    cryptoMock.envelopeEncrypt.mockReturnValue(envelope);
    auditMock.write.mockResolvedValue(undefined);
    prismaMock.globalLocationShareRecipient.findMany.mockResolvedValue([]);
    prismaMock.friendship.findMany.mockResolvedValue([]);
    prismaMock.block.findMany.mockResolvedValue([]);
  });

  it("stores only an encrypted envelope for the latest GPS update", async () => {
    await service.updateMyLocation(ownerId, {
      latitude: 55.7558,
      longitude: 37.6173,
    });

    expect(cryptoMock.envelopeEncrypt).toHaveBeenCalledWith({
      latitude: 55.7558,
      longitude: 37.6173,
    });
    if (!locationWrite) throw new Error("Location write was not recorded");
    expect(locationWrite.create).toEqual(expect.objectContaining(envelope));
    expect(JSON.stringify(locationWrite.create)).not.toContain("55.7558");
    expect(JSON.stringify(locationWrite.create)).not.toContain("37.6173");
  });

  it("rejects selected recipients without an active accepted friendship", async () => {
    await expect(
      service.createShare(ownerId, {
        audience: LocationShareAudienceDto.SELECTED,
        recipientIds: [friendId],
        precision: LocationSharePrecisionDto.EXACT,
        ttlMinutes: 30,
        explicitConsent: true,
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prismaMock.globalLocationShare.create).not.toHaveBeenCalled();
  });

  it("does not expose an otherwise active share after a block", async () => {
    prismaMock.globalLocationShareRecipient.findMany.mockResolvedValue([
      { share: locationShare(friendId) },
    ]);
    prismaMock.friendship.findMany.mockResolvedValue([
      { userAId: ownerId, userBId: friendId },
    ]);
    prismaMock.block.findMany.mockResolvedValue([
      { blockerId: ownerId, blockedId: friendId },
    ]);

    await expect(service.mapFriends(ownerId)).resolves.toEqual({ markers: [] });
    expect(cryptoMock.envelopeDecrypt).not.toHaveBeenCalled();
  });

  it("rounds approximate coordinates after authorization", async () => {
    prismaMock.globalLocationShareRecipient.findMany.mockResolvedValue([
      { share: locationShare(friendId, "APPROXIMATE") },
    ]);
    prismaMock.friendship.findMany.mockResolvedValue([
      { userAId: ownerId, userBId: friendId },
    ]);
    cryptoMock.envelopeDecrypt.mockReturnValue({
      latitude: 55.75581,
      longitude: 37.61734,
    });

    const result = await service.mapFriends(ownerId);
    expect(result.markers).toEqual([
      expect.objectContaining({
        userId: friendId,
        latitude: 55.76,
        longitude: 37.62,
        precision: "APPROXIMATE",
      }),
    ]);
  });

  it("notifies every snapshot recipient when an owner revokes a share", async () => {
    const secondRecipientId = randomUUID();
    prismaMock.globalLocationShare.findFirst.mockResolvedValue({
      id: shareId,
      recipients: [
        { recipientId: friendId },
        { recipientId: secondRecipientId },
      ],
    });
    prismaMock.globalLocationShare.updateMany.mockResolvedValue({ count: 1 });

    await expect(service.revokeShare(ownerId, shareId)).resolves.toEqual({
      success: true,
    });
    expect(realtimeMock.emitUsers).toHaveBeenCalledWith(
      [ownerId, friendId, secondRecipientId],
      "location.share.revoked",
      { ownerId, shareId },
    );
  });

  function locationShare(
    locationOwnerId: string,
    precision: "APPROXIMATE" | "EXACT" = "EXACT",
  ) {
    return {
      id: shareId,
      ownerId: locationOwnerId,
      precision,
      expiresAt: new Date(Date.now() + 60_000),
      owner: {
        profile: { displayName: "Friend", emoji: null, avatarMediaId: null },
        currentLocation: { ...envelope, capturedAt: new Date() },
      },
    };
  }
});
