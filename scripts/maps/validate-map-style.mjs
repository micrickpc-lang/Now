import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  closeSync,
  existsSync,
  openSync,
  readFileSync,
  readSync,
  statSync,
} from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");

function usage() {
  process.stdout
    .write(`Usage: node scripts/maps/validate-map-style.mjs [options]

Statically validate the versioned style, Tilemaker profile, checksum policy and
generated first-party sprite/glyph assets. Optionally validate MBTiles framing.

Options:
  --style <path>            Style JSON (default: infra/maps/assets/v1/style.json)
  --region <path>           Region JSON (default: infra/maps/region.json)
  --tilemaker-config <path> Tilemaker JSON config
  --mbtiles <path>          Also check a built MBTiles file
  --help                    Show this help
`);
}

function parseArgs(argv) {
  const options = {
    style: resolve(root, "infra/maps/assets/v1/style.json"),
    region: resolve(root, "infra/maps/region.json"),
    tilemakerConfig: resolve(root, "infra/maps/tilemaker/config.json"),
    mbtiles: null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--help" || argument === "-h") {
      usage();
      process.exit(0);
    }
    const value = argv[index + 1];
    if (!value) throw new Error(`${argument} requires a path`);
    if (argument === "--style") options.style = resolve(value);
    else if (argument === "--region") options.region = resolve(value);
    else if (argument === "--tilemaker-config") {
      options.tilemakerConfig = resolve(value);
    } else if (argument === "--mbtiles") options.mbtiles = resolve(value);
    else throw new Error(`Unknown option: ${argument}`);
    index += 1;
  }
  return options;
}

function readJson(path, label) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    throw new Error(`${label} is not valid JSON: ${error.message}`);
  }
}

function requireCondition(condition, message) {
  if (!condition) throw new Error(message);
}

const options = parseArgs(process.argv.slice(2));
const style = readJson(options.style, "Map style");
const region = readJson(options.region, "Region config");
const tilemaker = readJson(options.tilemakerConfig, "Tilemaker config");
const processLua = readFileSync(
  resolve(root, "infra/maps/tilemaker/process.lua"),
  "utf8",
);
const tilemakerImage = readFileSync(
  resolve(root, "infra/maps/tilemaker/image.txt"),
  "utf8",
).trim();
const nginx = readFileSync(resolve(root, "infra/nginx/staging.conf"), "utf8");
const compose = readFileSync(
  resolve(root, "docker-compose.staging.yml"),
  "utf8",
);
const martin = readFileSync(resolve(root, "infra/maps/martin.yaml"), "utf8");
const compatibilityStyle = readJson(
  resolve(root, "infra/maps/assets/style-v1.json"),
  "Compatibility map style",
);
const networkAllowlist = readJson(
  resolve(root, "infra/nginx/network-allowlist.json"),
  "Map network allowlist",
);
const mobileConfig = readFileSync(
  resolve(root, "apps/mobile/lib/core/config/app_config.dart"),
  "utf8",
);
const mobileRepository = readFileSync(
  resolve(root, "apps/mobile/lib/features/map/data/maps_repository.dart"),
  "utf8",
);
const mapsController = readFileSync(
  resolve(root, "services/api/src/features/maps/maps.controller.ts"),
  "utf8",
);
const mapsService = readFileSync(
  resolve(root, "services/api/src/features/maps/maps.service.ts"),
  "utf8",
);

requireCondition(style.version === 8, "MapLibre style version must be 8");
requireCondition(
  Array.isArray(style.layers) && style.layers.length >= 2,
  "Map style must contain render layers",
);
requireCondition(
  JSON.stringify(style.metadata).includes("© OpenStreetMap contributors"),
  "OpenStreetMap attribution metadata is required",
);
requireCondition(
  style.metadata?.["seychas:version"] === "v1",
  "Style metadata must carry the immutable v1 identifier",
);
requireCondition(
  style.sprite === "/maps/v1/sprites/sprite",
  "Style sprite endpoint must be first-party and versioned",
);
requireCondition(
  style.glyphs === "/maps/v1/glyphs/{fontstack}/{range}.pbf",
  "Style glyph endpoint must be first-party and versioned",
);
requireCondition(
  style.layers.every((layer) => layer.type !== "symbol"),
  "The generated minimal glyph set is valid only while v1 has no symbol layers",
);
requireCondition(
  JSON.stringify(compatibilityStyle) === JSON.stringify(style),
  "Compatibility and canonical v1 styles have drifted",
);

