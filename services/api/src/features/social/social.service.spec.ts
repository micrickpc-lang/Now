import { randomUUID } from "node:crypto";
import type { AuditService } from "../../common/audit.service";
import type { CryptoService } from "../../common/crypto.service";
import type { PrismaService } from "../../common/prisma.service";
import type { RealtimeGateway } from "../../realtime/realtime.gateway";
import { SocialService } from "./social.service";

describe("SocialService realtime access revocation", () => {
  const userId = randomUUID();
  const otherId = randomUUID();
  const roomId = randomUUID();
  const conversationId = randomUUID();
  const prismaMock = {
    friendship: { deleteMany: jest.fn() },
    block: { upsert: jest.fn() },
    roomMember: { findMany: jest.fn(), updateMany: jest.fn() },
    locationShare: { deleteMany: jest.fn() },
    globalLocationShareRecipient: { deleteMany: jest.fn() },
    conversation: { findUnique: jest.fn() },
    $transaction: jest.fn(),
  };
  const cryptoMock = {};
  const auditMock = { write: jest.fn() };
  const realtimeMock = {
    evictUserFromConversation: jest.fn(),
    evictUserFromRoom: jest.fn(),
    emitUsers: jest.fn(),
  };
  const service = new SocialService(
    prismaMock as unknown as PrismaService,
    cryptoMock as CryptoService,
    auditMock as unknown as AuditService,
    realtimeMock as unknown as RealtimeGateway,
  );

  beforeEach(() => {
    jest.clearAllMocks();
    prismaMock.roomMember.findMany.mockResolvedValue([{ roomId }]);
    prismaMock.conversation.findUnique.mockResolvedValue({
      id: conversationId,
    });
    prismaMock.$transaction.mockImplementation(
      (work: (tx: typeof prismaMock) => unknown) =>
        Promise.resolve(work(prismaMock)),
    );
    auditMock.write.mockResolvedValue(undefined);
  });

  it("revokes direct and temporary-room subscriptions when friendship is removed", async () => {
    await expect(service.removeFriend(userId, otherId)).resolves.toEqual({
      success: true,
    });

    expect(prismaMock.locationShare.deleteMany).toHaveBeenCalled();
    expect(prismaMock.roomMember.updateMany).toHaveBeenCalled();
    expect(realtimeMock.evictUserFromConversation).toHaveBeenCalledWith(
      userId,
      conversationId,
    );
    expect(realtimeMock.evictUserFromConversation).toHaveBeenCalledWith(
      otherId,
      conversationId,
    );
    expect(realtimeMock.evictUserFromRoom).toHaveBeenCalledWith(
      otherId,
      roomId,
    );
    expect(
      prismaMock.globalLocationShareRecipient.deleteMany,
    ).toHaveBeenCalled();
  });

  it("revokes the blocked user's active room subscription", async () => {
    await expect(service.block(userId, otherId)).resolves.toEqual({
      success: true,
    });

    expect(realtimeMock.evictUserFromRoom).toHaveBeenCalledWith(
      otherId,
      roomId,
    );
    expect(realtimeMock.evictUserFromConversation).toHaveBeenCalledWith(
      userId,
      conversationId,
    );
    expect(auditMock.write).toHaveBeenCalledWith(
      expect.objectContaining({ action: "user.blocked" }),
    );
    expect(
      prismaMock.globalLocationShareRecipient.deleteMany,
    ).toHaveBeenCalled();
  });
});
