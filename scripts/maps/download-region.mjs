import {
  createWriteStream,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  statSync,
  unlinkSync,
} from "node:fs";
import { dirname, resolve } from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

const root = resolve(import.meta.dirname, "../..");
const config = JSON.parse(
  readFileSync(resolve(root, "infra/maps/region.json"), "utf8"),
);
const destination = resolve(root, config.output);
const partial = `${destination}.partial`;
mkdirSync(dirname(destination), { recursive: true });

const response = await fetch(config.pbfUrl, { redirect: "follow" });
if (!response.ok || !response.body)
  throw new Error(`Region download failed: HTTP ${response.status}`);
const length = Number(response.headers.get("content-length") ?? 0);
if (length && length > config.maxBytes)
  throw new Error(`Region exceeds configured ${config.maxBytes} byte limit`);

if (existsSync(partial)) unlinkSync(partial);
await pipeline(
  Readable.fromWeb(response.body),
  createWriteStream(partial, { flags: "wx" }),
);
const downloaded = statSync(partial).size;
if (downloaded === 0 || downloaded > config.maxBytes) {
  unlinkSync(partial);
  throw new Error(`Unexpected download size: ${downloaded}`);
}
renameSync(partial, destination);
process.stdout.write(
  `Downloaded ${config.id}: ${downloaded} bytes -> ${config.output}\n`,
);
