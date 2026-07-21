import {
  BadGatewayException,
  BadRequestException,
  Injectable,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";

@Injectable()
export class MapsService {
  constructor(private readonly config: ConfigService) {}

  style() {
    const base =
      this.config.get<string>("MAP_PUBLIC_BASE_URL") ??
      "http://localhost:8080/maps";
    return {
      version: 8,
      name: "Сейчас Aurora v1",
      metadata: {
        "seychas:version": "1",
        attribution: "© OpenStreetMap contributors",
      },
      sources: {
        seychas: {
          type: "vector",
          tiles: [`${base}/tiles/{z}/{x}/{y}.pbf`],
          minzoom: 0,
          maxzoom: 14,
          attribution: "© OpenStreetMap contributors",
        },
      },
      layers: [
        {
          id: "background",
          type: "background",
          paint: { "background-color": "#0D1020" },
        },
        {
          id: "water",
          type: "fill",
          source: "seychas",
          "source-layer": "water",
          paint: { "fill-color": "#182E51" },
        },
        {
          id: "landuse",
          type: "fill",
          source: "seychas",
          "source-layer": "landuse",
          paint: { "fill-color": "#171B31", "fill-opacity": 0.7 },
        },
        {
          id: "roads",
          type: "line",
          source: "seychas",
          "source-layer": "transportation",
          paint: {
            "line-color": "#525A78",
            "line-width": ["interpolate", ["linear"], ["zoom"], 8, 0.4, 15, 3],
          },
        },
      ],
    };
  }

  async tile(
    z: number,
    x: number,
    y: number,
  ): Promise<{ body: ArrayBuffer; contentType: string }> {
    if (
      ![z, x, y].every(Number.isInteger) ||
      z < 0 ||
      z > 16 ||
      x < 0 ||
      y < 0
    ) {
      throw new BadRequestException("Invalid tile coordinates");
    }
    const internal =
      this.config.get<string>("INTERNAL_MARTIN_URL") ?? "http://martin:3000";
    const response = await fetch(`${internal}/seychas/${z}/${x}/${y}`);
    if (!response.ok) throw new BadGatewayException("Tile service unavailable");
    return {
      body: await response.arrayBuffer(),
      contentType:
        response.headers.get("content-type") ?? "application/x-protobuf",
    };
  }

  async search(query: string) {
    const internal =
      this.config.get<string>("INTERNAL_NOMINATIM_URL") ??
      "http://nominatim:8080";
    const url = new URL("/search", internal);
    url.searchParams.set("q", query.slice(0, 120));
    url.searchParams.set("format", "jsonv2");
    url.searchParams.set("limit", "8");
    url.searchParams.set("addressdetails", "1");
    const countryCodes = this.config.get<string>("SEARCH_COUNTRY_CODES");
    if (countryCodes) url.searchParams.set("countrycodes", countryCodes);
    const response = await fetch(url, {
      headers: { "user-agent": "seychas-private-geocoder/1.0" },
    });
    if (!response.ok)
      throw new BadGatewayException("Search service unavailable");
    const rows = (await response.json()) as Array<Record<string, unknown>>;
    return rows.map((row) => ({
      id: String(row.place_id),
      label: row.display_name,
      latitude: Number(row.lat),
      longitude: Number(row.lon),
      type: row.type,
    }));
  }

  async reverse(latitude: number, longitude: number) {
    const internal =
      this.config.get<string>("INTERNAL_NOMINATIM_URL") ??
      "http://nominatim:8080";
    const url = new URL("/reverse", internal);
    url.searchParams.set("lat", String(latitude));
    url.searchParams.set("lon", String(longitude));
    url.searchParams.set("format", "jsonv2");
    const response = await fetch(url, {
      headers: { "user-agent": "seychas-private-geocoder/1.0" },
    });
    if (!response.ok)
      throw new BadGatewayException("Reverse search unavailable");
    const row = (await response.json()) as Record<string, unknown>;
    return { label: row.display_name, address: row.address };
  }

  approximate(latitude: number, longitude: number) {
    const grid = 0.02;
    return {
      center: {
        latitude: Math.round(latitude / grid) * grid,
        longitude: Math.round(longitude / grid) * grid,
      },
      radiusMeters: 1800,
      precision: "reduced",
    };
  }
}
