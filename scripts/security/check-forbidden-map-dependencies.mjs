import { readdirSync, readFileSync, statSync } from "node:fs";
import { extname, relative, resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");
const forbidden = [
  "googleapis.com",
  "maps.googleapis.com",
  "yandex",
  "mapbox",
  "2gis",
  "here.com",
  "bing.com/maps",
  "tile.openstreetmap.org",
  "nominatim.openstreetmap.org",
  "router.project-osrm.org",
  "google_maps_flutter",
  "mapbox_maps_flutter",
];
const extensions = new Set([
  ".dart",
  ".ts",
  ".tsx",
  ".js",
  ".mjs",
  ".json",
  ".yaml",
  ".yml",
  ".xml",
  ".gradle",
  ".kts",
  ".swift",
  ".kt",
  ".conf",
]);
const ignored = new Set([
  "node_modules",
  ".git",
  ".dart_tool",
  "build",
  ".next",
  "dist",
  "docs",
]);
const self = resolve(import.meta.filename);
const findings = [];

function walk(directory) {
  for (const entry of readdirSync(directory)) {
    if (
      ignored.has(entry) ||
      entry === "package-lock.json" ||
      entry === "pubspec.lock"
    )
      continue;
    const path = resolve(directory, entry);
    if (path === self) continue;
    const stats = statSync(path);
    if (stats.isDirectory()) walk(path);
    else if (extensions.has(extname(path))) {
      const content = readFileSync(path, "utf8").toLocaleLowerCase("en-US");
      for (const value of forbidden)
        if (content.includes(value))
          findings.push(`${relative(root, path)}: ${value}`);
    }
  }
}

walk(root);
if (findings.length) {
  process.stderr.write(
    `Forbidden external map dependencies/endpoints:\n${findings.join("\n")}\n`,
  );
  process.exit(1);
}
process.stdout.write(
  "No forbidden external map SDKs or endpoints found in source/network configuration\n",
);
