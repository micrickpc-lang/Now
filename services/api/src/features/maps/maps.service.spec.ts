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
    MAP_GEOCODER_RETRY_DELAY_MS: "250",
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
    delete values.MAP_MODE;
    delete values.GEOCODING_BASE_URL;
    delete values.REVERSE_GEOCODING_BASE_URL;
    delete values.GEOCODING_API_KEY;
    delete values.GEOCODING_API_KEY_HEADER;
    delete values.GEOCODING_API_KEY_QUERY_PARAM;
    delete values.MAP_GLOBAL_FALLBACK_TO_SELF_HOSTED;
  });

  afterAll(() => {
    global.fetch = originalFetch;
  });

  it("uses the requesting map origin for absolute Android tile URLs", () => {
    const base = "http://192.168.1.68/api/v1/maps";

    expect(service.style(base).sources.seychas).toMatchObject({
      type: "vector",
      tiles: [`${base}/tiles/{z}/{x}/{y}.pbf`],
    });
    expect(service.tileJson(base).tiles).toEqual([
      `${base}/tiles/{z}/{x}/{y}.pbf`,
    ]);
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

  it("uses the fixed global geocoder endpoint without exposing its key to clients", async () => {
    values.MAP_MODE = "global_provider";
    values.GEOCODING_BASE_URL = "https://geocoder.example.invalid/search";
    values.REVERSE_GEOCODING_BASE_URL =
      "https://geocoder.example.invalid/reverse";
    values.GEOCODING_API_KEY = "server-only-provider-key";
    global.fetch = jest.fn().mockResolvedValue(
      new Response(
        JSON.stringify([
          {
            place_id: "global-place",
            display_name: "Moscow, Russia",
            lat: "55.7558",
            lon: "37.6173",
            type: "city",
          },
        ]),
      ),
    );

    await expect(service.search("Moscow")).resolves.toEqual([
      {
        id: "global-place",
        label: "Moscow, Russia",
        latitude: 55.7558,
        longitude: 37.6173,
        type: "city",
      },
    ]);

    const [url] = (global.fetch as jest.Mock).mock.calls[0] as [URL];
    expect(url.origin).toBe("https://geocoder.example.invalid");
    expect(url.searchParams.get("q")).toBe("Moscow");
    expect(url.searchParams.get("key")).toBe("server-only-provider-key");
  });

  it("uses the fixed global reverse endpoint and server-side credential header", async () => {
    values.MAP_MODE = "global_provider";
    values.GEOCODING_BASE_URL = "https://geocoder.example.invalid/search";
    values.REVERSE_GEOCODING_BASE_URL =
      "https://geocoder.example.invalid/reverse";
    values.GEOCODING_API_KEY = "server-only-provider-key";
    values.GEOCODING_API_KEY_HEADER = "x-provider-key";
    global.fetch = jest.fn().mockResolvedValue(
      new Response(
        JSON.stringify({
          address: {
            city: "New York",
            state: "New York",
            country: "United States",
            country_code: "us",
          },
        }),
      ),
    );

    await expect(service.reverse(40.7484, -73.9857)).resolves.toEqual({
      label: "New York",
      address: {
        city: "New York",
        state: "New York",
        country: "United States",
        country_code: "us",
      },
    });

    const [url, init] = (global.fetch as jest.Mock).mock.calls[0] as [
      URL,
      RequestInit,
    ];
    expect(url.origin).toBe("https://geocoder.example.invalid");
    expect(url.searchParams.get("lat")).toBe("40.7484");
    expect(url.searchParams.get("lon")).toBe("-73.9857");
    expect(init.headers).toMatchObject({
      "x-provider-key": "server-only-provider-key",
    });
  });

  it("falls back to the private Nominatim endpoint when the global provider is unavailable", async () => {
    values.MAP_MODE = "global_provider";
    values.GEOCODING_BASE_URL = "https://geocoder.example.invalid/search";
    values.REVERSE_GEOCODING_BASE_URL =
      "https://geocoder.example.invalid/reverse";
    values.MAP_GLOBAL_FALLBACK_TO_SELF_HOSTED = "true";
    global.fetch = jest
      .fn()
      .mockResolvedValueOnce(new Response(null, { status: 503 }))
      .mockResolvedValueOnce(new Response(null, { status: 503 }))
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify([
            {
              place_id: "fallback-place",
              display_name: "Monaco",
              lat: "43.7384",
              lon: "7.4246",
            },
          ]),
        ),
      );

    await expect(service.search("Monaco")).resolves.toHaveLength(1);

    const calls = (global.fetch as jest.Mock).mock.calls as Array<[URL]>;
    expect(calls).toHaveLength(3);
    expect(calls[2][0].origin).toBe("http://nominatim:8080");
  });

  it("returns an explicit coordinate search locally without caching or upstream I/O", async () => {
    global.fetch = jest.fn();

    await expect(service.search("40.7484, -73.9857")).resolves.toEqual([
      expect.objectContaining({
        latitude: 40.7484,
        longitude: -73.9857,
        type: "coordinate",
      }),
    ]);
    expect(global.fetch).not.toHaveBeenCalled();
    expect(redis.setJson).not.toHaveBeenCalled();
  });
});
