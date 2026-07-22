import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { isUUID } from "class-validator";
import { AuditService } from "../../common/audit.service";
import { ContentPolicyService } from "../../common/content-policy.service";
import {
  MESSAGE_ENCRYPTION_PROVIDER,
  type MessageEncryptionProvider,
} from "../../common/message-encryption.provider";
import { PrismaService } from "../../common/prisma.service";
import { RealtimeGateway } from "../../realtime/realtime.gateway";
import type {
  AddConversationMemberDto,
  ConversationPageDto,
  ConversationSearchDto,
  CreateGroupConversationDto,
  CreateMessageDto,
  MessagePageDto,
  UpdateConversationDto,
} from "./conversations.dto";
import { TypingStateService } from "./typing.store";

type ChatRoleValue = "OWNER" | "ADMIN" | "MEMBER";
type DeleteModeValue = "NONE" | "SELF" | "EVERYONE";

interface PageCursor {
  timestamp: string;
  id: string;
}

interface MessageRecord {
  id: string;
  conversationId: string;
  senderId: string | null;
  clientMessageId: string | null;
  type: string;
  text: string | null;
  metadata: unknown;
  protectionMode: string;
  payloadVersion: number;
  replyToMessageId: string | null;
  forwardedFromMessageId: string | null;
  createdAt: Date;
  editedAt: Date | null;
  deletedAt: Date | null;
  deleteMode: DeleteModeValue;
  reactions: Array<{ userId: string; reaction: string; createdAt: Date }>;
  readReceipts: Array<{ userId: string; readAt: Date }>;
  deliveries: Array<{
    userId: string;
    state: "PENDING" | "DELIVERED" | "FAILED";
    deliveredAt: Date | null;
  }>;
  attachments: Array<{
    id: string;
    mediaId: string;
    position: number;
    media: { mimeType: string; byteSize: number };
  }>;
}

function canonicalPair(left: string, right: string): [string, string] {
  return left < right ? [left, right] : [right, left];
}

