import {
  BadGatewayException,
  BadRequestException,
  Injectable,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { createHash, createHmac, randomUUID } from "node:crypto";
import { PrismaService } from "../../common/prisma.service";
import { RedisService } from "../../common/redis.service";
import type { ApproximateLocationDto } from "./maps.dto";

const SAFE_LOCATION_DRAFT_TTL_MS = 15 * 60_000;
const MIN_APPROXIMATE_RADIUS_METERS = 2_000;
const MAX_APPROXIMATE_RADIUS_METERS = 10_000;
const GEOCODER_RETRYABLE_STATUSES = new Set([408, 429, 500, 502, 503, 504]);

export interface ReverseResult {
  label: string;
  address: Record<string, string>;
}

export interface SearchResult {
  id: string;
  label: string;
  latitude: number;
  longitude: number;
  type?: string;
}

export interface SafeCenter {
  latitude: number;
  longitude: number;
}

interface GeocoderEndpoint {
  url: string;
  selfHosted: boolean;
}

@Injectable()
export class MapsService {
  constructor(
    private readonly config: ConfigService,
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  style(requestBaseUrl?: string) {
    const base = this.mapBaseUrl(requestBaseUrl);
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

  tileJson(requestBaseUrl?: string) {
    const base = this.mapBaseUrl(requestBaseUrl);
    return {
      tilejson: "3.0.0",
      name: "Seychas Aurora v1",
      scheme: "xyz",
      tiles: [`${base}/tiles/{z}/{x}/{y}.pbf`],
      minzoom: 0,
      maxzoom: 14,
      attribution: "© OpenStreetMap contributors",
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
      z > 14 ||
      x < 0 ||
      y < 0 ||
      x >= 2 ** z ||
      y >= 2 ** z
    ) {
      throw new BadRequestException("Invalid tile coordinates");
    }
    const internal =
      this.config.get<string>("INTERNAL_MARTIN_URL") ?? "http://martin:3000";
    const response = await this.fetchUpstream(
      `${internal}/seychas/${z}/${x}/${y}`,
      undefined,
      "Tile service unavailable",
    );
    if (!response.ok) throw new BadGatewayException("Tile service unavailable");
    const declaredLength = Number(response.headers.get("content-length") ?? 0);
    if (declaredLength > 5_000_000) {
      throw new BadGatewayException(
        "Tile service returned an invalid response",
      );
    }
    const body = await response.arrayBuffer();
    if (body.byteLength > 5_000_000) {
      throw new BadGatewayException(
        "Tile service returned an invalid response",
      );
    }
    return {
      body,
      contentType:
        response.headers.get("content-type") ?? "application/x-protobuf",
    };
  }

  async search(query: string) {
    const normalized = query
      .normalize("NFKC")
      .replace(/\s+/gu, " ")
      .trim()
      .slice(0, 120);
    if (normalized.length < 2) {
      throw new BadRequestException("Search query must contain at least two characters");
    }
    const coordinate = this.coordinateSearchResult(normalized);
    if (coordinate) return [coordinate];

    const cacheKey = this.cacheKey(
      "search",
      normalized.toLocaleLowerCase("ru"),
    );
    const cached = await this.readCache<SearchResult[]>(cacheKey);
    if (cached) return cached;
    const payload = await this.requestGeocoder("search", normalized);
    const results = this.searchResults(payload);
    await this.writeCache(cacheKey, results, 300);
    return results;
  }

  async reverse(latitude: number, longitude: number): Promise<ReverseResult> {
    const cacheKey = this.cacheKey(
      "reverse",
      `${latitude.toFixed(5)}:${longitude.toFixed(5)}`,
    );
    const cached = await this.readCache<ReverseResult>(cacheKey);
    if (cached) return cached;
    const payload = await this.requestGeocoder("reverse", latitude, longitude);
    const row = this.reverseRow(payload);
    const rawAddress = this.addressObject(row.address);
    const address = this.administrativeAddress(rawAddress);
    const label =
      this.firstLabel(address, [
        "suburb",
        "city_district",
        "borough",
        "city",
        "town",
        "village",
        "municipality",
        "county",
        "state",
        "country",
      ]) ?? "Выбранная точка";
    const result = { label, address };
    await this.writeCache(cacheKey, result, 300);
    return result;
  }

  async upstreamReadiness() {
    if (this.mapMode() === "global_provider") {
      // The global style and geocoder are independent external services. Their
      // configured URLs are validated at startup; probing provider endpoints
      // can consume quota or require a request-specific credential.
      return { tileService: "external", geocoder: "configured" } as const;
    }
    const martin =
      this.config.get<string>("INTERNAL_MARTIN_URL") ?? "http://martin:3000";
    const nominatim =
      this.config.get<string>("INTERNAL_NOMINATIM_URL") ??
      "http://nominatim:8080";
    const [tileService, geocoder] = await Promise.all([
      this.fetchUpstream(
        `${martin}/catalog`,
        undefined,
        "Tile service unavailable",
      ),
      this.fetchUpstream(
        `${nominatim}/status.php?format=json`,
        undefined,
        "Search service unavailable",
      ),
    ]);
    if (!tileService.ok || !geocoder.ok) {
      throw new BadGatewayException("Map dependencies unavailable");
    }
    return { tileService: "ready", geocoder: "ready" } as const;
  }

  async createSafeLocation(ownerId: string, dto: ApproximateLocationDto) {
    const id = randomUUID();
    const expiresAt = new Date(Date.now() + SAFE_LOCATION_DRAFT_TTL_MS);

    if (dto.mode === "APPROXIMATE") {
      const radiusMeters = this.safeRadius(dto.accuracyMeters);
      const center = this.safeCenter(dto.latitude, dto.longitude, radiusMeters);
      const description = `Примерно в радиусе ${Math.ceil(radiusMeters / 1000)} км`;
      await this.prisma.$executeRaw`
        INSERT INTO "safe_location_zones" (
          "id", "owner_id", "mode", "safe_center", "radius_meters",
          "description", "expires_at", "updated_at"
        ) VALUES (
          ${id}::uuid,
          ${ownerId}::uuid,
          CAST(${dto.mode} AS "LocationMode"),
          ST_SetSRID(ST_MakePoint(${center.longitude}, ${center.latitude}), 4326)::geography,
          ${radiusMeters},
          ${description},
          ${expiresAt},
          now()
        )
      `;
      return {
        safeLocationId: id,
        mode: dto.mode,
        description,
        expiresAt,
        center,
        radiusMeters,
      };
    }

    const reverse = await this.reverse(dto.latitude, dto.longitude);
    const address = this.addressObject(reverse.address);
    const cityLabel = this.firstLabel(address, [
      "city",
      "town",
      "village",
      "municipality",
    ]);
    const districtLabel = this.firstLabel(address, [
      "suburb",
      "city_district",
      "borough",
      "county",
    ]);
    const label = dto.mode === "CITY" ? cityLabel : districtLabel;
    if (!label) {
      throw new BadGatewayException(
        dto.mode === "CITY"
          ? "City could not be determined"
          : "District could not be determined",
      );
    }
    const description =
      dto.mode === "CITY" ? `Город: ${label}` : `Район: ${label}`;
    await this.prisma.$executeRaw`
      INSERT INTO "safe_location_zones" (
        "id", "owner_id", "mode", "description", "city_label",
        "district_label", "expires_at", "updated_at"
      ) VALUES (
        ${id}::uuid,
        ${ownerId}::uuid,
        CAST(${dto.mode} AS "LocationMode"),
        ${description},
        ${dto.mode === "CITY" ? label : null},
        ${dto.mode === "DISTRICT" ? label : null},
        ${expiresAt},
        now()
      )
    `;
    return {
      safeLocationId: id,
      mode: dto.mode,
      description,
      expiresAt,
    };
  }

  private publicBaseUrl() {
    return (
      this.config.get<string>("MAP_PUBLIC_BASE_URL") ??
      "http://localhost:8080/maps"
    ).replace(/\/+$/u, "");
  }

  private mapBaseUrl(requestBaseUrl?: string) {
    return requestBaseUrl?.replace(/\/+$/u, "") || this.publicBaseUrl();
  }

  private mapMode(): "self_hosted" | "global_provider" {
    return this.config.get<string>("MAP_MODE") === "global_provider"
      ? "global_provider"
      : "self_hosted";
  }

  private geocoderEndpoint(
    operation: "search" | "reverse",
    mode: "self_hosted" | "global_provider" = this.mapMode(),
  ): GeocoderEndpoint {
    if (mode === "self_hosted") {
      const internal =
        this.config.get<string>("INTERNAL_NOMINATIM_URL") ??
        "http://nominatim:8080";
      return {
        url: new URL(`/${operation}`, internal).toString(),
        selfHosted: true,
      };
    }

    const key =
      operation === "search"
        ? "GEOCODING_BASE_URL"
        : "REVERSE_GEOCODING_BASE_URL";
    const url = this.config.get<string>(key);
    if (!url) throw new BadGatewayException("Geocoding service unavailable");
    return { url, selfHosted: false };
  }

  private async requestGeocoder(
    operation: "search" | "reverse",
    value: string | number,
    longitude?: number,
  ): Promise<unknown> {
    const primary = this.geocoderEndpoint(operation);
    try {
      return await this.fetchGeocoder(primary, operation, value, longitude);
    } catch (error) {
      if (
        primary.selfHosted ||
        this.config.get<string>("MAP_GLOBAL_FALLBACK_TO_SELF_HOSTED") ===
          "false" ||
        !(error instanceof BadGatewayException)
      ) {
        throw error;
      }
      return this.fetchGeocoder(
        this.geocoderEndpoint(operation, "self_hosted"),
        operation,
        value,
        longitude,
      );
    }
  }

  private async fetchGeocoder(
    endpoint: GeocoderEndpoint,
    operation: "search" | "reverse",
    value: string | number,
    longitude?: number,
  ): Promise<unknown> {
    const url = new URL(endpoint.url);
    const headers: Record<string, string> = {
      "user-agent": "seychas-geocoder-proxy/1.0",
      "accept-language": "ru",
    };
    if (operation === "search") {
      url.searchParams.set("q", String(value));
      url.searchParams.set("limit", "8");
      url.searchParams.set("addressdetails", "1");
      if (endpoint.selfHosted) {
        const countryCodes = this.config.get<string>("SEARCH_COUNTRY_CODES");
        if (countryCodes) url.searchParams.set("countrycodes", countryCodes);
      }
    } else {
      url.searchParams.set("lat", String(value));
      url.searchParams.set("lon", String(longitude));
    }
    url.searchParams.set("format", "jsonv2");
    this.applyGlobalCredential(url, headers, endpoint.selfHosted);

    const unavailableMessage =
      operation === "search"
        ? "Search service unavailable"
        : "Reverse search unavailable";
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        const response = await this.fetchUpstream(
          url,
          { headers },
          unavailableMessage,
        );
        if (response.ok) {
          return this.readGeocoderPayload(response, unavailableMessage);
        }
        if (
          !GEOCODER_RETRYABLE_STATUSES.has(response.status) ||
          attempt === 1
        ) {
          throw new BadGatewayException(unavailableMessage);
        }
      } catch (error) {
        if (attempt === 1 || !(error instanceof BadGatewayException)) {
          throw error;
        }
      }
      await this.waitForGeocoderRetry();
    }
    throw new BadGatewayException(unavailableMessage);
  }

  private waitForGeocoderRetry(): Promise<void> {
    const configured = Number(
      this.config.get<string>("MAP_GEOCODER_RETRY_DELAY_MS") ?? "1200",
    );
    const delay = Number.isFinite(configured)
      ? Math.max(250, Math.min(3_000, configured))
      : 1_200;
    return new Promise((resolve) => setTimeout(resolve, delay));
  }

  private applyGlobalCredential(
    url: URL,
    headers: Record<string, string>,
    selfHosted: boolean,
  ) {
    if (selfHosted) return;
    const apiKey = this.config.get<string>("GEOCODING_API_KEY")?.trim();
    if (!apiKey) return;
    const header = this.config
      .get<string>("GEOCODING_API_KEY_HEADER")
      ?.trim();
    if (header) {
      headers[header] = apiKey;
      return;
    }
    const parameter =
      this.config.get<string>("GEOCODING_API_KEY_QUERY_PARAM")?.trim() ||
      "key";
    url.searchParams.set(parameter, apiKey);
  }

  private async readGeocoderPayload(
    response: Response,
    unavailableMessage: string,
  ): Promise<unknown> {
    const declaredLength = Number(response.headers.get("content-length") ?? 0);
    if (declaredLength > 2_000_000) {
      throw new BadGatewayException(unavailableMessage);
    }
    try {
      const body = await response.arrayBuffer();
      if (body.byteLength > 2_000_000) {
        throw new BadGatewayException(unavailableMessage);
      }
      return JSON.parse(new TextDecoder().decode(body)) as unknown;
    } catch {
      throw new BadGatewayException(unavailableMessage);
    }
  }

  private searchResults(payload: unknown): SearchResult[] {
    const rows = Array.isArray(payload)
      ? payload
      : this.geoJsonRows(this.addressObject(payload));
    return rows
      .map((row) => this.searchResult(this.addressObject(row)))
      .filter((row): row is SearchResult => row !== undefined)
      .slice(0, 8);
  }

  private geoJsonRows(payload: Record<string, unknown>): unknown[] {
    if (!Array.isArray(payload.features)) return [];
    return payload.features.map((feature) => {
      const value = this.addressObject(feature);
      const properties = this.addressObject(value.properties);
      const geometry = this.addressObject(value.geometry);
      const coordinates = Array.isArray(geometry.coordinates)
        ? geometry.coordinates
        : [];
      return {
        place_id: value.id,
        display_name:
          properties.place_name ??
          properties.full_address ??
          properties.name ??
          value.text,
        lat: coordinates[1],
        lon: coordinates[0],
        type: properties.type ?? properties.feature_type,
      };
    });
  }

  private searchResult(
    row: Record<string, unknown>,
  ): SearchResult | undefined {
    const latitude = Number(row.lat);
    const longitude = Number(row.lon);
    const label = this.safeString(row.display_name, 240);
    if (
      !label ||
      !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      return undefined;
    }
    const type = this.safeString(row.type, 60);
    return {
      id:
        this.safeString(row.place_id, 80) ??
        this.cacheKey("place", `${latitude}:${longitude}`),
      label,
      latitude,
      longitude,
      ...(type ? { type } : {}),
    };
  }

  private reverseRow(payload: unknown): Record<string, unknown> {
    const row = this.addressObject(payload);
    if (Object.keys(row).length > 0 && !Array.isArray(row.features)) return row;

    const feature = Array.isArray(row.features) ? row.features[0] : undefined;
    const value = this.addressObject(feature);
    const properties = this.addressObject(value.properties);
    return {
      address: {
        city: properties.city ?? properties.place ?? properties.locality,
        city_district: properties.district ?? properties.neighborhood,
        county: properties.county,
        state: properties.region ?? properties.state,
        country: properties.country,
        country_code: properties.country_code,
      },
    };
  }

  private coordinateSearchResult(query: string): SearchResult | undefined {
    const match = /^([+-]?\d{1,2}(?:\.\d+)?),\s*([+-]?\d{1,3}(?:\.\d+)?)$/u.exec(
      query,
    );
    if (!match) return undefined;
    const latitude = Number(match[1]);
    const longitude = Number(match[2]);
    if (
      !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) ||
      latitude < -90 ||
      latitude > 90 ||
      longitude < -180 ||
      longitude > 180
    ) {
      return undefined;
    }
    return {
      id: this.cacheKey("coordinate", `${latitude}:${longitude}`),
      label: `${latitude}, ${longitude}`,
      latitude,
      longitude,
      type: "coordinate",
    };
  }

  private async fetchUpstream(
    input: string | URL,
    init: RequestInit | undefined,
    unavailableMessage: string,
  ): Promise<Response> {
    const timeoutMs = Number(
      this.config.get<string>("MAP_UPSTREAM_TIMEOUT_MS") ?? "3000",
    );
    try {
      return await fetch(input, {
        ...init,
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch {
      throw new BadGatewayException(unavailableMessage);
    }
  }

  private cacheKey(namespace: string, value: string): string {
    const digest = createHash("sha256").update(value).digest("hex");
    return `maps:v1:${namespace}:${digest}`;
  }

  private async readCache<T>(key: string): Promise<T | undefined> {
    try {
      return await this.redis.getJson<T>(key);
    } catch {
      return undefined;
    }
  }

  private async writeCache(key: string, value: unknown, ttlSeconds: number) {
    try {
      await this.redis.setJson(key, value, ttlSeconds);
    } catch {
      // Geocoding remains available if the cache is temporarily unavailable.
    }
  }

  private safeRadius(accuracyMeters: number): number {
    const normalized = Math.ceil(Math.max(0, accuracyMeters) / 250) * 250;
    return Math.min(
      MAX_APPROXIMATE_RADIUS_METERS,
      Math.max(MIN_APPROXIMATE_RADIUS_METERS, normalized),
    );
  }

  private safeCenter(
    latitude: number,
    longitude: number,
    radiusMeters: number,
  ): SafeCenter {
    const secret = this.config.getOrThrow<string>("LOCATION_PRIVACY_SECRET");
    const digest = createHmac("sha256", secret)
      .update(`safe-location-grid-v1:${radiusMeters}`)
      .digest();
    const latitudeShift =
      (digest.readUInt32BE(0) / 0x1_0000_0000) * radiusMeters;
    const longitudeShift =
      (digest.readUInt32BE(4) / 0x1_0000_0000) * radiusMeters;
    const metersPerDegree = 111_320;
    const cosine = Math.max(0.01, Math.cos((latitude * Math.PI) / 180));
    const northing = latitude * metersPerDegree;
    const easting = longitude * metersPerDegree * cosine;
    const safeNorthing =
      Math.floor((northing + latitudeShift) / radiusMeters) * radiusMeters +
      radiusMeters / 2 -
      latitudeShift;
    const safeEasting =
      Math.floor((easting + longitudeShift) / radiusMeters) * radiusMeters +
      radiusMeters / 2 -
      longitudeShift;
    return {
      latitude: this.roundCoordinate(
        Math.max(-90, Math.min(90, safeNorthing / metersPerDegree)),
      ),
      longitude: this.roundCoordinate(
        Math.max(-180, Math.min(180, safeEasting / (metersPerDegree * cosine))),
      ),
    };
  }

  private roundCoordinate(value: number): number {
    return Math.round(value * 1_000_000) / 1_000_000;
  }

  private addressObject(value: unknown): Record<string, unknown> {
    return typeof value === "object" && value !== null
      ? (value as Record<string, unknown>)
      : {};
  }

  private administrativeAddress(
    address: Record<string, unknown>,
  ): Record<string, string> {
    const allowed = [
      "city",
      "town",
      "village",
      "municipality",
      "suburb",
      "city_district",
      "borough",
      "county",
      "state",
      "country",
      "country_code",
    ];
    return Object.fromEntries(
      allowed.flatMap((key) => {
        const value = this.safeString(address[key], 100);
        return value ? [[key, value]] : [];
      }),
    );
  }

  private safeString(value: unknown, maxLength: number): string | undefined {
    if (typeof value !== "string" && typeof value !== "number") {
      return undefined;
    }
    const normalized = String(value).trim().slice(0, maxLength);
    return normalized || undefined;
  }

  private firstLabel(
    address: Record<string, unknown>,
    keys: string[],
  ): string | undefined {
    for (const key of keys) {
      const candidate = address[key];
      if (typeof candidate !== "string") continue;
      const label = candidate.trim().slice(0, 100);
      if (label) return label;
    }
    return undefined;
  }
}
