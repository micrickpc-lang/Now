-- P0: keep legacy SMS records readable while introducing passwordless email,
-- external identities, and retained refresh-token rotation history.
CREATE TYPE "AuthIdentityProvider" AS ENUM ('EMAIL', 'GOOGLE');
CREATE TYPE "EmailLoginCodePurpose" AS ENUM ('LOGIN', 'LINK_IDENTITY');

ALTER TABLE "users" ALTER COLUMN "phone_hash" DROP NOT NULL;
ALTER TABLE "users" ALTER COLUMN "phone_ciphertext" DROP NOT NULL;
ALTER TABLE "users" ALTER COLUMN "birth_date" DROP NOT NULL;
ALTER TABLE "users"
  ADD COLUMN "email_hash" TEXT,
  ADD COLUMN "email_ciphertext" TEXT,
  ADD COLUMN "email_verified_at" TIMESTAMP(3),
  ADD COLUMN "username" VARCHAR(32),
  ADD COLUMN "profile_completed_at" TIMESTAMP(3);

ALTER TABLE "devices" ADD COLUMN "app_version" VARCHAR(40);

ALTER TABLE "auth_sessions"
  ADD COLUMN "token_family_id" UUID,
  ADD COLUMN "revoke_reason" VARCHAR(64),
  ADD COLUMN "app_version" VARCHAR(40);
UPDATE "auth_sessions" SET "token_family_id" = "id" WHERE "token_family_id" IS NULL;
ALTER TABLE "auth_sessions" ALTER COLUMN "token_family_id" SET NOT NULL;

CREATE TABLE "refresh_tokens" (
  "id" UUID NOT NULL,
  "session_id" UUID NOT NULL,
  "token_hash" TEXT NOT NULL,
  "issued_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "used_at" TIMESTAMP(3),
  "revoked_at" TIMESTAMP(3),
  "expires_at" TIMESTAMP(3) NOT NULL,
  "replaced_by_id" UUID,
  CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "auth_identities" (
  "id" UUID NOT NULL,
  "user_id" UUID NOT NULL,
  "provider" "AuthIdentityProvider" NOT NULL,
  "subject_hash" VARCHAR(96) NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "auth_identities_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "email_login_codes" (
  "id" UUID NOT NULL,
  "email_hash" VARCHAR(96) NOT NULL,
  "code_hash" VARCHAR(96) NOT NULL,
  "purpose" "EmailLoginCodePurpose" NOT NULL DEFAULT 'LOGIN',
  "requested_by_user_id" UUID,
  "request_ip_hash" VARCHAR(96) NOT NULL,
  "installation_id" VARCHAR(128),
  "attempt_count" INTEGER NOT NULL DEFAULT 0,
  "resend_count" INTEGER NOT NULL DEFAULT 0,
  "expires_at" TIMESTAMP(3) NOT NULL,
  "consumed_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "email_login_codes_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "users_email_hash_key" ON "users"("email_hash");
CREATE UNIQUE INDEX "users_username_key" ON "users"("username");
CREATE INDEX "auth_sessions_token_family_id_revoked_at_idx" ON "auth_sessions"("token_family_id", "revoked_at");
CREATE UNIQUE INDEX "refresh_tokens_token_hash_key" ON "refresh_tokens"("token_hash");
CREATE UNIQUE INDEX "refresh_tokens_replaced_by_id_key" ON "refresh_tokens"("replaced_by_id");
CREATE INDEX "refresh_tokens_session_id_revoked_at_idx" ON "refresh_tokens"("session_id", "revoked_at");
CREATE INDEX "refresh_tokens_expires_at_idx" ON "refresh_tokens"("expires_at");
CREATE UNIQUE INDEX "auth_identities_provider_subject_hash_key" ON "auth_identities"("provider", "subject_hash");
CREATE INDEX "auth_identities_user_id_idx" ON "auth_identities"("user_id");
CREATE INDEX "email_login_codes_email_hash_purpose_created_at_idx" ON "email_login_codes"("email_hash", "purpose", "created_at");
CREATE INDEX "email_login_codes_request_ip_hash_created_at_idx" ON "email_login_codes"("request_ip_hash", "created_at");
CREATE INDEX "email_login_codes_expires_at_idx" ON "email_login_codes"("expires_at");

ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_session_id_fkey"
  FOREIGN KEY ("session_id") REFERENCES "auth_sessions"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_replaced_by_id_fkey"
  FOREIGN KEY ("replaced_by_id") REFERENCES "refresh_tokens"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "auth_identities" ADD CONSTRAINT "auth_identities_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "email_login_codes" ADD CONSTRAINT "email_login_codes_requested_by_user_id_fkey"
  FOREIGN KEY ("requested_by_user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
