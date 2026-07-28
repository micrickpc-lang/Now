ALTER TYPE "LocationMode" ADD VALUE IF NOT EXISTS 'EXACT_PIN';
ALTER TYPE "LocationMode" ADD VALUE IF NOT EXISTS 'EXACT_LIVE';

ALTER TABLE "signals"
  ADD COLUMN "exact_location_share_id" UUID;

CREATE UNIQUE INDEX "signals_exact_location_share_id_key"
  ON "signals"("exact_location_share_id");

ALTER TABLE "signals"
  ADD CONSTRAINT "signals_exact_location_share_id_fkey"
  FOREIGN KEY ("exact_location_share_id")
  REFERENCES "exact_location_shares"("id")
  ON DELETE SET NULL
  ON UPDATE CASCADE;
