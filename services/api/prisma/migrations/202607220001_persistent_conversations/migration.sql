-- Persistent messenger is intentionally separate from signal-bound temporary rooms.
CREATE TYPE "ConversationType" AS ENUM ('DIRECT', 'GROUP');
CREATE TYPE "ChatRole" AS ENUM ('OWNER', 'ADMIN', 'MEMBER');
CREATE TYPE "ConversationInviteState" AS ENUM ('PENDING', 'ACCEPTED', 'REVOKED', 'EXPIRED');
CREATE TYPE "MessageType" AS ENUM ('TEXT', 'IMAGE', 'VIDEO', 'VOICE', 'FILE', 'LOCATION', 'SYSTEM', 'SIGNAL', 'CALL', 'POLL', 'STORY_REPLY');
CREATE TYPE "MessageDeleteMode" AS ENUM ('NONE', 'SELF', 'EVERYONE');
CREATE TYPE "MessageDeliveryState" AS ENUM ('PENDING', 'DELIVERED', 'FAILED');

CREATE TABLE "conversations" (
    "id" UUID NOT NULL,
    "type" "ConversationType" NOT NULL,
    "direct_pair_key" VARCHAR(80),
    "title" VARCHAR(100),
    "avatar_media_id" UUID,
    "owner_id" UUID,
    "last_message_at" TIMESTAMP(3),
    "deleted_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "conversations_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "conversation_members" (
    "conversation_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "role" "ChatRole" NOT NULL DEFAULT 'MEMBER',
    "joined_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "left_at" TIMESTAMP(3),
    CONSTRAINT "conversation_members_pkey" PRIMARY KEY ("conversation_id", "user_id")
);

CREATE TABLE "conversation_invites" (
    "id" UUID NOT NULL,
    "conversation_id" UUID NOT NULL,
    "inviter_id" UUID NOT NULL,
    "invitee_id" UUID NOT NULL,
    "token_hash" TEXT NOT NULL,
    "state" "ConversationInviteState" NOT NULL DEFAULT 'PENDING',
    "expires_at" TIMESTAMP(3) NOT NULL,
    "accepted_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "conversation_invites_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "messages" (
    "id" UUID NOT NULL,
    "conversation_id" UUID NOT NULL,
    "sender_id" UUID,
    "client_message_id" UUID,
    "reply_to_message_id" UUID,
    "forwarded_from_message_id" UUID,
    "type" "MessageType" NOT NULL DEFAULT 'TEXT',
    "text" VARCHAR(4000),
    "metadata" JSONB NOT NULL DEFAULT '{}',
    "protection_mode" VARCHAR(32) NOT NULL DEFAULT 'SERVER_MANAGED',
    "payload_version" INTEGER NOT NULL DEFAULT 1,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "edited_at" TIMESTAMP(3),
    "deleted_at" TIMESTAMP(3),
    "delete_mode" "MessageDeleteMode" NOT NULL DEFAULT 'NONE',
    CONSTRAINT "messages_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "message_edits" (
    "id" UUID NOT NULL,
    "message_id" UUID NOT NULL,
    "editor_id" UUID NOT NULL,
    "previous_text" VARCHAR(4000),
    "new_text" VARCHAR(4000) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "message_edits_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "message_attachments" (
    "id" UUID NOT NULL,
    "message_id" UUID NOT NULL,
    "media_id" UUID NOT NULL,
    "position" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "message_attachments_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "message_reactions" (
    "message_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "reaction" VARCHAR(32) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "message_reactions_pkey" PRIMARY KEY ("message_id", "user_id", "reaction")
);

CREATE TABLE "message_read_receipts" (
    "message_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "read_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "message_read_receipts_pkey" PRIMARY KEY ("message_id", "user_id")
);

CREATE TABLE "message_deliveries" (
    "message_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "state" "MessageDeliveryState" NOT NULL DEFAULT 'PENDING',
    "delivered_at" TIMESTAMP(3),
    "failed_at" TIMESTAMP(3),
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "message_deliveries_pkey" PRIMARY KEY ("message_id", "user_id")
);

CREATE TABLE "pinned_messages" (
    "conversation_id" UUID NOT NULL,
    "message_id" UUID NOT NULL,
    "pinned_by_id" UUID NOT NULL,
    "pinned_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "pinned_messages_pkey" PRIMARY KEY ("conversation_id", "message_id")
);

CREATE TABLE "conversation_drafts" (
    "conversation_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "text" VARCHAR(4000) NOT NULL,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "conversation_drafts_pkey" PRIMARY KEY ("conversation_id", "user_id")
);

CREATE TABLE "chat_mutes" (
    "conversation_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "muted_until" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "chat_mutes_pkey" PRIMARY KEY ("conversation_id", "user_id")
);

CREATE TABLE "chat_audit_events" (
    "id" UUID NOT NULL,
    "conversation_id" UUID NOT NULL,
    "actor_user_id" UUID,
    "target_user_id" UUID,
    "action" VARCHAR(80) NOT NULL,
    "metadata" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "chat_audit_events_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "reports" ADD COLUMN "chat_message_id" UUID;

CREATE UNIQUE INDEX "conversations_direct_pair_key_key" ON "conversations"("direct_pair_key");
CREATE INDEX "conversations_updated_at_id_idx" ON "conversations"("updated_at", "id");
CREATE INDEX "conversations_last_message_at_id_idx" ON "conversations"("last_message_at", "id");
CREATE INDEX "conversation_members_user_id_left_at_conversation_id_idx" ON "conversation_members"("user_id", "left_at", "conversation_id");
CREATE UNIQUE INDEX "conversation_invites_token_hash_key" ON "conversation_invites"("token_hash");
CREATE INDEX "conversation_invites_conversation_id_state_idx" ON "conversation_invites"("conversation_id", "state");
CREATE INDEX "conversation_invites_invitee_id_state_expires_at_idx" ON "conversation_invites"("invitee_id", "state", "expires_at");
CREATE UNIQUE INDEX "messages_sender_id_client_message_id_key" ON "messages"("sender_id", "client_message_id");
CREATE INDEX "messages_conversation_id_created_at_id_idx" ON "messages"("conversation_id", "created_at", "id");
CREATE INDEX "messages_conversation_id_sender_id_created_at_idx" ON "messages"("conversation_id", "sender_id", "created_at");
CREATE INDEX "message_edits_message_id_created_at_idx" ON "message_edits"("message_id", "created_at");
CREATE UNIQUE INDEX "message_attachments_message_id_position_key" ON "message_attachments"("message_id", "position");
CREATE UNIQUE INDEX "message_attachments_message_id_media_id_key" ON "message_attachments"("message_id", "media_id");
CREATE INDEX "message_attachments_media_id_idx" ON "message_attachments"("media_id");
CREATE INDEX "message_reactions_user_id_created_at_idx" ON "message_reactions"("user_id", "created_at");
CREATE INDEX "message_read_receipts_user_id_read_at_idx" ON "message_read_receipts"("user_id", "read_at");
CREATE INDEX "message_deliveries_user_id_state_updated_at_idx" ON "message_deliveries"("user_id", "state", "updated_at");
CREATE INDEX "pinned_messages_conversation_id_pinned_at_idx" ON "pinned_messages"("conversation_id", "pinned_at");
CREATE INDEX "conversation_drafts_user_id_updated_at_idx" ON "conversation_drafts"("user_id", "updated_at");
CREATE INDEX "chat_mutes_user_id_muted_until_idx" ON "chat_mutes"("user_id", "muted_until");
CREATE INDEX "chat_audit_events_conversation_id_created_at_idx" ON "chat_audit_events"("conversation_id", "created_at");
CREATE INDEX "reports_chat_message_id_idx" ON "reports"("chat_message_id");

ALTER TABLE "conversations" ADD CONSTRAINT "conversations_avatar_media_id_fkey" FOREIGN KEY ("avatar_media_id") REFERENCES "media_files"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "conversations" ADD CONSTRAINT "conversations_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "conversation_members" ADD CONSTRAINT "conversation_members_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "conversation_members" ADD CONSTRAINT "conversation_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "conversation_invites" ADD CONSTRAINT "conversation_invites_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "conversation_invites" ADD CONSTRAINT "conversation_invites_inviter_id_fkey" FOREIGN KEY ("inviter_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "conversation_invites" ADD CONSTRAINT "conversation_invites_invitee_id_fkey" FOREIGN KEY ("invitee_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "messages" ADD CONSTRAINT "messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "messages" ADD CONSTRAINT "messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "messages" ADD CONSTRAINT "messages_reply_to_message_id_fkey" FOREIGN KEY ("reply_to_message_id") REFERENCES "messages"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "messages" ADD CONSTRAINT "messages_forwarded_from_message_id_fkey" FOREIGN KEY ("forwarded_from_message_id") REFERENCES "messages"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "message_edits" ADD CONSTRAINT "message_edits_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "messages"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "message_edits" ADD CONSTRAINT "message_edits_editor_id_fkey" FOREIGN KEY ("editor_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "message_attachments" ADD CONSTRAINT "message_attachments_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "messages"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "message_attachments" ADD CONSTRAINT "message_attachments_media_id_fkey" FOREIGN KEY ("media_id") REFERENCES "media_files"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "message_reactions" ADD CONSTRAINT "message_reactions_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "messages"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "message_reactions" ADD CONSTRAINT "message_reactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "message_read_receipts" ADD CONSTRAINT "message_read_receipts_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "messages"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "message_read_receipts" ADD CONSTRAINT "message_read_receipts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "message_deliveries" ADD CONSTRAINT "message_deliveries_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "messages"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "message_deliveries" ADD CONSTRAINT "message_deliveries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "pinned_messages" ADD CONSTRAINT "pinned_messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "pinned_messages" ADD CONSTRAINT "pinned_messages_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "messages"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "pinned_messages" ADD CONSTRAINT "pinned_messages_pinned_by_id_fkey" FOREIGN KEY ("pinned_by_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "conversation_drafts" ADD CONSTRAINT "conversation_drafts_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "conversation_drafts" ADD CONSTRAINT "conversation_drafts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "chat_mutes" ADD CONSTRAINT "chat_mutes_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "chat_mutes" ADD CONSTRAINT "chat_mutes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "chat_audit_events" ADD CONSTRAINT "chat_audit_events_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "conversations"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "chat_audit_events" ADD CONSTRAINT "chat_audit_events_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "chat_audit_events" ADD CONSTRAINT "chat_audit_events_target_user_id_fkey" FOREIGN KEY ("target_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "reports" ADD CONSTRAINT "reports_chat_message_id_fkey" FOREIGN KEY ("chat_message_id") REFERENCES "messages"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "conversations" ADD CONSTRAINT "conversations_type_shape" CHECK (
  ("type" = 'DIRECT' AND "direct_pair_key" IS NOT NULL AND "title" IS NULL AND "owner_id" IS NULL)
  OR
  ("type" = 'GROUP' AND "direct_pair_key" IS NULL AND "title" IS NOT NULL AND "owner_id" IS NOT NULL)
);
ALTER TABLE "conversation_invites" ADD CONSTRAINT "conversation_invites_no_self" CHECK ("inviter_id" <> "invitee_id");
ALTER TABLE "messages" ADD CONSTRAINT "messages_client_sender_pair" CHECK (
  ("sender_id" IS NULL AND "client_message_id" IS NULL)
  OR
  ("sender_id" IS NOT NULL AND "client_message_id" IS NOT NULL)
);
ALTER TABLE "messages" ADD CONSTRAINT "messages_positive_payload_version" CHECK ("payload_version" > 0);
ALTER TABLE "message_attachments" ADD CONSTRAINT "message_attachments_nonnegative_position" CHECK ("position" >= 0);
