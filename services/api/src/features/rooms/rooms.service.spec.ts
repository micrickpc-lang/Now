import { ForbiddenException } from "@nestjs/common";
import type { ConfigService } from "@nestjs/config";
import type { AuditService } from "../../common/audit.service";
import type { ContentPolicyService } from "../../common/content-policy.service";
import type { CryptoService } from "../../common/crypto.service";
import type { PrismaService } from "../../common/prisma.service";
import type { RealtimeGateway } from "../../realtime/realtime.gateway";
import { RoomsService } from "./rooms.service";

describe("RoomsService exact location shares", () => {
  const room = {
    id: "room-id",
    state: "ACTIVE",
    expiresAt: new Date(Date.now() + 60 * 60_000),
    members: [],
    polls: [],
  };
  const prisma = {
    temporaryRoom: { findFirst: jest.fn() },
    locationShare: {
      findMany: jest.fn(),
      upsert: jest.fn(),
      deleteMany: jest.fn(),
    },
  };
  const crypto = {
    envelopeEncrypt: jest.fn(),
    envelopeDecrypt: jest.fn(),
  };
  const audit = { write: jest.fn() };
  const content = { assertAllowed: jest.fn() };
  const realtime = { emitRoom: jest.fn() };
  const config = { get: jest.fn() };
  const service = new RoomsService(
    prisma as unknown as PrismaService,
    crypto as unknown as CryptoService,
    audit as unknown as AuditService,
    content as unknown as ContentPolicyService,
    realtime as unknown as RealtimeGateway,
    config as unknown as ConfigService,
  );

  beforeEach(() => {
    jest.clearAllMocks();
    prisma.temporaryRoom.findFirst.mockResolvedValue({ ...room });
    prisma.locationShare.findMany.mockResolvedValue([]);
    prisma.locationShare.upsert.mockResolvedValue({
      id: "share-id",
      ownerId: "member-id",
      expiresAt: room.expiresAt,
    });
    prisma.locationShare.deleteMany.mockResolvedValue({ count: 1 });
    config.get.mockReturnValue("true");
    crypto.envelopeEncrypt.mockReturnValue({
      ciphertext: "ciphertext",
      iv: "iv",
      authTag: "tag",
      encryptedDataKey: "key",
      keyIv: "key-iv",
      keyAuthTag: "key-tag",
    });
    audit.write.mockResolvedValue(undefined);
  });

  it("does not load or decrypt exact locations with a regular room read", async () => {
    await expect(service.get("member-id", "room-id")).resolves.toEqual(room);
    expect(prisma.locationShare.findMany).not.toHaveBeenCalled();
    expect(crypto.envelopeDecrypt).not.toHaveBeenCalled();
  });

  it("returns decrypted shares only through the dedicated active-member read and audits each share", async () => {
    prisma.locationShare.findMany.mockResolvedValue([
      {
        id: "share-a",
        ownerId: "owner-a",
        expiresAt: room.expiresAt,
        ciphertext: "a",
        iv: "iv",
        authTag: "tag",
        encryptedDataKey: "key",
        keyIv: "key-iv",
        keyAuthTag: "key-tag",
      },
      {
        id: "share-b",
        ownerId: "owner-b",
        expiresAt: room.expiresAt,
        ciphertext: "b",
        iv: "iv",
        authTag: "tag",
        encryptedDataKey: "key",
        keyIv: "key-iv",
        keyAuthTag: "key-tag",
      },
    ]);
    crypto.envelopeDecrypt
      .mockReturnValueOnce({ latitude: 55.75, longitude: 37.62 })
      .mockReturnValueOnce({ latitude: 59.93, longitude: 30.31 });

    await expect(
      service.locationShares("member-id", "room-id"),
    ).resolves.toEqual([
      expect.objectContaining({
        id: "share-a",
        value: { latitude: 55.75, longitude: 37.62 },
      }),
      expect.objectContaining({
        id: "share-b",
        value: { latitude: 59.93, longitude: 30.31 },
      }),
    ]);
    expect(audit.write).toHaveBeenCalledTimes(2);
    const [[findArgs]] = prisma.locationShare.findMany.mock
      .calls as unknown as Array<
      [
        {
          where: {
            room: { members: { some: { userId: string; leftAt: null } } };
          };
        },
      ]
    >;
    expect(findArgs.where.room).toEqual({
      members: { some: { userId: "member-id", leftAt: null } },
    });
  });

  it("requires the feature flag before accepting a precise location", async () => {
    config.get.mockReturnValue("false");

    await expect(
      service.shareLocation("member-id", "room-id", {
        latitude: 55.75,
        longitude: 37.62,
        ttlMinutes: 5,
        explicitConsent: true,
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(crypto.envelopeEncrypt).not.toHaveBeenCalled();
  });

  it("fails exact reads closed when the feature is disabled", async () => {
    config.get.mockReturnValue("false");

    await expect(
      service.locationShares("member-id", "room-id"),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.locationShare.findMany).not.toHaveBeenCalled();
  });

  it("encrypts a consented location and caps its expiry to the room", async () => {
    await service.shareLocation("member-id", "room-id", {
      latitude: 55.75,
      longitude: 37.62,
      ttlMinutes: 60,
      explicitConsent: true,
      label: "Meeting point",
    });

    expect(crypto.envelopeEncrypt).toHaveBeenCalledWith({
      latitude: 55.75,
      longitude: 37.62,
      label: "Meeting point",
    });
    const [[upsertArgs]] = prisma.locationShare.upsert.mock
      .calls as unknown as Array<
      [{ create: { ciphertext: string }; update: { ciphertext: string } }]
    >;
    expect(upsertArgs.create.ciphertext).toBe("ciphertext");
    expect(upsertArgs.update.ciphertext).toBe("ciphertext");
  });
});
