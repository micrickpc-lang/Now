import "reflect-metadata";
import type { ConfigService } from "@nestjs/config";
import { validate } from "class-validator";
import { MapReverseDto } from "./maps.dto";
import { MapsService } from "./maps.service";

describe("MapsService", () => {
  const config = {
    get: jest.fn(() => "http://nominatim:8080"),
  } as unknown as ConfigService;
  const fetchSpy = jest.spyOn(global, "fetch");

  beforeEach(() => {
    jest.clearAllMocks();
  });

  afterAll(() => {
    fetchSpy.mockRestore();
  });

  it("uses a bounded short-lived clone cache for repeated geocoding", async () => {
    fetchSpy.mockResolvedValue(
      new Response(
        JSON.stringify([
          {
            place_id: 1,
            display_name: "Moscow",
            lat: "55.7558",
            lon: "37.6173",
            type: "city",
          },
        ]),
        { status: 200 },
      ),
    );
    const service = new MapsService(config);

    await expect(service.search("Moscow")).resolves.toEqual([
      expect.objectContaining({ latitude: 55.7558, longitude: 37.6173 }),
    ]);
    await expect(service.search("Moscow")).resolves.toHaveLength(1);
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });

  it("rejects a non-numeric reverse coordinate before it reaches the provider", async () => {
    const dto = new MapReverseDto();
    dto.lat = Number.NaN;
    dto.lon = 37.6173;

    await expect(validate(dto)).resolves.not.toHaveLength(0);
  });
});
