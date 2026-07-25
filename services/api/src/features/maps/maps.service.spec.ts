import { BadGatewayException, BadRequestException } from "@nestjs/common";
import type { ConfigService } from "@nestjs/config";
import type { PrismaService } from "../../common/prisma.service";
import type { RedisService } from "../../common/redis.service";
import { MapsService } from "./maps.service";

describe("MapsService", () => {
  const originalFetch = global.fetch;
  const executeRaw = jest.fn().mockResolvedValue(1);
  const redis = {
    getJson: jest.fn().mockResolvedValue(undefined),
    setJson: jest.fn().mockResolvedValue("OK"),
  };
  const values: Record<string, string> = {
    INTERNAL_MARTIN_URL: "http://martin:3000",
    INTERNAL_NOMINATIM_URL: "http://nominatim:8080",
    LOCATION_PRIVACY_SECRET: "privacy-secret-that-is-long-enough-for-tests",
    MAP_UPSTREAM_TIMEOUT_MS: "1000",
  };
  const config = {
    get: jest.fn((key: string) => values[key]),
    getOrThrow: jest.fn((key: string) => {
      const value = values[key];
      if (!value) throw new Error(`Missing ${key}`);
      return value;
    }),
  };

  const service = new MapsService(
    config as unknown as ConfigService,
    { $executeRaw: executeRaw } as unknown as PrismaService,
    redis as unknown as RedisService,
  );

  beforeEach(() => {
    jest.clearAllMocks();
    redis.getJson.mockResolvedValue(undefined);
    redis.setJson.mockResolvedValue("OK");
  });

  afterAll(() => {
    global.fetch = originalFetch;
  });

  it("rejects XYZ coordinates outside the zoom grid before an upstream call", async () => {
    global.fetch = jest.fn();

    await expect(service.tile(2, 4, 0)).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it("does not persist the source GPS coordinate when creating an approximate zone", async () => {
    const latitude = 43.7384;
    const longitude = 7.4246;

    const result = await service.createSafeLocation("owner-id", {
      mode: "APPROXIMATE",
      latitude,
      longitude,
      accuracyMeters: 18,
    });

    expect(result.radiusMeters).toBe(2_000);
    expect(result.center).not.toEqual({ latitude, longitude });
    const [executeRawCall] = executeRaw.mock.calls as unknown as Array<
      [unknown, ...unknown[]]
    >;
    const boundValues = executeRawCall?.slice(1) ?? [];
    expect(boundValues).not.toContain(latitude);
    expect(boundValues).not.toContain(longitude);
  });

  it("returns and caches only administrative reverse-geocoding fields", async () => {
    global.fetch = jest.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          display_name: "1 Exact Street, Monaco",
          address: {
            house_number: "1",
            road: "Exact Street",
            suburb: "Monte-Carlo",
            city: "Monaco",
            country: "Monaco",
            country_code: "mc",
          },
        }),
      ),
    );

    const result = await service.reverse(43.7384, 7.4246);

    expect(result).toEqual({
      label: "Monte-Carlo",
      address: {
        city: "Monaco",
        suburb: "Monte-Carlo",
        country: "Monaco",
        country_code: "mc",
      },
    });
    const [setJsonCall] = redis.setJson.mock.calls as unknown as Array<
      [string, unknown]
    >;
    expect(JSON.stringify(setJsonCall?.[1])).not.toContain("Exact Street");
    expect(setJsonCall?.[0]).not.toContain("43.7384");
  });

  it("maps upstream network failures to a non-sensitive gateway error", async () => {
    global.fetch = jest.fn().mockRejectedValue(new Error("private upstream"));

    await expect(service.search("Monte Carlo")).rejects.toEqual(
      new BadGatewayException("Search service unavailable"),
    );
  });
});
