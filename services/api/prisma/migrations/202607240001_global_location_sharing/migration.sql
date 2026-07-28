CREATE TYPE "GlobalLocationShareAudience" AS ENUM ('FRIENDS', 'SELECTED');
CREATE TYPE "GlobalLocationPrecision" AS ENUM ('APPROXIMATE', 'EXACT');

CREATE TABLE "user_locations" (
  "owner_id" UUID NOT NULL,
  "ciphertext" TEXT NOT NULL,
  "iv" TEXT NOT NULL,
  "auth_tag" TEXT NOT NULL,
  "encrypted_data_key" TEXT NOT NULL,
  "key_iv" TEXT NOT NULL,
  "key_auth_tag" TEXT NOT NULL,
  "captured_at" TIMESTAMP(3) NOT NULL,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "user_locations_pkey" PRIMARY KEY ("owner_id")
);

CREATE TABLE "global_location_shares" (
  "id" UUID NOT NULL,
  "owner_id" UUID NOT NULL,
  "audience" "GlobalLocationShareAudience" NOT NULL,
  "precision" "GlobalLocationPrecision" NOT NULL,
  "explicit_consent_at" TIMESTAMP(3) NOT NULL,
  "expires_at" TIMESTAMP(3) NOT NULL,
  "revoked_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "global_location_shares_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "global_location_share_recipients" (
  "share_id" UUID NOT NULL,
  "recipient_id" UUID NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "global_location_share_recipients_pkey" PRIMARY KEY ("share_id", "recipient_id")
);

CREATE INDEX "user_locations_updated_at_idx" ON "user_locations"("updated_at");
CREATE INDEX "global_location_shares_owner_id_expires_at_idx" ON "global_location_shares"("owner_id", "expires_at");
CREATE INDEX "global_location_shares_expires_at_idx" ON "global_location_shares"("expires_at");
CREATE INDEX "global_location_share_recipients_recipient_id_share_id_idx" ON "global_location_share_recipients"("recipient_id", "share_id");

ALTER TABLE "user_locations" ADD CONSTRAINT "user_locations_owner_id_fkey"
  FOREIGN KEY ("owner_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "global_location_shares" ADD CONSTRAINT "global_location_shares_owner_id_fkey"
  FOREIGN KEY ("owner_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "global_location_share_recipients" ADD CONSTRAINT "global_location_share_recipients_share_id_fkey"
  FOREIGN KEY ("share_id") REFERENCES "global_location_shares"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "global_location_share_recipients" ADD CONSTRAINT "global_location_share_recipients_recipient_id_fkey"
  FOREIGN KEY ("recipient_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
