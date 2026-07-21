import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");
const style = JSON.parse(
  readFileSync(resolve(root, "infra/maps/assets/style-v1.json"), "utf8"),
);
if (
  style.version !== 8 ||
  !Array.isArray(style.layers) ||
  style.layers.length < 2
)
  throw new Error("Invalid MapLibre style structure");
if (!JSON.stringify(style).includes("© OpenStreetMap contributors"))
  throw new Error("Visible attribution metadata is required");

const allowed = [/^\//u, /^https:\/\/maps\.[a-z0-9.-]+\//u];
for (const source of Object.values(style.sources)) {
  for (const url of source.tiles ?? []) {
    if (!allowed.some((pattern) => pattern.test(url)))
      throw new Error(`Non-first-party tile URL: ${url}`);
  }
}
process.stdout.write(
  "Map style is valid and uses first-party/relative resources\n",
);
