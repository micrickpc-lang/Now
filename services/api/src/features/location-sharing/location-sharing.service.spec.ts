import { HttpException, HttpStatus } from "@nestjs/common";
import type { ConfigService } from "@nestjs/config";
import { randomUUID } from "node:crypto";
import type { AuditService } from "../../common/audit.service";
import type { CryptoService } from "../../common/crypto.service";
import type { PrismaService } from "../../common/prisma.service";
import type { RealtimeGateway } from "../../realtime/realtime.gateway";
import { LocationSharingService } from "./location-sharing.service";

const envelope = {
  ciphertext: "ciphertext",
  iv: "iv",
  authTag: "tag",
  encryptedDataKey: "key",
  keyIv: "key-iv",
  keyAuthTag: "key-tag",
};

describe("LocationSharingService", () => {
  const ownerId = randomUUID();
  const viewerId = randomUUID();
  const shareId = randomUUID();
  const prisma = {
    exactLocationShare: {
      count: jest.fn(),
      create: jest.fn(),
      findFirst: jest.fn(),
      findMany: jest.fn(),
      findUniqueOrThrow: jest.fn(),
      updateMany: jest.fn(),
      delete: jest.fn(),
    },
    friendship: { count: jest.fn(), findMany: jest.fn() },
    block: { count: jest.fn(), findMany: jest.fn() },
    circle: { findFirst: jest.fn() },
    temporaryRoom: { findFirst: jest.fn() },
  };
  const crypto = {
    envelopeEncrypt: jest.fn(),
    envelopeDecrypt: jest.fn(),
  };
  const audit = { write: jest.fn() };
  const realtime = { emitUsers: jest.fn() };
  const config = { get: jest.fn() };
  const service = new LocationSharingService(
    prisma as unknown as PrismaService,
    crypto as unknown as CryptoService,
    audit as unknown as AuditService,
    realtime as unknown as RealtimeGateway,
    config as unknown as ConfigService,
  );

  const selectedShare = () => ({
    id: shareId,
    ownerId,
    audience: "SELECTED_FRIENDS",
    expiryMode: "MANUAL",
    expiresAt: null,
    updatedAt: new Date(Date.now() - 10_000),
    backgroundUpdatesEnabled: false,
    ...envelope,
    owner: { id: ownerId, profile: { displayName: "Owner", emoji: null } },
    recipients: [
      {
        viewerId,
        viewer: { profile: { displayName: "Viewer", emoji: null } },
      },
    ],
    circle: null,
    room: null,
  });

  const createDto = () => ({
    latitude: 55.75,
    longitude: 37.62,
    audience: "SELECTED_FRIENDS" as const,
    expiryMode: "MANUAL" as const,
    explicitConsent: true,
    backgroundUpdatesEnabled: false,
    recipientIds: [viewerId],
  });

  beforeEach(() => {
    jest.clearAllMocks();
    config.get.mockReturnValue("true");
    prisma.exactLocationShare.count.mockResolvedValue(0);
    prisma.friendship.count.mockResolvedValue(1);
    prisma.block.count.mockResolvedValue(0);
    prisma.friendship.findMany.mockResolvedValue([
      { userAId: ownerId, userBId: viewerId },
    ]);
    prisma.block.findMany.mockResolvedValue([]);
    prisma.exactLocationShare.create.mockResolvedValue(selectedShare());
    prisma.exactLocationShare.findFirst.mockResolvedValue(selectedShare());
    prisma.exactLocationShare.updateMany.mockResolvedValue({ count: 1 });
    prisma.exactLocationShare.findUniqueOrThrow.mockResolvedValue(
      selectedShare(),
    );
    crypto.envelopeEncrypt.mockReturnValue(envelope);
    crypto.envelopeDecrypt.mockReturnValue({ latitude: 55.75, longitude: 37.62 });
    audit.write.mockResolvedValue(undefined);
  });

  it("fails closed when exact sharing is disabled", async () => {
    config.get.mockReturnValue("false");

    await expect(service.create(ownerId, createDto())).rejects.toMatchObject({
      status: HttpStatus.FORBIDDEN,
    });
    expect(prisma.exactLocationShare.count).not.toHaveBeenCalled();
    expect(crypto.envelopeEncrypt).not.toHaveBeenCalled();
  });

  it("requires every selected recipient to be an accepted, unblocked friend", async () => {
    prisma.friendship.count.mockResolvedValue(0);

    await expect(service.create(ownerId, createDto())).rejects.toMatchObject({
      status: HttpStatus.FORBIDDEN,
    });
    expect(prisma.exactLocationShare.create).not.toHaveBeenCalled();
  });

  it("caps the number of active exact shares", async () => {
    prisma.exactLocationShare.count.mockResolvedValue(10);

    await expect(service.create(ownerId, createDto())).rejects.toMatchObject({
      status: HttpStatus.TOO_MANY_REQUESTS,
    });
    expect(prisma.friendship.count).not.toHaveBeenCalled();
  });

  it("checks the current friendship again before exposing selected-friend shares", async () => {
    prisma.exactLocationShare.findMany.mockResolvedValue([]);

    await expect(service.visibleTo(viewerId)).resolves.toEqual([]);
    const [[query]] = prisma.exactLocationShare.findMany.mock.calls as unknown as Array<
      [{ where: { OR: Array<{ owner?: { OR: unknown[] } }> } }]
    >;
    expect(query.where.OR[0]?.owner?.OR).toEqual([
      { friendshipsA: { some: { userBId: viewerId, status: "ACCEPTED" } } },
      { friendshipsB: { some: { userAId: viewerId, status: "ACCEPTED" } } },
    ]);
  });

  it("returns 429 instead of accepting updates faster than five seconds", async () => {
    prisma.exactLocationShare.updateMany.mockResolvedValue({ count: 0 });

    await expect(
      service.update(ownerId, shareId, { latitude: 55.76, longitude: 37.63 }),
    ).rejects.toMatchObject({ status: HttpStatus.TOO_MANY_REQUESTS });
    expect(prisma.exactLocationShare.findUniqueOrThrow).not.toHaveBeenCalled();
  });

  it("does not notify a recipient who has blocked the location owner", async () => {
    prisma.block.findMany.mockResolvedValue([
      { blockerId: viewerId, blockedId: ownerId },
    ]);

    await service.update(ownerId, shareId, {
      latitude: 55.76,
      longitude: 37.63,
    });

    expect(realtime.emitUsers).toHaveBeenCalledWith(
      [],
      "location.exact.updated",
      expect.objectContaining({ shareId, ownerId }),
    );
  });

  it("uses an HTTP 429 response for the client-visible update limit", async () => {
    prisma.exactLocationShare.updateMany.mockResolvedValue({ count: 0 });

    try {
      await service.update(ownerId, shareId, {
        latitude: 55.76,
        longitude: 37.63,
      });
      fail("Expected an update limit error");
    } catch (error) {
      expect(error).toBeInstanceOf(HttpException);
      expect((error as HttpException).getStatus()).toBe(
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  });
});