const sourceLayers = new Set();
for (const source of Object.values(style.sources ?? {})) {
  requireCondition(
    source.type === "vector",
    "Only vector map sources are allowed",
  );
  for (const url of source.tiles ?? []) {
    requireCondition(
      url === "/maps/v1/tiles/{z}/{x}/{y}.pbf",
      `Tile URL is not the approved versioned first-party endpoint: ${url}`,
    );
    requireCondition(
      !url.includes("?"),
      "Tile URLs must not contain query data",
    );
  }
}
for (const layer of style.layers) {
  if (layer["source-layer"]) sourceLayers.add(layer["source-layer"]);
}
for (const sourceLayer of sourceLayers) {
  requireCondition(
    Object.hasOwn(tilemaker.layers ?? {}, sourceLayer),
    `Style source-layer is missing from Tilemaker config: ${sourceLayer}`,
  );
  requireCondition(
    processLua.includes(`:Layer("${sourceLayer}"`),
    `Tilemaker Lua never emits source-layer: ${sourceLayer}`,
  );
}

requireCondition(region.schemaVersion === 1, "Region schemaVersion must be 1");
requireCondition(region.datasetVersion === "v1", "Region dataset must be v1");
requireCondition(
  region.checksumAlgorithm === "md5",
  "Geofabrik checksumAlgorithm must be md5",
);
requireCondition(
  new URL(region.pbfUrl).protocol === "https:" &&
    new URL(region.checksumUrl).protocol === "https:",
  "Region and checksum URLs must use HTTPS",
);
requireCondition(
  region.pinnedSha256 == null || /^[a-f0-9]{64}$/u.test(region.pinnedSha256),
  "pinnedSha256 must be null or a lowercase SHA-256",
);
requireCondition(
  region.mbtilesOutput.endsWith("seychas-v1.mbtiles"),
  "MBTiles output must carry its v1 identifier",
);
requireCondition(
  /^ghcr\.io\/systemed\/tilemaker@sha256:[a-f0-9]{64}$/u.test(tilemakerImage),
  "Tilemaker image must use an immutable sha256 digest, never latest/master",
);
requireCondition(
  tilemaker.settings?.version === "1" && tilemaker.settings?.maxzoom === 14,
  "Tilemaker metadata/version or maxzoom is unexpected",
);
requireCondition(
  processLua.includes("function node_function") &&
    processLua.includes("function way_function"),
  "Tilemaker Lua entry points are missing",
);

execFileSync(
  process.execPath,
  [resolve(root, "scripts/maps/generate-assets.mjs"), "--check"],
  { stdio: "inherit" },
);
const manifest = readJson(
  resolve(root, "infra/maps/assets/v1/manifest.json"),
  "Generated asset manifest",
);
for (const requiredAsset of [
  "sprites/sprite.json",
  "sprites/sprite.png",
  "sprites/sprite@2x.json",
  "sprites/sprite@2x.png",
  "glyphs/Noto Sans Regular/0-255.pbf",
]) {
  requireCondition(
    Object.hasOwn(manifest.files ?? {}, requiredAsset),
    `Generated asset manifest is missing: ${requiredAsset}`,
  );
}
for (const [path, expectation] of Object.entries(manifest.files ?? {})) {
  const asset = resolve(root, "infra/maps/assets/v1", path);
  requireCondition(
    existsSync(asset),
    `Generated map asset is missing: ${path}`,
  );
  const content = readFileSync(asset);
  requireCondition(content.length === expectation.bytes, `Wrong size: ${path}`);
  requireCondition(
    createHash("sha256").update(content).digest("hex") === expectation.sha256,
    `Wrong SHA-256: ${path}`,
  );
}

