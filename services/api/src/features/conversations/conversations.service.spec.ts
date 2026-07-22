import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import type { AuditService } from "../../common/audit.service";
import type { ContentPolicyService } from "../../common/content-policy.service";
import type { PrismaService } from "../../common/prisma.service";
import { ServerManagedEncryptionProvider } from "../../common/message-encryption.provider";
import type { RealtimeGateway } from "../../realtime/realtime.gateway";
import { ConversationsService } from "./conversations.service";
import type { TypingStateService } from "./typing.store";

describe("ConversationsService security policies", () => {
  const actorId = randomUUID();
  const friendId = randomUUID();
  const conversationId = randomUUID();
  const clientMessageId = randomUUID();
  const messageId = randomUUID();

  const prismaMock = {
    friendship: { findFirst: jest.fn() },
    block: { count: jest.fn() },
    conversation: {
      upsert: jest.fn(),
      findUnique: jest.fn(),
      findFirst: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
    },
    conversationMember: {
      findFirst: jest.fn(),
      findMany: jest.fn(),
      upsert: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
    },
    message: {
      findUnique: jest.fn(),
      findMany: jest.fn(),
      count: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
    },
    messageEdit: { create: jest.fn() },
    messageReaction: { upsert: jest.fn(), deleteMany: jest.fn() },
    messageReadReceipt: { createMany: jest.fn(), upsert: jest.fn() },
    messageDelivery: { updateManyAndReturn: jest.fn() },
    pinnedMessage: { upsert: jest.fn(), deleteMany: jest.fn() },
    chatMute: { deleteMany: jest.fn() },
    conversationDraft: { deleteMany: jest.fn() },
    chatAuditEvent: { create: jest.fn() },
    signal: { findFirst: jest.fn() },
    signalVisibility: { count: jest.fn() },
    user: { findUniqueOrThrow: jest.fn() },
    $transaction: jest.fn(),
  };
  const contentMock = { assertAllowed: jest.fn() };
  const auditMock = { write: jest.fn() };
  const realtimeMock = {
    emitUsers: jest.fn(),
    emitUser: jest.fn(),
    emitConversation: jest.fn(),
    evictUserFromConversation: jest.fn(),
  };
  const typingMock = { set: jest.fn(), delete: jest.fn() };
  const service = new ConversationsService(
    prismaMock as unknown as PrismaService,
    contentMock as unknown as ContentPolicyService,
    auditMock as unknown as AuditService,
    realtimeMock as unknown as RealtimeGateway,
    typingMock as unknown as TypingStateService,
    new ServerManagedEncryptionProvider(),
  );

  const baseMessage = {
    id: messageId,
    conversationId,
    senderId: actorId,
    clientMessageId,
    type: "TEXT" as const,
    text: "original",
    metadata: {},
    protectionMode: "SERVER_MANAGED",
    payloadVersion: 1,
    replyToMessageId: null,
    forwardedFromMessageId: null,
    createdAt: new Date("2026-07-22T00:00:00.000Z"),
    editedAt: null,
    deletedAt: null,
    deleteMode: "NONE" as const,
    reactions: [],
    readReceipts: [],
    deliveries: [],
    attachments: [],
  };

  beforeEach(() => {
    jest.clearAllMocks();
    prismaMock.conversationMember.findFirst.mockResolvedValue({
      role: "MEMBER",
      conversation: {
        id: conversationId,
        type: "GROUP",
        members: [
          { userId: actorId, role: "MEMBER" },
          { userId: friendId, role: "MEMBER" },
        ],
      },
    });
    prismaMock.user.findUniqueOrThrow.mockResolvedValue({ limitedMode: false });
    prismaMock.friendship.findFirst.mockResolvedValue({ id: randomUUID() });
    prismaMock.messageDelivery.updateManyAndReturn.mockResolvedValue([]);
    prismaMock.conversationMember.findMany.mockResolvedValue([
      { userId: actorId },
      { userId: friendId },
    ]);
    prismaMock.chatAuditEvent.create.mockResolvedValue({});
    auditMock.write.mockResolvedValue(undefined);
    contentMock.assertAllowed.mockResolvedValue(undefined);
    prismaMock.$transaction.mockImplementation(
      (work: ((tx: typeof prismaMock) => unknown) | unknown[]) =>
        Promise.resolve(
          typeof work === "function" ? work(prismaMock) : Promise.all(work),
        ),
    );
  });

  it("stops direct creation when either user has blocked the other", async () => {
    prismaMock.friendship.findFirst.mockResolvedValue({ id: randomUUID() });
    prismaMock.block.count.mockResolvedValue(1);
    await expect(
      service.createDirect(actorId, friendId),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prismaMock.conversation.upsert).not.toHaveBeenCalled();
  });

  it("rejects a group title that becomes empty after trimming", async () => {
    await expect(
      service.createGroup(actorId, {
        title: "   ",
        memberIds: [friendId],
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(contentMock.assertAllowed).not.toHaveBeenCalled();
  });

  it("rejects a clientMessageId replay with changed content", async () => {
    prismaMock.message.findUnique.mockResolvedValue(baseMessage);
    await expect(
      service.createMessage(actorId, conversationId, {
        clientMessageId,
        type: "TEXT",
        text: "changed",
      }),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(prismaMock.message.count).not.toHaveBeenCalled();
  });

  it("returns the original message for an identical idempotent replay", async () => {
    prismaMock.message.findUnique.mockResolvedValue(baseMessage);
    await expect(
      service.createMessage(actorId, conversationId, {
        clientMessageId,
        type: "TEXT",
        text: "original",
      }),
    ).resolves.toMatchObject({ id: messageId, text: "original" });
    expect(contentMock.assertAllowed).not.toHaveBeenCalled();
  });

  it("replays an existing signal message without revalidating expired signal state", async () => {
    const signalId = randomUUID();
    prismaMock.message.findUnique.mockResolvedValue({
      ...baseMessage,
      type: "SIGNAL",
      text: null,
      metadata: { signalId },
    });
    await expect(
      service.createMessage(actorId, conversationId, {
        clientMessageId,
        type: "SIGNAL",
        metadata: { signalId },
      }),
    ).resolves.toMatchObject({ id: messageId, type: "SIGNAL" });
    expect(prismaMock.signal.findFirst).not.toHaveBeenCalled();
  });

  it("maps SELF deletion only as a tombstone for its author", async () => {
    prismaMock.message.findMany.mockResolvedValue([
      {
        ...baseMessage,
        deleteMode: "SELF",
        deletedAt: new Date("2026-07-22T00:01:00.000Z"),
      },
    ]);
    const own = await service.messages(actorId, conversationId, { limit: 30 });
    const other = await service.messages(friendId, conversationId, {
      limit: 30,
    });
    expect(own.items[0]).toMatchObject({ text: null, deleteMode: "SELF" });
    expect(other.items[0]).toMatchObject({
      text: "original",
      deleteMode: "NONE",
    });
  });

  it("atomically acknowledges pending deliveries when a recipient loads history", async () => {
    prismaMock.message.findMany.mockResolvedValue([baseMessage]);
    prismaMock.messageDelivery.updateManyAndReturn.mockResolvedValue([
      { messageId },
    ]);
    await service.messages(friendId, conversationId, { limit: 30 });
    const deliveryCalls = prismaMock.messageDelivery.updateManyAndReturn.mock
      .calls as unknown as Array<[unknown]>;
    expect(deliveryCalls[0]?.[0]).toMatchObject({
      where: { userId: friendId, state: "PENDING" },
    });
    expect(realtimeMock.emitUsers).toHaveBeenCalledWith(
      [actorId, friendId],
      "message.delivered",
      expect.objectContaining({ messageId, userId: friendId }),
    );
  });

  it("exposes delivery status only to the sender", async () => {
    prismaMock.message.findMany.mockResolvedValue([
      {
        ...baseMessage,
        deliveries: [
          { userId: friendId, state: "DELIVERED", deliveredAt: new Date() },
        ],
      },
    ]);
    const sender = await service.messages(actorId, conversationId, {
      limit: 30,
    });
    const recipient = await service.messages(friendId, conversationId, {
      limit: 30,
    });
    expect(sender.items[0]).toMatchObject({ deliveryStatus: "DELIVERED" });
    expect(recipient.items[0]).not.toHaveProperty("deliveryStatus");
  });

  it("omits sender-only delivery status from shared realtime message payloads", async () => {
    const created = {
      ...baseMessage,
      deliveries: [
        {
          userId: friendId,
          state: "PENDING" as const,
          deliveredAt: null,
        },
      ],
    };
    prismaMock.message.findUnique.mockResolvedValue(null);
    prismaMock.message.count.mockResolvedValue(0);
    prismaMock.message.create.mockResolvedValue(created);
    prismaMock.conversation.update.mockResolvedValue({});

    const response = await service.createMessage(actorId, conversationId, {
      clientMessageId,
      type: "TEXT",
      text: "original",
    });

    expect(response).toMatchObject({ deliveryStatus: "SENT" });
    const eventCalls = realtimeMock.emitUsers.mock.calls as unknown as Array<
      [string[], string, { message: Record<string, unknown> }]
    >;
    const eventCall = eventCalls.find(
      ([, event]) => event === "message.created",
    );
    expect(eventCall).toBeDefined();
    expect(eventCall?.[2].message).not.toHaveProperty("deliveryStatus");
  });

  it("keeps former-friend direct history readable but forbids new messages", async () => {
    prismaMock.conversationMember.findFirst.mockResolvedValue({
      role: "MEMBER",
      conversation: {
        id: conversationId,
        type: "DIRECT",
        members: [
          { userId: actorId, role: "MEMBER" },
          { userId: friendId, role: "MEMBER" },
        ],
      },
    });
    prismaMock.block.count.mockResolvedValue(0);
    prismaMock.friendship.findFirst.mockResolvedValue(null);
    prismaMock.user.findUniqueOrThrow.mockResolvedValue({ limitedMode: true });
    prismaMock.message.findMany.mockResolvedValue([baseMessage]);

    await expect(
      service.messages(actorId, conversationId, { limit: 30 }),
    ).resolves.toMatchObject({ items: [{ id: messageId }] });
    expect(
      prismaMock.messageDelivery.updateManyAndReturn,
    ).not.toHaveBeenCalled();
    await expect(
      service.createMessage(actorId, conversationId, {
        clientMessageId: randomUUID(),
        type: "TEXT",
        text: "must stay blocked",
      }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prismaMock.message.create).not.toHaveBeenCalled();
  });

  it("evicts a removed group member from realtime and clears typing", async () => {
    prismaMock.conversationMember.findFirst
      .mockResolvedValueOnce({
        role: "ADMIN",
        conversation: {
          id: conversationId,
          type: "GROUP",
          members: [
            { userId: actorId, role: "ADMIN" },
            { userId: friendId, role: "MEMBER" },
          ],
        },
      })
      .mockResolvedValueOnce({ role: "MEMBER" });
    prismaMock.conversationMember.update.mockResolvedValue({});
    typingMock.delete.mockResolvedValue(undefined);

    await expect(
      service.removeMember(actorId, conversationId, friendId),
    ).resolves.toEqual({ success: true });

    expect(typingMock.delete).toHaveBeenCalledWith(conversationId, friendId);
    expect(realtimeMock.evictUserFromConversation).toHaveBeenCalledWith(
      friendId,
      conversationId,
    );
  });

  it("evicts a member's sockets when they leave a group", async () => {
    prismaMock.conversationMember.update.mockResolvedValue({});
    prismaMock.chatMute.deleteMany.mockResolvedValue({ count: 0 });
    prismaMock.conversationDraft.deleteMany.mockResolvedValue({ count: 0 });
    typingMock.delete.mockResolvedValue(undefined);

    await expect(service.leave(actorId, conversationId)).resolves.toEqual({
      success: true,
    });

    expect(realtimeMock.evictUserFromConversation).toHaveBeenCalledWith(
      actorId,
      conversationId,
    );
  });

  it("transfers group ownership before allowing the old owner to leave", async () => {
    prismaMock.conversationMember.findFirst.mockResolvedValue({
      role: "OWNER",
      conversation: {
        id: conversationId,
        type: "GROUP",
        members: [
          { userId: actorId, role: "OWNER" },
          { userId: friendId, role: "ADMIN" },
        ],
      },
    });
    prismaMock.conversationMember.updateMany.mockResolvedValue({ count: 1 });
    prismaMock.conversation.updateMany.mockResolvedValue({ count: 1 });
    prismaMock.conversationMember.update.mockResolvedValue({});
    prismaMock.message.count.mockResolvedValue(0);
    prismaMock.conversation.findFirst.mockResolvedValue({
      id: conversationId,
      type: "GROUP",
      title: "Close friends",
      avatarMediaId: null,
      ownerId: friendId,
      createdAt: new Date(),
      updatedAt: new Date(),
      lastMessageAt: null,
      members: [
        {
          userId: actorId,
          role: "ADMIN",
          user: {
            profile: { displayName: "Actor", emoji: null, avatarMediaId: null },
          },
        },
        {
          userId: friendId,
          role: "OWNER",
          user: {
            profile: {
              displayName: "Friend",
              emoji: null,
              avatarMediaId: null,
            },
          },
        },
      ],
      messages: [],
      mutes: [],
    });

    await expect(
      service.transferOwnership(actorId, conversationId, friendId),
    ).resolves.toMatchObject({ ownerId: friendId });
    const updateCalls = prismaMock.conversation.updateMany.mock
      .calls as unknown as Array<[unknown]>;
    expect(updateCalls[0]?.[0]).toMatchObject({
      where: { ownerId: actorId },
      data: { ownerId: friendId },
    });
    expect(prismaMock.conversationMember.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: { role: "ADMIN" } }),
    );
  });

  it("does not implement direct deletion through shared membership state", async () => {
    prismaMock.conversationMember.findFirst.mockResolvedValue({
      role: "MEMBER",
      conversation: {
        id: conversationId,
        type: "DIRECT",
        members: [
          { userId: actorId, role: "MEMBER" },
          { userId: friendId, role: "MEMBER" },
        ],
      },
    });
    prismaMock.block.count.mockResolvedValue(0);
    await expect(
      service.remove(actorId, conversationId),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
