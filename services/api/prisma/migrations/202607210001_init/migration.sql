-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- Required for privacy-preserving approximate spatial queries.
CREATE EXTENSION IF NOT EXISTS postgis;

-- CreateEnum
CREATE TYPE "UserStatus" AS ENUM ('ACTIVE', 'SUSPENDED', 'DELETING');

-- CreateEnum
CREATE TYPE "FriendshipStatus" AS ENUM ('PENDING', 'ACCEPTED', 'REJECTED');

-- CreateEnum
CREATE TYPE "CircleRole" AS ENUM ('OWNER', 'MEMBER');

-- CreateEnum
CREATE TYPE "SignalState" AS ENUM ('DRAFT', 'ACTIVE', 'FULL', 'EXPIRED', 'CANCELLED', 'COMPLETED', 'MODERATED');

-- CreateEnum
CREATE TYPE "SignalFormat" AS ENUM ('ONLINE', 'OFFLINE');

-- CreateEnum
CREATE TYPE "LocationMode" AS ENUM ('NONE', 'CITY', 'DISTRICT', 'APPROXIMATE', 'EXACT_ROOM');

-- CreateEnum
CREATE TYPE "JoinRequestState" AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "RoomState" AS ENUM ('ACTIVE', 'COMPLETED', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "ReportState" AS ENUM ('OPEN', 'INVESTIGATING', 'ACTIONED', 'DISMISSED', 'APPEALED');

-- CreateEnum
CREATE TYPE "AdminRole" AS ENUM ('MODERATOR', 'TRUST_SAFETY', 'SUPERADMIN');

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "phone_hash" TEXT NOT NULL,
    "phone_ciphertext" TEXT NOT NULL,
    "birth_date" DATE NOT NULL,
    "limited_mode" BOOLEAN NOT NULL DEFAULT false,
    "status" "UserStatus" NOT NULL DEFAULT 'ACTIVE',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_profiles" (
    "user_id" UUID NOT NULL,
    "display_name" VARCHAR(40) NOT NULL,
    "emoji" VARCHAR(16),
    "avatar_media_id" UUID,
    "bio" VARCHAR(160),
    "show_recent_activity" BOOLEAN NOT NULL DEFAULT false,
    "notification_settings" JSONB NOT NULL DEFAULT '{}',
    "privacy_settings" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_profiles_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "devices" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "installation_id" VARCHAR(128) NOT NULL,
    "platform" VARCHAR(16) NOT NULL,
    "label" VARCHAR(80),
    "last_seen_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "devices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "auth_sessions" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "device_id" UUID,
    "refresh_token_hash" TEXT NOT NULL,
    "rotation_counter" INTEGER NOT NULL DEFAULT 0,
    "ip_hash" TEXT,
    "user_agent" VARCHAR(255),
    "expires_at" TIMESTAMP(3) NOT NULL,
    "last_used_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "revoked_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "auth_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "otp_challenges" (
    "id" UUID NOT NULL,
    "phone_hash" TEXT NOT NULL,
    "code_hash" TEXT NOT NULL,
    "request_ip_hash" TEXT NOT NULL,
    "attempt_count" INTEGER NOT NULL DEFAULT 0,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "consumed_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "otp_challenges_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "friendships" (
    "id" UUID NOT NULL,
    "user_a_id" UUID NOT NULL,
    "user_b_id" UUID NOT NULL,
    "requested_by_id" UUID NOT NULL,
    "status" "FriendshipStatus" NOT NULL DEFAULT 'PENDING',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "friendships_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "friendship_invites" (
    "id" UUID NOT NULL,
    "creator_id" UUID NOT NULL,
    "token_hash" TEXT NOT NULL,
    "short_code" VARCHAR(10) NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "consumed_at" TIMESTAMP(3),
    "consumed_by_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "friendship_invites_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "circles" (
    "id" UUID NOT NULL,
    "owner_id" UUID NOT NULL,
    "name" VARCHAR(60) NOT NULL,
    "emoji" VARCHAR(16),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "circles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "circle_members" (
    "circle_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "role" "CircleRole" NOT NULL DEFAULT 'MEMBER',
    "joined_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "circle_members_pkey" PRIMARY KEY ("circle_id","user_id")
);

-- CreateTable
CREATE TABLE "signals" (
    "id" UUID NOT NULL,
    "author_id" UUID NOT NULL,
    "category" VARCHAR(40) NOT NULL,
    "text" VARCHAR(180),
    "emoji" VARCHAR(16),
    "starts_at" TIMESTAMP(3) NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "format" "SignalFormat" NOT NULL,
    "location_mode" "LocationMode" NOT NULL DEFAULT 'NONE',
    "city_label" VARCHAR(100),
    "district_label" VARCHAR(100),
    "approximate_point" geography(Point, 4326),
    "max_participants" INTEGER NOT NULL DEFAULT 4,
    "state" "SignalState" NOT NULL DEFAULT 'ACTIVE',
    "extended_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "signals_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "signal_visibility" (
    "id" UUID NOT NULL,
    "signal_id" UUID NOT NULL,
    "circle_id" UUID,
    "user_id" UUID,

    CONSTRAINT "signal_visibility_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "signal_join_requests" (
    "id" UUID NOT NULL,
    "signal_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "state" "JoinRequestState" NOT NULL DEFAULT 'PENDING',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "signal_join_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "signal_participants" (
    "signal_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "joined_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "signal_participants_pkey" PRIMARY KEY ("signal_id","user_id")
);

-- CreateTable
CREATE TABLE "temporary_rooms" (
    "id" UUID NOT NULL,
    "signal_id" UUID NOT NULL,
    "owner_id" UUID NOT NULL,
    "title" VARCHAR(100) NOT NULL,
    "state" "RoomState" NOT NULL DEFAULT 'ACTIVE',
    "scheduled_at" TIMESTAMP(3),
    "expires_at" TIMESTAMP(3) NOT NULL,
    "completed_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "temporary_rooms_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "room_members" (
    "room_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "joined_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "left_at" TIMESTAMP(3),
    "muted_until" TIMESTAMP(3),

    CONSTRAINT "room_members_pkey" PRIMARY KEY ("room_id","user_id")
);

-- CreateTable
CREATE TABLE "room_messages" (
    "id" UUID NOT NULL,
    "room_id" UUID NOT NULL,
    "author_id" UUID,
    "body" VARCHAR(1000) NOT NULL,
    "system" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "room_messages_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "room_reactions" (
    "message_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "emoji" VARCHAR(16) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "room_reactions_pkey" PRIMARY KEY ("message_id","user_id","emoji")
);

-- CreateTable
CREATE TABLE "room_polls" (
    "id" UUID NOT NULL,
    "room_id" UUID NOT NULL,
    "question" VARCHAR(200) NOT NULL,
    "closes_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "room_polls_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "room_poll_options" (
    "id" UUID NOT NULL,
    "poll_id" UUID NOT NULL,
    "label" VARCHAR(100) NOT NULL,
    "position" INTEGER NOT NULL,

    CONSTRAINT "room_poll_options_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "room_poll_votes" (
    "poll_option_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "room_poll_votes_pkey" PRIMARY KEY ("poll_option_id","user_id")
);

-- CreateTable
CREATE TABLE "location_shares" (
    "id" UUID NOT NULL,
    "room_id" UUID NOT NULL,
    "owner_id" UUID NOT NULL,
    "ciphertext" TEXT NOT NULL,
    "iv" TEXT NOT NULL,
    "auth_tag" TEXT NOT NULL,
    "encrypted_data_key" TEXT NOT NULL,
    "key_iv" TEXT NOT NULL,
    "key_auth_tag" TEXT NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "location_shares_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "memories" (
    "id" UUID NOT NULL,
    "owner_id" UUID NOT NULL,
    "title" VARCHAR(80) NOT NULL,
    "category" VARCHAR(40) NOT NULL,
    "occurred_at" TIMESTAMP(3) NOT NULL,
    "duration_min" INTEGER,
    "theme" VARCHAR(32) NOT NULL DEFAULT 'aurora',
    "private" BOOLEAN NOT NULL DEFAULT true,
    "media_id" UUID,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "memories_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "memory_participants" (
    "memory_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,

    CONSTRAINT "memory_participants_pkey" PRIMARY KEY ("memory_id","user_id")
);

-- CreateTable
CREATE TABLE "media_files" (
    "id" UUID NOT NULL,
    "owner_id" UUID NOT NULL,
    "object_key" TEXT NOT NULL,
    "thumbnail_key" TEXT,
    "mime_type" VARCHAR(80) NOT NULL,
    "byte_size" INTEGER NOT NULL,
    "sha256" TEXT NOT NULL,
    "scan_status" VARCHAR(20) NOT NULL DEFAULT 'pending',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "media_files_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "blocks" (
    "blocker_id" UUID NOT NULL,
    "blocked_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "blocks_pkey" PRIMARY KEY ("blocker_id","blocked_id")
);

-- CreateTable
CREATE TABLE "reports" (
    "id" UUID NOT NULL,
    "reporter_id" UUID,
    "reported_user_id" UUID,
    "signal_id" UUID,
    "message_id" UUID,
    "category" VARCHAR(40) NOT NULL,
    "details" VARCHAR(1000),
    "state" "ReportState" NOT NULL DEFAULT 'OPEN',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "reports_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "admin_users" (
    "id" UUID NOT NULL,
    "email" TEXT NOT NULL,
    "password_hash" TEXT NOT NULL,
    "role" "AdminRole" NOT NULL DEFAULT 'MODERATOR',
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "admin_users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "moderation_actions" (
    "id" UUID NOT NULL,
    "report_id" UUID,
    "admin_id" UUID NOT NULL,
    "action" VARCHAR(60) NOT NULL,
    "reason" VARCHAR(500) NOT NULL,
    "metadata" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "moderation_actions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "notification_tokens" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "token_hash" TEXT NOT NULL,
    "encrypted_token" TEXT NOT NULL,
    "platform" VARCHAR(16) NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "notification_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "consent_records" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "type" VARCHAR(60) NOT NULL,
    "version" VARCHAR(32) NOT NULL,
    "granted" BOOLEAN NOT NULL,
    "evidence_ref" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "consent_records_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_logs" (
    "id" UUID NOT NULL,
    "actor_user_id" UUID,
    "actor_admin_id" UUID,
    "action" VARCHAR(100) NOT NULL,
    "resource_type" VARCHAR(60) NOT NULL,
    "resource_id" UUID,
    "result" VARCHAR(30) NOT NULL,
    "ip_hash" TEXT,
    "metadata" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "feature_flags" (
    "key" VARCHAR(80) NOT NULL,
    "enabled" BOOLEAN NOT NULL DEFAULT false,
    "payload" JSONB NOT NULL DEFAULT '{}',
    "min_version" VARCHAR(30),
    "force_update" BOOLEAN NOT NULL DEFAULT false,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "feature_flags_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "forbidden_words" (
    "id" UUID NOT NULL,
    "pattern" VARCHAR(160) NOT NULL,
    "category" VARCHAR(40) NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "forbidden_words_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "analytics_events" (
    "id" UUID NOT NULL,
    "user_id" UUID,
    "pseudonym" VARCHAR(64) NOT NULL,
    "name" VARCHAR(60) NOT NULL,
    "properties" JSONB NOT NULL DEFAULT '{}',
    "occurred_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "analytics_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "deletion_reports" (
    "id" UUID NOT NULL,
    "user_id" UUID,
    "request_ref" TEXT NOT NULL,
    "categories" JSONB NOT NULL,
    "completed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "retained_basis" JSONB NOT NULL DEFAULT '{}',

    CONSTRAINT "deletion_reports_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_phone_hash_key" ON "users"("phone_hash");

-- CreateIndex
CREATE UNIQUE INDEX "user_profiles_avatar_media_id_key" ON "user_profiles"("avatar_media_id");

-- CreateIndex
CREATE INDEX "devices_user_id_last_seen_at_idx" ON "devices"("user_id", "last_seen_at");

-- CreateIndex
CREATE UNIQUE INDEX "devices_user_id_installation_id_key" ON "devices"("user_id", "installation_id");

-- CreateIndex
CREATE INDEX "auth_sessions_user_id_revoked_at_idx" ON "auth_sessions"("user_id", "revoked_at");

-- CreateIndex
CREATE INDEX "auth_sessions_expires_at_idx" ON "auth_sessions"("expires_at");

-- CreateIndex
CREATE INDEX "otp_challenges_phone_hash_created_at_idx" ON "otp_challenges"("phone_hash", "created_at");

-- CreateIndex
CREATE INDEX "otp_challenges_request_ip_hash_created_at_idx" ON "otp_challenges"("request_ip_hash", "created_at");

-- CreateIndex
CREATE INDEX "otp_challenges_expires_at_idx" ON "otp_challenges"("expires_at");

-- CreateIndex
CREATE INDEX "friendships_user_a_id_status_idx" ON "friendships"("user_a_id", "status");

-- CreateIndex
CREATE INDEX "friendships_user_b_id_status_idx" ON "friendships"("user_b_id", "status");

-- CreateIndex
CREATE UNIQUE INDEX "friendships_user_a_id_user_b_id_key" ON "friendships"("user_a_id", "user_b_id");

-- CreateIndex
CREATE UNIQUE INDEX "friendship_invites_token_hash_key" ON "friendship_invites"("token_hash");

-- CreateIndex
CREATE UNIQUE INDEX "friendship_invites_short_code_key" ON "friendship_invites"("short_code");

-- CreateIndex
CREATE INDEX "friendship_invites_creator_id_created_at_idx" ON "friendship_invites"("creator_id", "created_at");

-- CreateIndex
CREATE INDEX "friendship_invites_expires_at_idx" ON "friendship_invites"("expires_at");

-- CreateIndex
CREATE INDEX "circles_owner_id_idx" ON "circles"("owner_id");

-- CreateIndex
CREATE INDEX "circle_members_user_id_idx" ON "circle_members"("user_id");

-- CreateIndex
CREATE INDEX "signals_author_id_state_idx" ON "signals"("author_id", "state");

-- CreateIndex
CREATE INDEX "signals_state_expires_at_idx" ON "signals"("state", "expires_at");

-- CreateIndex
CREATE INDEX "signal_visibility_circle_id_idx" ON "signal_visibility"("circle_id");

-- CreateIndex
CREATE INDEX "signal_visibility_user_id_idx" ON "signal_visibility"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "signal_visibility_signal_id_circle_id_key" ON "signal_visibility"("signal_id", "circle_id");

-- CreateIndex
CREATE UNIQUE INDEX "signal_visibility_signal_id_user_id_key" ON "signal_visibility"("signal_id", "user_id");

-- CreateIndex
CREATE INDEX "signal_join_requests_user_id_state_idx" ON "signal_join_requests"("user_id", "state");

-- CreateIndex
CREATE UNIQUE INDEX "signal_join_requests_signal_id_user_id_key" ON "signal_join_requests"("signal_id", "user_id");

-- CreateIndex
CREATE INDEX "signal_participants_user_id_idx" ON "signal_participants"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "temporary_rooms_signal_id_key" ON "temporary_rooms"("signal_id");

-- CreateIndex
CREATE INDEX "temporary_rooms_state_expires_at_idx" ON "temporary_rooms"("state", "expires_at");

-- CreateIndex
CREATE INDEX "room_members_user_id_left_at_idx" ON "room_members"("user_id", "left_at");

-- CreateIndex
CREATE INDEX "room_messages_room_id_created_at_idx" ON "room_messages"("room_id", "created_at");

-- CreateIndex
CREATE INDEX "room_polls_room_id_idx" ON "room_polls"("room_id");

-- CreateIndex
CREATE UNIQUE INDEX "room_poll_options_poll_id_position_key" ON "room_poll_options"("poll_id", "position");

-- CreateIndex
CREATE INDEX "location_shares_expires_at_idx" ON "location_shares"("expires_at");

-- CreateIndex
CREATE UNIQUE INDEX "location_shares_room_id_owner_id_key" ON "location_shares"("room_id", "owner_id");

-- CreateIndex
CREATE UNIQUE INDEX "memories_media_id_key" ON "memories"("media_id");

-- CreateIndex
CREATE INDEX "memories_owner_id_occurred_at_idx" ON "memories"("owner_id", "occurred_at");

-- CreateIndex
CREATE UNIQUE INDEX "media_files_object_key_key" ON "media_files"("object_key");

-- CreateIndex
CREATE UNIQUE INDEX "media_files_thumbnail_key_key" ON "media_files"("thumbnail_key");

-- CreateIndex
CREATE INDEX "media_files_owner_id_idx" ON "media_files"("owner_id");

-- CreateIndex
CREATE INDEX "blocks_blocked_id_idx" ON "blocks"("blocked_id");

-- CreateIndex
CREATE INDEX "reports_state_created_at_idx" ON "reports"("state", "created_at");

-- CreateIndex
CREATE INDEX "reports_reported_user_id_idx" ON "reports"("reported_user_id");

-- CreateIndex
CREATE UNIQUE INDEX "admin_users_email_key" ON "admin_users"("email");

-- CreateIndex
CREATE INDEX "moderation_actions_report_id_idx" ON "moderation_actions"("report_id");

-- CreateIndex
CREATE INDEX "moderation_actions_admin_id_created_at_idx" ON "moderation_actions"("admin_id", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "notification_tokens_token_hash_key" ON "notification_tokens"("token_hash");

-- CreateIndex
CREATE INDEX "notification_tokens_user_id_enabled_idx" ON "notification_tokens"("user_id", "enabled");

-- CreateIndex
CREATE INDEX "consent_records_user_id_type_idx" ON "consent_records"("user_id", "type");

-- CreateIndex
CREATE INDEX "audit_logs_resource_type_resource_id_created_at_idx" ON "audit_logs"("resource_type", "resource_id", "created_at");

-- CreateIndex
CREATE INDEX "audit_logs_actor_user_id_created_at_idx" ON "audit_logs"("actor_user_id", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "forbidden_words_pattern_key" ON "forbidden_words"("pattern");

-- CreateIndex
CREATE INDEX "analytics_events_name_occurred_at_idx" ON "analytics_events"("name", "occurred_at");

-- CreateIndex
CREATE UNIQUE INDEX "deletion_reports_request_ref_key" ON "deletion_reports"("request_ref");

-- AddForeignKey
ALTER TABLE "user_profiles" ADD CONSTRAINT "user_profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_profiles" ADD CONSTRAINT "user_profiles_avatar_media_id_fkey" FOREIGN KEY ("avatar_media_id") REFERENCES "media_files"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "devices" ADD CONSTRAINT "devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "auth_sessions" ADD CONSTRAINT "auth_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "auth_sessions" ADD CONSTRAINT "auth_sessions_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "devices"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "friendships" ADD CONSTRAINT "friendships_user_a_id_fkey" FOREIGN KEY ("user_a_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "friendships" ADD CONSTRAINT "friendships_user_b_id_fkey" FOREIGN KEY ("user_b_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "friendships" ADD CONSTRAINT "friendships_requested_by_id_fkey" FOREIGN KEY ("requested_by_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "friendship_invites" ADD CONSTRAINT "friendship_invites_creator_id_fkey" FOREIGN KEY ("creator_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "friendship_invites" ADD CONSTRAINT "friendship_invites_consumed_by_id_fkey" FOREIGN KEY ("consumed_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "circles" ADD CONSTRAINT "circles_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "circle_members" ADD CONSTRAINT "circle_members_circle_id_fkey" FOREIGN KEY ("circle_id") REFERENCES "circles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "circle_members" ADD CONSTRAINT "circle_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "signals" ADD CONSTRAINT "signals_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "signal_visibility" ADD CONSTRAINT "signal_visibility_signal_id_fkey" FOREIGN KEY ("signal_id") REFERENCES "signals"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "signal_visibility" ADD CONSTRAINT "signal_visibility_circle_id_fkey" FOREIGN KEY ("circle_id") REFERENCES "circles"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "signal_join_requests" ADD CONSTRAINT "signal_join_requests_signal_id_fkey" FOREIGN KEY ("signal_id") REFERENCES "signals"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "signal_join_requests" ADD CONSTRAINT "signal_join_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "signal_participants" ADD CONSTRAINT "signal_participants_signal_id_fkey" FOREIGN KEY ("signal_id") REFERENCES "signals"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "signal_participants" ADD CONSTRAINT "signal_participants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "temporary_rooms" ADD CONSTRAINT "temporary_rooms_signal_id_fkey" FOREIGN KEY ("signal_id") REFERENCES "signals"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "temporary_rooms" ADD CONSTRAINT "temporary_rooms_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "room_members" ADD CONSTRAINT "room_members_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "temporary_rooms"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "room_members" ADD CONSTRAINT "room_members_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "room_messages" ADD CONSTRAINT "room_messages_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "temporary_rooms"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "room_messages" ADD CONSTRAINT "room_messages_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "room_reactions" ADD CONSTRAINT "room_reactions_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "room_messages"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "room_reactions" ADD CONSTRAINT "room_reactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "room_polls" ADD CONSTRAINT "room_polls_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "temporary_rooms"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "room_poll_options" ADD CONSTRAINT "room_poll_options_poll_id_fkey" FOREIGN KEY ("poll_id") REFERENCES "room_polls"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "room_poll_votes" ADD CONSTRAINT "room_poll_votes_poll_option_id_fkey" FOREIGN KEY ("poll_option_id") REFERENCES "room_poll_options"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "room_poll_votes" ADD CONSTRAINT "room_poll_votes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "location_shares" ADD CONSTRAINT "location_shares_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "temporary_rooms"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "location_shares" ADD CONSTRAINT "location_shares_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "memories" ADD CONSTRAINT "memories_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "memories" ADD CONSTRAINT "memories_media_id_fkey" FOREIGN KEY ("media_id") REFERENCES "media_files"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "memory_participants" ADD CONSTRAINT "memory_participants_memory_id_fkey" FOREIGN KEY ("memory_id") REFERENCES "memories"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "memory_participants" ADD CONSTRAINT "memory_participants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "media_files" ADD CONSTRAINT "media_files_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "blocks" ADD CONSTRAINT "blocks_blocker_id_fkey" FOREIGN KEY ("blocker_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "blocks" ADD CONSTRAINT "blocks_blocked_id_fkey" FOREIGN KEY ("blocked_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_reported_user_id_fkey" FOREIGN KEY ("reported_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_signal_id_fkey" FOREIGN KEY ("signal_id") REFERENCES "signals"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "reports" ADD CONSTRAINT "reports_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "room_messages"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "moderation_actions" ADD CONSTRAINT "moderation_actions_report_id_fkey" FOREIGN KEY ("report_id") REFERENCES "reports"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "moderation_actions" ADD CONSTRAINT "moderation_actions_admin_id_fkey" FOREIGN KEY ("admin_id") REFERENCES "admin_users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "notification_tokens" ADD CONSTRAINT "notification_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "consent_records" ADD CONSTRAINT "consent_records_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_actor_user_id_fkey" FOREIGN KEY ("actor_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "analytics_events" ADD CONSTRAINT "analytics_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "deletion_reports" ADD CONSTRAINT "deletion_reports_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Domain invariants Prisma cannot express directly.
ALTER TABLE "friendships" ADD CONSTRAINT "friendships_canonical_pair" CHECK ("user_a_id" < "user_b_id");
ALTER TABLE "blocks" ADD CONSTRAINT "blocks_no_self" CHECK ("blocker_id" <> "blocked_id");
ALTER TABLE "signal_visibility" ADD CONSTRAINT "signal_visibility_one_target" CHECK (num_nonnulls("circle_id", "user_id") = 1);
ALTER TABLE "signals" ADD CONSTRAINT "signals_valid_capacity" CHECK ("max_participants" BETWEEN 2 AND 20);
ALTER TABLE "signals" ADD CONSTRAINT "signals_valid_window" CHECK ("expires_at" > "starts_at");
ALTER TABLE "location_shares" ADD CONSTRAINT "location_shares_future_expiry" CHECK ("expires_at" > "created_at");
CREATE INDEX "signals_approximate_point_gist" ON "signals" USING GIST ("approximate_point");