for (const requiredNginxFragment of [
  "location = /api/v1/maps/style.json {",
  "alias /srv/maps/v1/style.json;",
  "location = /maps/v1/style.json {",
  "location ^~ /maps/v1/sprites/ {",
  "alias /srv/maps/v1/sprites/;",
  "location ^~ /maps/v1/glyphs/ {",
  "alias /srv/maps/v1/glyphs/;",
  "location ~ ^/maps/v1/tiles/",
  "rewrite ^ /api/v1/maps/tiles/$tile_z/$tile_x/$tile_y.pbf break;",
  "location ~ ^/api/v1/maps/tiles/",
  "location ~ ^/api/v1/maps/(search|reverse)$",
]) {
  requireCondition(
    nginx.includes(requiredNginxFragment),
    `Nginx public map graph is missing: ${requiredNginxFragment}`,
  );
}
for (const forbiddenLogValue of ["$request_uri", "$query_string", "$args"]) {
  requireCondition(
    !nginx.includes(forbiddenLogValue),
    `Nginx map logs/cache must not use query-bearing ${forbiddenLogValue}`,
  );
}
for (const requiredComposeFragment of [
  "MAP_PUBLIC_BASE_URL: http://${PUBLIC_IP:?set the server IPv4 address}/api/v1/maps",
  "INTERNAL_MARTIN_URL: http://martin:3000",
  "INTERNAL_NOMINATIM_URL: http://nominatim:8080",
  "./infra/maps/assets:/srv/maps:ro",
  "${NOW_DATA_ROOT:-/opt/now/data}/maps:/data:ro",
]) {
  requireCondition(
    compose.includes(requiredComposeFragment),
    `Staging Compose map graph is missing: ${requiredComposeFragment}`,
  );
}
requireCondition(
  martin.includes("seychas: /data/seychas-v1.mbtiles"),
  "Martin does not expose the versioned MBTiles as the internal seychas source",
);
for (const route of [
  '@Get("style.json")',
  '@Get("tilejson.json")',
  '@Get("tiles/:z/:x/:y")',
  '@Get("search")',
  '@Get("reverse")',
]) {
  requireCondition(
    mapsController.includes(route),
    `API map controller route is missing: ${route}`,
  );
}
for (const upstream of [
  "`${internal}/seychas/${z}/${x}/${y}`",
  'new URL("/search", internal)',
  'new URL("/reverse", internal)',
  "`${martin}/catalog`",
  "`${nominatim}/status.php?format=json`",
]) {
  requireCondition(
    mapsService.includes(upstream),
    `API internal map route is missing: ${upstream}`,
  );
}
requireCondition(
  mobileConfig.includes("'$apiBaseUrl/maps/style.json'"),
  "Mobile default style URL no longer matches the Nginx API-style alias",
);
for (const mobileRoute of ["'/maps/search'", "'/maps/reverse'"]) {
  requireCondition(
    mobileRepository.includes(mobileRoute),
    `Mobile map repository route is missing: ${mobileRoute}`,
  );
}
for (const publicPath of [
  "/api/v1/maps/style.json",
  "/api/v1/maps/tilejson.json",
  "/api/v1/maps/tiles/",
  "/api/v1/maps/search",
  "/api/v1/maps/reverse",
  "/maps/v1/style.json",
  "/maps/v1/tiles/",
  "/maps/v1/sprites/",
  "/maps/v1/glyphs/",
]) {
  requireCondition(
    networkAllowlist.mapResourcePaths?.includes(publicPath),
    `Map network allowlist is missing: ${publicPath}`,
  );
}
requireCondition(
  networkAllowlist.requiresHttps === true &&
    networkAllowlist.stagingBareIpHttpOnly === true,
  "Network allowlist must distinguish production HTTPS from bare-IP staging HTTP",
);

if (options.mbtiles) {
  requireCondition(existsSync(options.mbtiles), "MBTiles file does not exist");
  requireCondition(
    statSync(options.mbtiles).size >= 4096,
    "MBTiles file is unexpectedly small",
  );
  const header = Buffer.alloc(16);
  const handle = openSync(options.mbtiles, "r");
  try {
    readSync(handle, header, 0, header.length, 0);
  } finally {
    closeSync(handle);
  }
  requireCondition(
    header.equals(Buffer.from("SQLite format 3\0", "binary")),
    "MBTiles file does not have a SQLite header",
  );
}

process.stdout.write(
  "Map graph is valid end-to-end: mobile/API URLs, Nginx aliases/rewrite, Martin source, Nominatim routes, versioned assets and checksum pipeline\n",
);
