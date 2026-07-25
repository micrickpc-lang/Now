CREATE TABLE "safe_location_zones" (
    "id" UUID NOT NULL,
    "owner_id" UUID NOT NULL,
    "signal_id" UUID,
    "mode" "LocationMode" NOT NULL,
    "safe_center" geography(Point, 4326),
    "radius_meters" INTEGER,
    "description" VARCHAR(160) NOT NULL,
    "city_label" VARCHAR(100),
    "district_label" VARCHAR(100),
    "expires_at" TIMESTAMP(3) NOT NULL,
    "deleted_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "safe_location_zones_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "safe_location_zones_supported_mode" CHECK ("mode" IN ('CITY', 'DISTRICT', 'APPROXIMATE')),
    CONSTRAINT "safe_location_zones_shape" CHECK (
      ("mode" = 'APPROXIMATE' AND "safe_center" IS NOT NULL AND "radius_meters" >= 2000)
      OR
      ("mode" IN ('CITY', 'DISTRICT') AND "safe_center" IS NULL AND "radius_meters" IS NULL)
    ),
    CONSTRAINT "safe_location_zones_future_expiry" CHECK ("expires_at" > "created_at")
);

CREATE UNIQUE INDEX "safe_location_zones_signal_id_key" ON "safe_location_zones"("signal_id");
CREATE INDEX "safe_location_zones_owner_id_expires_at_idx" ON "safe_location_zones"("owner_id", "expires_at");
CREATE INDEX "safe_location_zones_expires_at_deleted_at_idx" ON "safe_location_zones"("expires_at", "deleted_at");
CREATE INDEX "safe_location_zones_safe_center_gist" ON "safe_location_zones" USING GIST ("safe_center");

ALTER TABLE "safe_location_zones" ADD CONSTRAINT "safe_location_zones_owner_id_fkey"
  FOREIGN KEY ("owner_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "safe_location_zones" ADD CONSTRAINT "safe_location_zones_signal_id_fkey"
  FOREIGN KEY ("signal_id") REFERENCES "signals"("id") ON DELETE CASCADE ON UPDATE CASCADE;
