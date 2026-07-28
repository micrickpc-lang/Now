CREATE TYPE "ExactLocationAudience" AS ENUM ('SELECTED_FRIENDS', 'CIRCLE', 'ROOM');
CREATE TYPE "ExactLocationExpiry" AS ENUM ('THIRTY_MINUTES', 'ONE_HOUR', 'MEETING_END', 'MANUAL');

CREATE TABLE "exact_location_shares" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "owner_id" UUID NOT NULL,
  "audience" "ExactLocationAudience" NOT NULL,
  "expiry_mode" "ExactLocationExpiry" NOT NULL,
  "circle_id" UUID,
  "room_id" UUID,
  "background_updates_enabled" BOOLEAN NOT NULL DEFAULT false,
  "ciphertext" TEXT NOT NULL,
  "iv" TEXT NOT NULL,
  "auth_tag" TEXT NOT NULL,
  "encrypted_data_key" TEXT NOT NULL,
  "key_iv" TEXT NOT NULL,
  "key_auth_tag" TEXT NOT NULL,
  "expires_at" TIMESTAMPTZ,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT "exact_location_shares_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "exact_location_shares_owner_id_fkey"
    FOREIGN KEY ("owner_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "exact_location_shares_circle_id_fkey"
    FOREIGN KEY ("circle_id") REFERENCES "circles"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "exact_location_shares_room_id_fkey"
    FOREIGN KEY ("room_id") REFERENCES "temporary_rooms"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "exact_location_shares_audience_target"
    CHECK (
      ("audience" = 'SELECTED_FRIENDS' AND "circle_id" IS NULL AND "room_id" IS NULL) OR
      ("audience" = 'CIRCLE' AND "circle_id" IS NOT NULL AND "room_id" IS NULL) OR
      ("audience" = 'ROOM' AND "circle_id" IS NULL AND "room_id" IS NOT NULL)
    ),
  CONSTRAINT "exact_location_shares_expiry"
    CHECK (
      ("expiry_mode" = 'MANUAL' AND "expires_at" IS NULL) OR
      ("expiry_mode" <> 'MANUAL' AND "expires_at" IS NOT NULL)
    )
);

CREATE TABLE "exact_location_recipients" (
  "share_id" UUID NOT NULL,
  "viewer_id" UUID NOT NULL,
  CONSTRAINT "exact_location_recipients_pkey" PRIMARY KEY ("share_id", "viewer_id"),
  CONSTRAINT "exact_location_recipients_share_id_fkey"
    FOREIGN KEY ("share_id") REFERENCES "exact_location_shares"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "exact_location_recipients_viewer_id_fkey"
    FOREIGN KEY ("viewer_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "exact_location_shares_owner_id_expires_at_idx"
  ON "exact_location_shares"("owner_id", "expires_at");
CREATE INDEX "exact_location_shares_circle_id_expires_at_idx"
  ON "exact_location_shares"("circle_id", "expires_at");
CREATE INDEX "exact_location_shares_room_id_expires_at_idx"
  ON "exact_location_shares"("room_id", "expires_at");
CREATE INDEX "exact_location_recipients_viewer_id_idx"
  ON "exact_location_recipients"("viewer_id");
