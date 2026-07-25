import { ServiceUnavailableException } from "@nestjs/common";
import type { PrismaService } from "../common/prisma.service";
import type { RedisService } from "../common/redis.service";
import type { MapsService } from "../features/maps/maps.service";
import { OperationsController } from "./operations.controller";

describe("OperationsController", () => {
  const database = { $queryRaw: jest.fn().mockResolvedValue([{ ok: 1 }]) };
  const redis = { ping: jest.fn().mockResolvedValue("PONG") };
  const maps = {
    upstreamReadiness: jest.fn().mockResolvedValue({
      tileService: "ready",
      geocoder: "ready",
    }),
  };
  const controller = new OperationsController(
    database as unknown as PrismaService,
    redis as unknown as RedisService,
    maps as unknown as MapsService,
  );

  beforeEach(() => {
    jest.clearAllMocks();
    database.$queryRaw.mockResolvedValue([{ ok: 1 }]);
    redis.ping.mockResolvedValue("PONG");
    maps.upstreamReadiness.mockResolvedValue({
      tileService: "ready",
      geocoder: "ready",
    });
  });

  it("keeps liveness independent of external dependencies", () => {
    expect(controller.health()).toMatchObject({ status: "ok" });
    expect(database.$queryRaw).not.toHaveBeenCalled();
    expect(redis.ping).not.toHaveBeenCalled();
  });

  it("reports ready only after every required dependency responds", async () => {
    await expect(controller.ready()).resolves.toEqual({
      status: "ready",
      dependencies: {
        database: "ready",
        redis: "ready",
        tileService: "ready",
        geocoder: "ready",
      },
    });
  });

  it("fails readiness closed without exposing the failed dependency", async () => {
    maps.upstreamReadiness.mockRejectedValue(new Error("private hostname"));

    await expect(controller.ready()).rejects.toEqual(
      new ServiceUnavailableException("Service dependencies unavailable"),
    );
  });
});
