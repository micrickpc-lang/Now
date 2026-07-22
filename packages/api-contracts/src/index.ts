export type IsoDateTime = string;

export type JsonPrimitive = boolean | number | string | null;
export type JsonValue = JsonPrimitive | JsonObject | JsonValue[];

export interface JsonObject {
  [key: string]: JsonValue;
}

export const ConversationType = {
  DIRECT: "DIRECT",
  GROUP: "GROUP",
} as const;

export type ConversationType =
  (typeof ConversationType)[keyof typeof ConversationType];

export const ConversationRole = {
  OWNER: "OWNER",
  ADMIN: "ADMIN",
  MEMBER: "MEMBER",
} as const;

export type ConversationRole =
  (typeof ConversationRole)[keyof typeof ConversationRole];

export const MessageType = {
  TEXT: "TEXT",
  IMAGE: "IMAGE",
  VIDEO: "VIDEO",
  VOICE: "VOICE",
  FILE: "FILE",
  LOCATION: "LOCATION",
  SYSTEM: "SYSTEM",
  SIGNAL: "SIGNAL",
  CALL: "CALL",
  POLL: "POLL",
  STORY_REPLY: "STORY_REPLY",
} as const;

export type MessageType = (typeof MessageType)[keyof typeof MessageType];

export const MessageDeleteMode = {
  NONE: "NONE",
  SELF: "SELF",
  EVERYONE: "EVERYONE",
} as const;

export type MessageDeleteMode =
  (typeof MessageDeleteMode)[keyof typeof MessageDeleteMode];

export const MessageDeliveryStatus = {
  PENDING: "PENDING",
  SENT: "SENT",
  DELIVERED: "DELIVERED",
  READ: "READ",
  FAILED: "FAILED",
} as const;

export type MessageDeliveryStatus =
  (typeof MessageDeliveryStatus)[keyof typeof MessageDeliveryStatus];

export type LocationMode =
  | "NONE"
  | "CITY"
  | "DISTRICT"
  | "APPROXIMATE"
  | "EXACT_ROOM";

export type SignalState =
  | "DRAFT"
  | "ACTIVE"
  | "FULL"
  | "EXPIRED"
  | "CANCELLED"
  | "COMPLETED"
  | "MODERATED";

export interface ConversationMember {
  userId: string;
  role: ConversationRole;
  displayName: string;
  emoji: string | null;
  avatarMediaId: string | null;
}

export interface ConversationMembership {
  role: ConversationRole;
  mutedUntil: IsoDateTime | null;
}

export interface MessageReadReceipt {
  userId: string;
  readAt: IsoDateTime;
}

export interface MessageReaction {
  userId: string;
  reaction: string;
  createdAt: IsoDateTime;
}

export interface MessageAttachment {
  id: string;
  mediaId: string;
  position: number;
  mimeType: string;
  byteSize: number;
}

export interface Message {
  id: string;
  conversationId: string;
  senderId: string | null;
  clientMessageId: string | null;
  type: MessageType;
  text: string | null;
  metadata: JsonObject;
  replyToMessageId: string | null;
  forwardedFromMessageId: string | null;
  createdAt: IsoDateTime;
  editedAt: IsoDateTime | null;
  deletedAt: IsoDateTime | null;
  deleteMode: MessageDeleteMode;
  reactions: MessageReaction[];
  attachments: MessageAttachment[];
  readReceipts: MessageReadReceipt[];
  /** Present for the sender; omitted from recipient views. */
  deliveryStatus?: MessageDeliveryStatus;
}

export interface ConversationSummary {
  id: string;
  type: ConversationType;
  title: string | null;
  avatarMediaId: string | null;
  ownerId: string | null;
  createdAt: IsoDateTime;
  updatedAt: IsoDateTime;
  lastMessageAt: IsoDateTime | null;
  membership: ConversationMembership;
  members: ConversationMember[];
  lastMessage: Message | null;
  unreadCount: number;
  /** Optional presentation state currently supplied by the mobile cache. */
  isPinned?: boolean;
  isArchived?: boolean;
  isTyping?: boolean;
  hasActiveCall?: boolean;
  hasActiveSignal?: boolean;
}

export interface ConversationPage {
  items: ConversationSummary[];
  nextCursor: string | null;
}

export interface MessagePage {
  items: Message[];
  nextCursor: string | null;
}

export interface CreateDirectConversationDto {
  friendId: string;
}