@Injectable()
export class ConversationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly content: ContentPolicyService,
    private readonly audit: AuditService,
    private readonly realtime: RealtimeGateway,
    private readonly typingState: TypingStateService,
    @Inject(MESSAGE_ENCRYPTION_PROVIDER)
    private readonly encryption: MessageEncryptionProvider,
  ) {}

  async list(userId: string, query: ConversationPageDto) {
    const cursor = query.cursor ? this.decodeCursor(query.cursor) : undefined;
    const rows = await this.prisma.conversationMember.findMany({
      where: {
        userId,
        leftAt: null,
        conversation: { deletedAt: null },
        ...(cursor && {
          OR: [
            { conversation: { updatedAt: { lt: new Date(cursor.timestamp) } } },
            {
              conversationId: { lt: cursor.id },
              conversation: { updatedAt: new Date(cursor.timestamp) },
            },
          ],
        }),
      },
      select: {
        conversationId: true,
        conversation: { select: { updatedAt: true } },
      },
      orderBy: [
        { conversation: { updatedAt: "desc" } },
        { conversationId: "desc" },
      ],
      take: query.limit + 1,
    });
    const hasMore = rows.length > query.limit;
    const page = rows.slice(0, query.limit);
    const items = (
      await Promise.all(
        page.map(({ conversationId }) => this.view(userId, conversationId)),
      )
    ).filter((item): item is NonNullable<typeof item> => item !== null);
    const last = page.at(-1);
    return {
      items,
      nextCursor:
        hasMore && last
          ? this.encodeCursor(last.conversation.updatedAt, last.conversationId)
          : null,
    };
  }

  async createDirect(userId: string, otherId: string) {
    if (userId === otherId)
      throw new BadRequestException(
        "A direct conversation requires another user",
      );
    await this.assertFriends(userId, otherId);
    await this.assertNotBlocked(userId, otherId);
    const [left, right] = canonicalPair(userId, otherId);
    const directPairKey = `${left}:${right}`;
    const existing = await this.prisma.conversation.findUnique({
      where: { directPairKey },
      select: { id: true },
    });
    const conversation = await this.prisma.conversation.upsert({
      where: { directPairKey },
      create: {
        type: "DIRECT",
        directPairKey,
        members: {
          create: [
            { userId, role: "MEMBER" },
            { userId: otherId, role: "MEMBER" },
          ],
        },
      },
      update: {
        deletedAt: null,
        updatedAt: new Date(),
      },
      select: { id: true },
    });
    await this.prisma.$transaction([
      this.prisma.conversationMember.upsert({
        where: {
          conversationId_userId: { conversationId: conversation.id, userId },
        },
        create: { conversationId: conversation.id, userId, role: "MEMBER" },
        update: { leftAt: null, role: "MEMBER" },
      }),
      this.prisma.conversationMember.upsert({
        where: {
          conversationId_userId: {
            conversationId: conversation.id,
            userId: otherId,
          },
        },
        create: {
          conversationId: conversation.id,
          userId: otherId,
          role: "MEMBER",
        },
        update: { leftAt: null, role: "MEMBER" },
      }),
    ]);
    await this.writeConversationAudit(
      conversation.id,
      userId,
      existing ? "conversation.reopened" : "conversation.created",
      otherId,
    );
    this.realtime.emitUsers([userId, otherId], "conversation.created", {
      conversationId: conversation.id,
    });
    return this.get(userId, conversation.id);
  }

  async createGroup(userId: string, dto: CreateGroupConversationDto) {
    const memberIds = [...new Set(dto.memberIds)].filter((id) => id !== userId);
    if (!memberIds.length)
      throw new BadRequestException(
        "A group requires at least one other member",
      );
    const title = dto.title.trim();
    if (!title) throw new BadRequestException("A group title is required");
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: { limitedMode: true },
    });
    await this.content.assertAllowed(title, user.limitedMode);
    await Promise.all(
      memberIds.map(async (memberId) => {
        await this.assertFriends(userId, memberId);
        await this.assertNotBlocked(userId, memberId);
      }),
    );
    if (dto.avatarMediaId) {
      const avatar = await this.prisma.mediaFile.findFirst({
        where: { id: dto.avatarMediaId, ownerId: userId, scanStatus: "clean" },
        select: { id: true },
      });
      if (!avatar) throw new BadRequestException("Group avatar is unavailable");
    }
    const conversation = await this.prisma.conversation.create({
      data: {
        type: "GROUP",
        title,
        avatarMediaId: dto.avatarMediaId,
        ownerId: userId,
        members: {
          create: [
            { userId, role: "OWNER" },
            ...memberIds.map((memberId) => ({
              userId: memberId,
              role: "MEMBER" as const,
            })),
          ],
        },
      },
      select: { id: true },
    });
    await this.writeConversationAudit(
      conversation.id,
      userId,
      "conversation.created",
    );
    this.realtime.emitUsers([userId, ...memberIds], "conversation.created", {
      conversationId: conversation.id,
    });
    return this.get(userId, conversation.id);
  }

  async get(userId: string, conversationId: string) {
    await this.assertMember(userId, conversationId);
    const value = await this.view(userId, conversationId);
    if (!value) throw this.notFound();
    return value;
  }

  async update(
    userId: string,
    conversationId: string,
    dto: UpdateConversationDto,
  ) {
    const member = await this.assertMember(userId, conversationId);
    this.assertGroupRole(member, ["OWNER", "ADMIN"]);
    if (member.conversation.type !== "GROUP")
      throw new BadRequestException("Direct conversations cannot be renamed");
    const title = dto.title?.trim();
    if (dto.title !== undefined && !title)
      throw new BadRequestException("A group title is required");
    if (title) {
      const user = await this.prisma.user.findUniqueOrThrow({
        where: { id: userId },
        select: { limitedMode: true },
      });
      await this.content.assertAllowed(title, user.limitedMode);
    }
    if (dto.avatarMediaId) {
      const avatar = await this.prisma.mediaFile.findFirst({
        where: { id: dto.avatarMediaId, ownerId: userId, scanStatus: "clean" },
        select: { id: true },
      });
      if (!avatar) throw new BadRequestException("Group avatar is unavailable");
    }
    await this.prisma.conversation.update({
      where: { id: conversationId },
      data: {
        ...(title && { title }),
        ...(dto.avatarMediaId && { avatarMediaId: dto.avatarMediaId }),
      },
    });
    await this.writeConversationAudit(
      conversationId,
      userId,
      "conversation.updated",
    );
    await this.emitMembers(conversationId, "conversation.updated", {
      conversationId,
    });
    return this.get(userId, conversationId);
  }

  async remove(userId: string, conversationId: string) {
    const member = await this.assertMember(userId, conversationId);
    if (member.conversation.type === "DIRECT")
      throw new BadRequestException(
        "Direct conversation deletion is not supported in phase 1",
      );
    this.assertGroupRole(member, ["OWNER"]);
    await this.prisma.conversation.update({
      where: { id: conversationId },
      data: { deletedAt: new Date() },
    });
    await this.writeConversationAudit(
      conversationId,
      userId,
      "conversation.deleted",
    );
    await this.emitMembers(conversationId, "conversation.deleted", {
      conversationId,
    });
    return { success: true };
  }

  async addMember(
    userId: string,
    conversationId: string,
    dto: AddConversationMemberDto,
  ) {
    if (dto.userId === userId)
      throw new BadRequestException(
        "Use role management or leave for yourself",
      );
    const member = await this.assertMember(userId, conversationId);
    this.assertGroupRole(member, ["OWNER", "ADMIN"]);
    if (member.conversation.type !== "GROUP")
      throw new BadRequestException(
        "Direct conversation membership is immutable",
      );
    if (
      dto.role === "OWNER" ||
      (dto.role === "ADMIN" && member.role !== "OWNER")
    )
      throw new ForbiddenException("Only the owner can appoint administrators");
    const existingMember = member.conversation.members.find(
      ({ userId: memberId }) => memberId === dto.userId,
    );
    if (existingMember)
      throw new ConflictException("The user is already an active member");
    if (member.conversation.members.length >= 100)
      throw new BadRequestException("A group cannot exceed 100 active members");
    await this.assertFriends(userId, dto.userId);
    await this.assertNotBlocked(userId, dto.userId);
    await this.prisma.conversationMember.upsert({
      where: { conversationId_userId: { conversationId, userId: dto.userId } },
      create: { conversationId, userId: dto.userId, role: dto.role },
      update: { leftAt: null, joinedAt: new Date(), role: dto.role },
    });
    await this.writeConversationAudit(
      conversationId,
      userId,
      "conversation.member.added",
      dto.userId,
    );
    await this.emitMembers(conversationId, "conversation.member.added", {
      conversationId,
      userId: dto.userId,
      role: dto.role,
    });
    this.realtime.emitUser(dto.userId, "conversation.created", {
      conversationId,
    });
    return this.get(userId, conversationId);
  }

  async removeMember(userId: string, conversationId: string, targetId: string) {
    if (userId === targetId)
      throw new BadRequestException(
        "Use the leave endpoint to remove yourself",
      );
    const member = await this.assertMember(userId, conversationId);
    this.assertGroupRole(member, ["OWNER", "ADMIN"]);
    if (member.conversation.type !== "GROUP")
      throw new BadRequestException(
        "Direct conversation membership is immutable",
      );
    const target = await this.prisma.conversationMember.findFirst({
      where: { conversationId, userId: targetId, leftAt: null },
      select: { role: true },
    });
    if (!target) throw this.notFound();
    if (
      target.role === "OWNER" ||
      (target.role === "ADMIN" && member.role !== "OWNER")
    )
      throw new ForbiddenException(
        "This member cannot be removed by the current role",
      );
    await this.prisma.conversationMember.update({
      where: { conversationId_userId: { conversationId, userId: targetId } },
      data: { leftAt: new Date() },
    });
    this.realtime.evictUserFromConversation(targetId, conversationId);
    await this.typingState.delete(conversationId, targetId);
    await this.writeConversationAudit(
      conversationId,
      userId,
      "conversation.member.removed",
      targetId,
    );
    await this.emitMembers(
      conversationId,
      "conversation.member.removed",
      {
        conversationId,
        userId: targetId,
      },
      [targetId],
    );
    return { success: true };
  }

  async leave(userId: string, conversationId: string) {
    const member = await this.assertMember(userId, conversationId);
    if (member.conversation.type === "DIRECT")
      throw new BadRequestException(
        "Direct conversations cannot be left in phase 1",
      );
    if (member.role === "OWNER")
      throw new BadRequestException(
        "Transfer ownership before leaving the group",
      );
    await this.prisma.$transaction([
      this.prisma.conversationMember.update({
        where: { conversationId_userId: { conversationId, userId } },
        data: { leftAt: new Date() },
      }),
      this.prisma.chatMute.deleteMany({ where: { conversationId, userId } }),
      this.prisma.conversationDraft.deleteMany({
        where: { conversationId, userId },
      }),
    ]);
    this.realtime.evictUserFromConversation(userId, conversationId);
    await this.typingState.delete(conversationId, userId);
    await this.writeConversationAudit(
      conversationId,
      userId,
      "conversation.member.left",
    );
    await this.emitMembers(
      conversationId,
      "conversation.member.removed",
      {
        conversationId,
        userId,
      },
      [userId],
    );
    return { success: true };
  }

  async transferOwnership(
    userId: string,
    conversationId: string,
    targetUserId: string,
  ) {
    if (targetUserId === userId)
      throw new BadRequestException("The target is already the owner");
    const member = await this.assertMember(userId, conversationId);
    this.assertGroupRole(member, ["OWNER"]);
    const target = member.conversation.members.find(
      ({ userId: memberId }) => memberId === targetUserId,
    );
    if (!target) throw this.notFound();

    await this.prisma.$transaction(async (tx) => {
      const promoted = await tx.conversationMember.updateMany({
        where: { conversationId, userId: targetUserId, leftAt: null },
        data: { role: "OWNER" },
      });
      if (promoted.count !== 1)
        throw new ConflictException("The target is no longer an active member");
      const changed = await tx.conversation.updateMany({
        where: {
          id: conversationId,
          type: "GROUP",
          ownerId: userId,
          deletedAt: null,
        },
        data: { ownerId: targetUserId },
      });
      if (changed.count !== 1)
        throw new ConflictException("Conversation ownership has changed");
      await tx.conversationMember.update({
        where: {
          conversationId_userId: { conversationId, userId },
        },
        data: { role: "ADMIN" },
      });
    });
    await this.writeConversationAudit(
      conversationId,
      userId,
      "conversation.ownership.transferred",
      targetUserId,
    );
    await this.emitMembers(conversationId, "conversation.updated", {
      conversationId,
      ownerId: targetUserId,
      previousOwnerId: userId,
    });
    return this.get(userId, conversationId);
  }

  async mute(userId: string, conversationId: string, rawUntil?: string) {
    await this.assertMember(userId, conversationId);
    const mutedUntil = rawUntil
      ? new Date(rawUntil)
      : new Date("9999-12-31T23:59:59.999Z");
    if (mutedUntil <= new Date())
      throw new BadRequestException("Mute expiry must be in the future");
    await this.prisma.chatMute.upsert({
      where: { conversationId_userId: { conversationId, userId } },
      create: { conversationId, userId, mutedUntil },
      update: { mutedUntil },
    });
    await this.audit.write({
      actorUserId: userId,
      action: "conversation.muted",
      resourceType: "conversation",
      resourceId: conversationId,
      metadata: { mutedUntil: mutedUntil.toISOString() },
    });
    return { success: true, mutedUntil };
  }

  async unmute(userId: string, conversationId: string) {
    await this.assertMember(userId, conversationId);
    await this.prisma.chatMute.deleteMany({
      where: { conversationId, userId },
    });
    await this.audit.write({
      actorUserId: userId,
      action: "conversation.unmuted",
      resourceType: "conversation",
      resourceId: conversationId,
    });
    return { success: true };
  }

  async messages(
    userId: string,
    conversationId: string,
    query: MessagePageDto,
  ) {
    const member = await this.assertMember(userId, conversationId);
    const cursor = query.cursor ? this.decodeCursor(query.cursor) : undefined;
    const rows = await this.prisma.message.findMany({
      where: {
        conversationId,
        ...(cursor && {
          OR: [
            { createdAt: { lt: new Date(cursor.timestamp) } },
            { createdAt: new Date(cursor.timestamp), id: { lt: cursor.id } },
          ],
        }),
      },
      select: this.messageSelect(),
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: query.limit + 1,
    });
    const hasMore = rows.length > query.limit;
    const page = rows.slice(0, query.limit);
    if (member.directFriendshipActive)
      await this.acknowledgeDeliveries(userId, conversationId, page);
    const last = page.at(-1);
    return {
      items: page.map((message) => this.mapMessage(userId, message)),
      nextCursor:
        hasMore && last ? this.encodeCursor(last.createdAt, last.id) : null,
    };
  }

  async createMessage(
    userId: string,
    conversationId: string,
    dto: CreateMessageDto,
  ) {
    const member = await this.assertMember(userId, conversationId, {
      requireDirectFriendship: true,
    });
    const existing = await this.prisma.message.findUnique({
      where: {
        senderId_clientMessageId: {
          senderId: userId,
          clientMessageId: dto.clientMessageId,
        },
      },
      select: this.messageSelect(),
    });
    const shape = this.normalizeMessageShape(dto);
    if (existing)
      return this.resolveIdempotent(userId, conversationId, existing, shape);
    const normalized = await this.validateMessage(userId, member, dto, shape);
    const recent = await this.prisma.message.count({
      where: {
        senderId: userId,
        createdAt: { gte: new Date(Date.now() - 60_000) },
      },
    });
    if (recent >= 30)
      throw new ForbiddenException("Message rate limit exceeded");
    const createdAt = new Date();
    const persisted = this.encryption.toPersistence({
      text: normalized.text,
      metadata: normalized.metadata,
    });
    let message: MessageRecord;
    try {
      message = await this.prisma.$transaction(async (tx) => {
        const created = await tx.message.create({
          data: {
            conversationId,
            senderId: userId,
            clientMessageId: dto.clientMessageId,
            type: dto.type,
            text: persisted.text,
            metadata: persisted.metadata,
            protectionMode: persisted.mode,
            payloadVersion: persisted.version,
            replyToMessageId: dto.replyToMessageId,
            forwardedFromMessageId: dto.forwardedFromMessageId,
            createdAt,
            readReceipts: { create: { userId, readAt: createdAt } },
            deliveries: {
              create: member.conversation.members
                .filter(({ userId: recipientId }) => recipientId !== userId)
                .map(({ userId: recipientId }) => ({ userId: recipientId })),
            },
          },
          select: this.messageSelect(),
        });
        await tx.conversation.update({
          where: { id: conversationId },
          data: { lastMessageAt: createdAt, updatedAt: createdAt },
        });
        return created;
      });
    } catch (error) {
      const raced = await this.prisma.message.findUnique({
        where: {
          senderId_clientMessageId: {
            senderId: userId,
            clientMessageId: dto.clientMessageId,
          },
        },
        select: this.messageSelect(),
      });
      if (!raced) throw error;
      return this.resolveIdempotent(userId, conversationId, raced, normalized);
    }
    const payload = this.mapMessage(userId, message);
    const realtimeMessage = this.mapMessage(userId, message, false);
    await this.audit.write({
      actorUserId: userId,
      action: "message.sent",
      resourceType: "message",
      resourceId: message.id,
      metadata: { conversationId, type: message.type },
    });
    await this.emitMembers(conversationId, "message.created", {
      conversationId,
      message: realtimeMessage,
    });
    return payload;
  }

  async editMessage(userId: string, messageId: string, text: string) {
    const message = await this.messageForMember(userId, messageId, true);
    if (message.senderId !== userId || message.type !== "TEXT")
      throw new ForbiddenException("Only the author can edit a text message");
    if (message.deleteMode !== "NONE")
      throw new BadRequestException("Deleted messages cannot be edited");
    if (Date.now() - message.createdAt.getTime() > 15 * 60_000)
      throw new ForbiddenException("The edit window has expired");
    const normalizedText = text.trim();
    if (!normalizedText)
      throw new BadRequestException("Message text is required");
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: { limitedMode: true },
    });
    await this.content.assertAllowed(normalizedText, user.limitedMode);
    const editedAt = new Date();
    const updated = await this.prisma.$transaction(async (tx) => {
      await tx.messageEdit.create({
        data: {
          messageId,
          editorId: userId,
          previousText: message.text,
          newText: normalizedText,
        },
      });
      return tx.message.update({
        where: { id: messageId },
        data: { text: normalizedText, editedAt },
        select: this.messageSelect(),
      });
    });
    const payload = this.mapMessage(userId, updated);
    const realtimeMessage = this.mapMessage(userId, updated, false);
    await this.writeMessageAudit(
      userId,
      "message.edited",
      messageId,
      message.conversationId,
    );
    await this.emitMembers(message.conversationId, "message.updated", {
      conversationId: message.conversationId,
      message: realtimeMessage,
    });
    return payload;
  }

  async deleteMessage(
    userId: string,
    messageId: string,
    mode: "SELF" | "EVERYONE",
  ) {
    const message = await this.messageForMember(userId, messageId);
    if (message.senderId !== userId)
      throw new ForbiddenException("Only the author can delete this message");
    if (
      mode === "EVERYONE" &&
      Date.now() - message.createdAt.getTime() > 15 * 60_000
    )
      throw new ForbiddenException(
        "The delete-for-everyone window has expired",
      );
    if (mode === "EVERYONE")
      await this.assertMember(userId, message.conversationId, {
        requireDirectFriendship: true,
      });
    const deletedAt = new Date();
    const updated = await this.prisma.message.update({
      where: { id: messageId },
      data: {
        deleteMode: mode,
        deletedAt,
        ...(mode === "EVERYONE" && { text: null, metadata: {} }),
      },
      select: this.messageSelect(),
    });
    const payload = this.mapMessage(userId, updated);
    const eventPayload = {
      conversationId: message.conversationId,
      message:
        mode === "SELF" ? payload : this.mapMessage(userId, updated, false),
    };
    await this.writeMessageAudit(
      userId,
      "message.deleted",
      messageId,
      message.conversationId,
      { mode },
    );
    if (mode === "SELF") {
      this.realtime.emitUser(userId, "message.deleted", eventPayload);
    } else {
      await this.emitMembers(
        message.conversationId,
        "message.deleted",
        eventPayload,
      );
    }
    return payload;
  }

  async addReaction(userId: string, messageId: string, reaction: string) {
    const message = await this.messageForMember(userId, messageId, true);
    if (message.deleteMode === "EVERYONE") throw this.notFound();
    const value = reaction.trim();
    if (!value || [...value].length > 16)
      throw new BadRequestException("Invalid reaction");
    const created = await this.prisma.messageReaction.upsert({
      where: {
        messageId_userId_reaction: { messageId, userId, reaction: value },
      },
      create: { messageId, userId, reaction: value },
      update: {},
    });
    await this.writeMessageAudit(
      userId,
      "message.reaction.added",
      messageId,
      message.conversationId,
    );
    await this.emitMembers(message.conversationId, "message.reaction.added", {
      conversationId: message.conversationId,
      messageId,
      userId,
      reaction: value,
      createdAt: created.createdAt,
    });
    return created;
  }

  async removeReaction(userId: string, messageId: string, reaction: string) {
    const message = await this.messageForMember(userId, messageId, true);
    await this.prisma.messageReaction.deleteMany({
      where: { messageId, userId, reaction },
    });
    await this.writeMessageAudit(
      userId,
      "message.reaction.removed",
      messageId,
      message.conversationId,
    );
    await this.emitMembers(message.conversationId, "message.reaction.removed", {
      conversationId: message.conversationId,
      messageId,
      userId,
      reaction,
    });
    return { success: true };
  }

  async markRead(userId: string, messageId: string) {
    const target = await this.messageForMember(userId, messageId, true);
    const unread = await this.prisma.message.findMany({
      where: {
        conversationId: target.conversationId,
        senderId: { not: userId },
        createdAt: { lte: target.createdAt },
        readReceipts: { none: { userId } },
      },
      select: { id: true },
    });
    const readAt = new Date();
    await this.prisma.$transaction(async (tx) => {
      if (unread.length) {
        await tx.messageReadReceipt.createMany({
          data: unread.map(({ id }) => ({ messageId: id, userId, readAt })),
          skipDuplicates: true,
        });
        await tx.messageDelivery.updateMany({
          where: { userId, messageId: { in: unread.map(({ id }) => id) } },
          data: { state: "DELIVERED", deliveredAt: readAt },
        });
      }
      await tx.messageReadReceipt.upsert({
        where: { messageId_userId: { messageId, userId } },
        create: { messageId, userId, readAt },
        update: { readAt },
      });
    });
    const payload = { success: true, messageId, readAt };
    await this.audit.write({
      actorUserId: userId,
      action: "message.read",
      resourceType: "message",
      resourceId: messageId,
      metadata: { conversationId: target.conversationId },
    });
    await this.emitMembers(target.conversationId, "message.read", {
      conversationId: target.conversationId,
      messageId,
      userId,
      readAt,
    });
    return payload;
  }

  async pin(userId: string, messageId: string) {
    const message = await this.messageForMember(userId, messageId, true);
    const member = await this.assertMember(userId, message.conversationId, {
      requireDirectFriendship: true,
    });
    if (member.conversation.type === "GROUP")
      this.assertGroupRole(member, ["OWNER", "ADMIN"]);
    const pin = await this.prisma.pinnedMessage.upsert({
      where: {
        conversationId_messageId: {
          conversationId: message.conversationId,
          messageId,
        },
      },
      create: {
        conversationId: message.conversationId,
        messageId,
        pinnedById: userId,
      },
      update: { pinnedById: userId, pinnedAt: new Date() },
    });
    await this.writeMessageAudit(
      userId,
      "message.pinned",
      messageId,
      message.conversationId,
    );
    return pin;
  }

  async unpin(userId: string, messageId: string) {
    const message = await this.messageForMember(userId, messageId, true);
    const member = await this.assertMember(userId, message.conversationId, {
      requireDirectFriendship: true,
    });
    if (member.conversation.type === "GROUP")
      this.assertGroupRole(member, ["OWNER", "ADMIN"]);
    await this.prisma.pinnedMessage.deleteMany({
      where: { conversationId: message.conversationId, messageId },
    });
    await this.writeMessageAudit(
      userId,
      "message.unpinned",
      messageId,
      message.conversationId,
    );
    return { success: true };
  }

  async search(
    userId: string,
    conversationId: string,
    query: ConversationSearchDto,
  ) {
    await this.assertMember(userId, conversationId);
    const text = query.query.trim();
    if (!text) throw new BadRequestException("A search query is required");
    const rows = await this.prisma.message.findMany({
      where: {
        conversationId,
        text: { contains: text, mode: "insensitive" },
        OR: [
          { deleteMode: "NONE" },
          { deleteMode: "SELF", senderId: { not: userId } },
        ],
      },
      select: this.messageSelect(),
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: query.limit,
    });
    return { items: rows.map((message) => this.mapMessage(userId, message)) };
  }

  async typing(userId: string, conversationId: string, active: boolean) {
    await this.assertMember(userId, conversationId, {
      requireDirectFriendship: true,
    });
    const expiresAt = active
      ? await this.typingState.set(conversationId, userId)
      : (await this.typingState.delete(conversationId, userId), null);
    this.realtime.emitConversation(
      conversationId,
      active ? "typing.started" : "typing.stopped",
      { conversationId, userId, ...(expiresAt && { expiresAt }) },
    );
    return { success: true, active, expiresAt };
  }

  async saveDraft(userId: string, conversationId: string, text: string) {
    await this.assertMember(userId, conversationId, {
      requireDirectFriendship: true,
    });
    if (!text.trim()) {
      await this.prisma.conversationDraft.deleteMany({
        where: { conversationId, userId },
      });
      await this.audit.write({
        actorUserId: userId,
        action: "conversation.draft.deleted",
        resourceType: "conversation",
        resourceId: conversationId,
      });
      return { text: "", updatedAt: null };
    }
    const draft = await this.prisma.conversationDraft.upsert({
      where: { conversationId_userId: { conversationId, userId } },
      create: { conversationId, userId, text },
      update: { text },
      select: { text: true, updatedAt: true },
    });
    await this.audit.write({
      actorUserId: userId,
      action: "conversation.draft.saved",
      resourceType: "conversation",
      resourceId: conversationId,
    });
    return draft;
  }

  async draft(userId: string, conversationId: string) {
    await this.assertMember(userId, conversationId);
    return this.prisma.conversationDraft.findUnique({
      where: { conversationId_userId: { conversationId, userId } },
      select: { text: true, updatedAt: true },
    });
  }

  private async view(userId: string, conversationId: string) {
    const [conversation, unreadCount] = await Promise.all([
      this.prisma.conversation.findFirst({
        where: {
          id: conversationId,
          deletedAt: null,
          members: { some: { userId, leftAt: null } },
        },
        select: {
          id: true,
          type: true,
          title: true,
          avatarMediaId: true,
          ownerId: true,
          createdAt: true,
          updatedAt: true,
          lastMessageAt: true,
          members: {
            where: { leftAt: null },
            select: {
              userId: true,
              role: true,
              user: {
                select: {
                  profile: {
                    select: {
                      displayName: true,
                      emoji: true,
                      avatarMediaId: true,
                    },
                  },
                },
              },
            },
          },
          messages: {
            orderBy: [{ createdAt: "desc" }, { id: "desc" }],
            take: 1,
            select: this.messageSelect(),
          },
          mutes: {
            where: { userId },
            select: { mutedUntil: true },
            take: 1,
          },
        },
      }),
      this.prisma.message.count({
        where: {
          conversationId,
          senderId: { not: userId },
          deleteMode: { not: "EVERYONE" },
          readReceipts: { none: { userId } },
        },
      }),
    ]);
    if (!conversation) return null;
    let directFriendshipActive = true;
    if (conversation.type === "DIRECT") {
      const other = conversation.members.find(
        ({ userId: id }) => id !== userId,
      );
      if (!other || (await this.isBlocked(userId, other.userId))) return null;
      directFriendshipActive = await this.areFriends(userId, other.userId);
    }
    const membership = conversation.members.find(
      (member) => member.userId === userId,
    );
    if (!membership) return null;
    return {
      id: conversation.id,
      type: conversation.type,
      title: conversation.title,
      avatarMediaId: conversation.avatarMediaId,
      ownerId: conversation.ownerId,
      createdAt: conversation.createdAt,
      updatedAt: conversation.updatedAt,
      lastMessageAt: conversation.lastMessageAt,
      membership: {
        role: membership.role,
        mutedUntil: conversation.mutes[0]?.mutedUntil ?? null,
      },
      members: conversation.members.map((member) => ({
        userId: member.userId,
        role: member.role,
        displayName: member.user.profile?.displayName ?? "User",
        emoji: member.user.profile?.emoji ?? null,
        avatarMediaId: member.user.profile?.avatarMediaId ?? null,
      })),
      lastMessage: conversation.messages[0]
        ? this.mapMessage(userId, conversation.messages[0])
        : null,
      unreadCount,
      isArchived: !directFriendshipActive,
    };
  }

  private async assertMember(
    userId: string,
    conversationId: string,
    options: { requireDirectFriendship?: boolean } = {},
  ) {
    const member = await this.prisma.conversationMember.findFirst({
      where: {
        conversationId,
        userId,
        leftAt: null,
        conversation: { deletedAt: null },
      },
      select: {
        role: true,
        conversation: {
          select: {
            id: true,
            type: true,
            members: {
              where: { leftAt: null },
              select: { userId: true, role: true },
            },
          },
        },
      },
    });
    if (!member) throw this.notFound();
    let directFriendshipActive = true;
    if (member.conversation.type === "DIRECT") {
      const other = member.conversation.members.find(
        ({ userId: id }) => id !== userId,
      );
      if (!other) throw this.notFound();
      await this.assertNotBlocked(userId, other.userId, true);
      directFriendshipActive = await this.areFriends(userId, other.userId);
      if (options.requireDirectFriendship && !directFriendshipActive)
        throw new ForbiddenException(
          "Direct conversation interaction requires mutual friendship",
        );
    }
    return { ...member, directFriendshipActive };
  }

  private assertGroupRole(
    member: { role: ChatRoleValue; conversation: { type: string } },
    roles: ChatRoleValue[],
  ) {
    if (member.conversation.type !== "GROUP" || !roles.includes(member.role))
      throw new ForbiddenException("Insufficient conversation role");
  }

  private async assertFriends(left: string, right: string) {
    if (!(await this.areFriends(left, right)))
      throw new ForbiddenException(
        "Conversations can only include mutual friends",
      );
  }

  private async areFriends(left: string, right: string) {
    const [userAId, userBId] = canonicalPair(left, right);
    const friendship = await this.prisma.friendship.findFirst({
      where: { userAId, userBId, status: "ACCEPTED" },
      select: { id: true },
    });
    return Boolean(friendship);
  }

  private async assertNotBlocked(left: string, right: string, hide = false) {
    const blocked = await this.isBlocked(left, right);
    if (blocked) {
      if (hide) throw this.notFound();
      throw new ForbiddenException("A block prevents this conversation action");
    }
  }

  private async isBlocked(left: string, right: string) {
    const blocked = await this.prisma.block.count({
      where: {
        OR: [
          { blockerId: left, blockedId: right },
          { blockerId: right, blockedId: left },
        ],
      },
    });
    return blocked > 0;
  }

  private async messageForMember(
    userId: string,
    messageId: string,
    requireDirectFriendship = false,
  ) {
    const message = await this.prisma.message.findFirst({
      where: {
        id: messageId,
        conversation: {
          deletedAt: null,
          members: { some: { userId, leftAt: null } },
        },
      },
      select: this.messageSelect(),
    });
    if (!message) throw this.notFound();
    await this.assertMember(userId, message.conversationId, {
      requireDirectFriendship,
    });
    return message;
  }

  private normalizeMessageShape(dto: CreateMessageDto) {
    if (!(["TEXT", "SIGNAL"] as string[]).includes(dto.type))
      throw new BadRequestException(
        "This message type is not enabled in phase 1",
      );
    let text = dto.text?.trim() ?? null;
    let metadata: Record<string, string | number | boolean | null> = {};
    if (dto.type === "TEXT") {
      if (!text) throw new BadRequestException("Text is required");
    } else {
      const signalId = dto.metadata?.signalId;
      if (typeof signalId !== "string" || !isUUID(signalId))
        throw new BadRequestException("A valid metadata.signalId is required");
      metadata = { signalId };
      text = null;
    }
    return {
      text,
      metadata,
      type: dto.type,
      replyToMessageId: dto.replyToMessageId ?? null,
      forwardedFromMessageId: dto.forwardedFromMessageId ?? null,
    };
  }

  private async validateMessage(
    userId: string,
    member: Awaited<ReturnType<ConversationsService["assertMember"]>>,
    dto: CreateMessageDto,
    normalized: ReturnType<ConversationsService["normalizeMessageShape"]>,
  ) {
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      select: { limitedMode: true },
    });
    if (dto.type === "TEXT") {
      await this.content.assertAllowed(normalized.text!, user.limitedMode);
    } else {
      await this.assertSignalVisibleToConversation(
        userId,
        normalized.metadata.signalId as string,
        member.conversation.members,
      );
    }
    if (dto.replyToMessageId) {
      const reply = await this.prisma.message.findFirst({
        where: {
          id: dto.replyToMessageId,
          conversationId: member.conversation.id,
          deleteMode: { not: "EVERYONE" },
        },
        select: { id: true },
      });
      if (!reply) throw new BadRequestException("Reply target is unavailable");
    }
    if (dto.forwardedFromMessageId) {
      await this.messageForMember(userId, dto.forwardedFromMessageId);
    }
    return normalized;
  }

  private async assertSignalVisibleToConversation(
    actorId: string,
    signalId: string,
    members: Array<{ userId: string }>,
  ) {
    const signal = await this.prisma.signal.findFirst({
      where: {
        id: signalId,
        authorId: actorId,
        state: { in: ["ACTIVE", "FULL"] },
        expiresAt: { gt: new Date() },
      },
      select: { id: true },
    });
    if (!signal) throw new ForbiddenException("Signal is unavailable");
    const checks = await Promise.all(
      members
        .filter(({ userId }) => userId !== actorId)
        .map(({ userId }) =>
          this.prisma.signalVisibility.count({
            where: {
              signalId,
              OR: [{ userId }, { circle: { members: { some: { userId } } } }],
            },
          }),
        ),
    );
    if (checks.some((count) => count === 0))
      throw new ForbiddenException(
        "Signal is not visible to every conversation member",
      );
  }

  private resolveIdempotent(
    userId: string,
    conversationId: string,
    existing: MessageRecord,
    normalized: {
      text: string | null;
      metadata: Record<string, string | number | boolean | null>;
      type: string;
      replyToMessageId: string | null;
      forwardedFromMessageId: string | null;
    },
  ) {
    if (
      existing.conversationId !== conversationId ||
      existing.type !== normalized.type ||
      existing.text !== normalized.text ||
      existing.replyToMessageId !== normalized.replyToMessageId ||
      existing.forwardedFromMessageId !== normalized.forwardedFromMessageId ||
      this.stableJson(existing.metadata) !==
        this.stableJson(normalized.metadata)
    ) {
      throw new ConflictException(
        "clientMessageId was already used for different content",
      );
    }
    return this.mapMessage(userId, existing);
  }

  private mapMessage(
    userId: string,
    message: MessageRecord,
    includeDeliveryStatus = true,
  ) {
    const restored = this.encryption.fromPersistence({
      mode: message.protectionMode,
      version: message.payloadVersion,
      text: message.text,
      metadata: message.metadata,
    });
    const hiddenForViewer =
      message.deleteMode === "EVERYONE" ||
      (message.deleteMode === "SELF" && message.senderId === userId);
    const visibleMode =
      message.deleteMode === "SELF" && message.senderId !== userId
        ? "NONE"
        : message.deleteMode;
    const deliveryStatus =
      message.senderId === userId
        ? message.readReceipts.some(
            ({ userId: readerId }) => readerId !== userId,
          )
          ? "READ"
          : message.deliveries.some(({ state }) => state === "DELIVERED")
            ? "DELIVERED"
            : message.deliveries.length > 0 &&
                message.deliveries.every(({ state }) => state === "FAILED")
              ? "FAILED"
              : "SENT"
        : undefined;
    return {
      id: message.id,
      conversationId: message.conversationId,
      senderId: message.senderId,
      clientMessageId: message.clientMessageId,
      type: message.type,
      text: hiddenForViewer ? null : restored.text,
      metadata: hiddenForViewer ? {} : restored.metadata,
      replyToMessageId: message.replyToMessageId,
      forwardedFromMessageId: message.forwardedFromMessageId,
      createdAt: message.createdAt,
      editedAt: hiddenForViewer ? null : message.editedAt,
      deletedAt: visibleMode === "NONE" ? null : message.deletedAt,
      deleteMode: visibleMode,
      reactions: hiddenForViewer ? [] : message.reactions,
      attachments: hiddenForViewer
        ? []
        : message.attachments.map((attachment) => ({
            id: attachment.id,
            mediaId: attachment.mediaId,
            position: attachment.position,
            mimeType: attachment.media.mimeType,
            byteSize: attachment.media.byteSize,
          })),
      readReceipts: message.readReceipts,
      ...(includeDeliveryStatus && deliveryStatus && { deliveryStatus }),
    };
  }

  private messageSelect() {
    return {
      id: true,
      conversationId: true,
      senderId: true,
      clientMessageId: true,
      type: true,
      text: true,
      metadata: true,
      protectionMode: true,
      payloadVersion: true,
      replyToMessageId: true,
      forwardedFromMessageId: true,
      createdAt: true,
      editedAt: true,
      deletedAt: true,
      deleteMode: true,
      reactions: {
        select: { userId: true, reaction: true, createdAt: true },
        orderBy: { createdAt: "asc" as const },
      },
      attachments: {
        select: {
          id: true,
          mediaId: true,
          position: true,
          media: { select: { mimeType: true, byteSize: true } },
        },
        orderBy: { position: "asc" as const },
      },
      readReceipts: {
        select: { userId: true, readAt: true },
        orderBy: { readAt: "asc" as const },
      },
      deliveries: {
        select: { userId: true, state: true, deliveredAt: true },
        orderBy: { userId: "asc" as const },
      },
    } as const;
  }

  private async acknowledgeDeliveries(
    userId: string,
    conversationId: string,
    messages: MessageRecord[],
  ) {
    const messageIds = messages
      .filter(
        (message) =>
          message.senderId !== userId && message.deleteMode !== "EVERYONE",
      )
      .map(({ id }) => id);
    if (!messageIds.length) return;
    const deliveredAt = new Date();
    const delivered = await this.prisma.messageDelivery.updateManyAndReturn({
      where: { userId, messageId: { in: messageIds }, state: "PENDING" },
      data: { state: "DELIVERED", deliveredAt, failedAt: null },
      select: { messageId: true },
    });
    if (!delivered.length) return;
    const members = await this.prisma.conversationMember.findMany({
      where: { conversationId, leftAt: null },
      select: { userId: true },
    });
    const memberIds = members.map(({ userId: memberId }) => memberId);
    for (const { messageId } of delivered) {
      this.realtime.emitUsers(memberIds, "message.delivered", {
        conversationId,
        messageId,
        userId,
        deliveredAt,
      });
    }
  }

  private async writeConversationAudit(
    conversationId: string,
    actorUserId: string,
    action: string,
    targetUserId?: string,
  ) {
    await this.prisma.chatAuditEvent.create({
      data: { conversationId, actorUserId, targetUserId, action },
    });
    await this.audit.write({
      actorUserId,
      action,
      resourceType: "conversation",
      resourceId: conversationId,
      metadata: targetUserId ? { targetUserId } : {},
    });
  }

  private async writeMessageAudit(
    actorUserId: string,
    action: string,
    messageId: string,
    conversationId: string,
    metadata: Record<string, string | number | boolean | null> = {},
  ) {
    await this.audit.write({
      actorUserId,
      action,
      resourceType: "message",
      resourceId: messageId,
      metadata: { conversationId, ...metadata },
    });
  }

  private async emitMembers(
    conversationId: string,
    event: string,
    payload: Record<string, unknown>,
    additionalUserIds: string[] = [],
  ) {
    const members = await this.prisma.conversationMember.findMany({
      where: { conversationId, leftAt: null },
      select: { userId: true },
    });
    this.realtime.emitUsers(
      [...members.map(({ userId }) => userId), ...additionalUserIds],
      event,
      payload,
    );
  }

  private encodeCursor(timestamp: Date, id: string) {
    return Buffer.from(
      JSON.stringify({ timestamp: timestamp.toISOString(), id }),
    ).toString("base64url");
  }

  private decodeCursor(value: string): PageCursor {
    try {
      const parsed = JSON.parse(
        Buffer.from(value, "base64url").toString("utf8"),
      ) as Partial<PageCursor>;
      if (
        typeof parsed.timestamp !== "string" ||
        Number.isNaN(new Date(parsed.timestamp).getTime()) ||
        typeof parsed.id !== "string" ||
        !isUUID(parsed.id)
      ) {
        throw new Error("invalid cursor");
      }
      return { timestamp: parsed.timestamp, id: parsed.id };
    } catch {
      throw new BadRequestException("Invalid pagination cursor");
    }
  }

  private stableJson(value: unknown): string {
    if (!value || typeof value !== "object" || Array.isArray(value))
      return JSON.stringify(value);
    return JSON.stringify(
      Object.fromEntries(
        Object.entries(value as Record<string, unknown>).sort(
          ([left], [right]) => left.localeCompare(right),
        ),
      ),
    );
  }

  private notFound() {
    return new NotFoundException("Conversation resource not found");
  }
}
