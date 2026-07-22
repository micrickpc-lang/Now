import { randomUUID } from "node:crypto";
import type { AuditService } from "../../common/audit.service";
import type { PrismaService } from "../../common/prisma.service";
import type { MediaService } from "../media/media.service";
import { UsersService } from "./users.service";

describe("UsersService account deletion", () => {
  const userId = randomUUID();
  const successorId = randomUUID();
  const retainedGroupId = randomUUID();
  const emptyGroupId = randomUUID();

  const tx = {
    user: { update: jest.fn(), delete: jest.fn() },
    authSession: { updateMany: jest.fn() },
    notificationToken: { deleteMany: jest.fn() },
    locationShare: { deleteMany: jest.fn() },
    roomMessage: { updateMany: jest.fn() },
    message: { updateMany: jest.fn() },
    conversation: {
      findMany: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
    },
    conversationMember: { update: jest.fn() },
    report: { updateMany: jest.fn() },
    mediaFile: { deleteMany: jest.fn() },
    deletionReport: { create: jest.fn() },
  };
  const prismaMock = {
    $transaction: jest.fn((work: (client: typeof tx) => unknown) =>
      Promise.resolve(work(tx)),
    ),
  };
  const auditMock = { write: jest.fn() };
  const mediaMock = { deleteAll: jest.fn() };
  const service = new UsersService(
    prismaMock as unknown as PrismaService,
    auditMock as unknown as AuditService,
    mediaMock as unknown as MediaService,
  );

  beforeEach(() => {
    jest.clearAllMocks();
    for (const repository of Object.values(tx)) {
      for (const method of Object.values(repository)) {
        method.mockResolvedValue({});
      }
    }
    tx.conversation.findMany.mockResolvedValue([
      { id: retainedGroupId, members: [{ userId: successorId }] },
      { id: emptyGroupId, members: [] },
    ]);
    mediaMock.deleteAll.mockResolvedValue(undefined);
    auditMock.write.mockResolvedValue(undefined);
  });

  it("transfers owned groups and deletes only groups without active successors", async () => {
    await expect(
      service.deleteAccount(
        userId,
        "\u0423\u0414\u0410\u041b\u0418\u0422\u042c",
      ),
    ).resolves.toMatchObject({ success: true });

    const ownedGroupCalls = tx.conversation.findMany.mock
      .calls as unknown as Array<[unknown]>;
    expect(ownedGroupCalls[0]?.[0]).toMatchObject({
      where: { type: "GROUP", ownerId: userId },
      select: {
        members: {
          where: {
            userId: { not: userId },
            leftAt: null,
            role: { in: ["ADMIN", "MEMBER"] },
          },
          orderBy: [{ role: "asc" }, { joinedAt: "asc" }, { userId: "asc" }],
          take: 1,
        },
      },
    });
    expect(tx.conversationMember.update).toHaveBeenCalledWith({
      where: {
        conversationId_userId: {
          conversationId: retainedGroupId,
          userId: successorId,
        },
      },
      data: { role: "OWNER" },
    });
    expect(tx.conversation.update).toHaveBeenCalledWith({
      where: { id: retainedGroupId },
      data: { ownerId: successorId },
    });
    expect(tx.conversation.delete).toHaveBeenCalledTimes(1);
    expect(tx.conversation.delete).toHaveBeenCalledWith({
      where: { id: emptyGroupId },
    });
    const ownershipUpdateOrder =
      tx.conversation.update.mock.invocationCallOrder[0] ?? Infinity;
    const userDeleteOrder = tx.user.delete.mock.invocationCallOrder[0] ?? -1;
    expect(ownershipUpdateOrder).toBeLessThan(userDeleteOrder);
  });
});