export interface CreateGroupConversationDto {
  title: string;
  memberIds: string[];
  avatarMediaId?: string;
}

export interface TransferConversationOwnershipDto {
  targetUserId: string;
}

export interface CreateMessageDto {
  clientMessageId: string;
  type?: MessageType;
  text?: string;
  replyToMessageId?: string;
  forwardedFromMessageId?: string;
  metadata?: JsonObject;
}

export interface ApiError {
  statusCode: number;
  error: string;
  message: string | string[];
  requestId?: string;
}

export interface RealtimeEnvelope<TPayload> {
  id: string;
  sequence: number;
  occurredAt: IsoDateTime;
  payload: TPayload;
}

export const RealtimeEventName = {
  CONVERSATION_CREATED: "conversation.created",
  CONVERSATION_UPDATED: "conversation.updated",
  CONVERSATION_DELETED: "conversation.deleted",
  CONVERSATION_MEMBER_ADDED: "conversation.member.added",
  CONVERSATION_MEMBER_REMOVED: "conversation.member.removed",
  MESSAGE_CREATED: "message.created",
  MESSAGE_UPDATED: "message.updated",
  MESSAGE_DELETED: "message.deleted",
  MESSAGE_REACTION_ADDED: "message.reaction.added",
  MESSAGE_REACTION_REMOVED: "message.reaction.removed",
  MESSAGE_DELIVERED: "message.delivered",
  MESSAGE_READ: "message.read",
  TYPING_STARTED: "typing.started",
  TYPING_STOPPED: "typing.stopped",
} as const;

export type RealtimeEventName =
  (typeof RealtimeEventName)[keyof typeof RealtimeEventName];

export interface ConversationChangedRealtimePayload {
  conversationId: string;
}

export interface ConversationMemberAddedRealtimePayload
  extends ConversationChangedRealtimePayload {
  userId: string;
  role: ConversationRole;
}

export interface ConversationMemberRemovedRealtimePayload
  extends ConversationChangedRealtimePayload {
  userId: string;
}

export interface MessageChangedRealtimePayload
  extends ConversationChangedRealtimePayload {
  message: Message;
}

export interface MessageReactionAddedRealtimePayload
  extends ConversationChangedRealtimePayload {
  messageId: string;
  userId: string;
  reaction: string;
  createdAt: IsoDateTime;
}

export interface MessageReactionRemovedRealtimePayload
  extends ConversationChangedRealtimePayload {
  messageId: string;
  userId: string;
  reaction: string;
}

export interface MessageDeliveredRealtimePayload
  extends ConversationChangedRealtimePayload {
  messageId: string;
  userId: string;
  deliveredAt: IsoDateTime;
}

export interface MessageReadRealtimePayload
  extends ConversationChangedRealtimePayload {
  messageId: string;
  userId: string;
  readAt: IsoDateTime;
}

export interface TypingStartedRealtimePayload
  extends ConversationChangedRealtimePayload {
  userId: string;
  expiresAt: IsoDateTime;
}

export interface TypingStoppedRealtimePayload
  extends ConversationChangedRealtimePayload {
  userId: string;
}

export interface RealtimeEventPayloadMap {
  "conversation.created": ConversationChangedRealtimePayload;
  "conversation.updated": ConversationChangedRealtimePayload;
  "conversation.deleted": ConversationChangedRealtimePayload;
  "conversation.member.added": ConversationMemberAddedRealtimePayload;
  "conversation.member.removed": ConversationMemberRemovedRealtimePayload;
  "message.created": MessageChangedRealtimePayload;
  "message.updated": MessageChangedRealtimePayload;
  "message.deleted": MessageChangedRealtimePayload;
  "message.reaction.added": MessageReactionAddedRealtimePayload;
  "message.reaction.removed": MessageReactionRemovedRealtimePayload;
  "message.delivered": MessageDeliveredRealtimePayload;
  "message.read": MessageReadRealtimePayload;
  "typing.started": TypingStartedRealtimePayload;
  "typing.stopped": TypingStoppedRealtimePayload;
}

export type RealtimeEnvelopeFor<TName extends RealtimeEventName> =
  RealtimeEnvelope<RealtimeEventPayloadMap[TName]>;

/** The flattened form used by the mobile realtime coordinator. */
export type MessengerRealtimeEvent = {
  [TName in RealtimeEventName]: RealtimeEnvelopeFor<TName> & {
    type: TName;
  };
}[RealtimeEventName];
