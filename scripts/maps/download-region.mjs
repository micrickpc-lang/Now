import { createHash } from "node:crypto";
import {
  createReadStream,
  createWriteStream,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, relative, resolve, sep } from "node:path";
import { Readable, Transform } from "node:stream";
import { pipeline } from "node:stream/promises";

const root = resolve(import.meta.dirname, "../..");

function usage() {
  process.stdout.write(`Usage: node scripts/maps/download-region.mjs [options]

Download the configured Monaco PBF, verify Geofabrik's HTTPS checksum before
publishing it, and record both MD5 and SHA-256 in a local metadata sidecar.

Options:
  --config <path>  Region config (default: infra/maps/region.json)
  --force          Download again even when the local verified file exists
  --verify-only    Verify the local PBF and metadata without network access
  --help           Show this help
`);
}

function parseArgs(argv) {
  const options = {
    config: resolve(root, "infra/maps/region.json"),
    force: false,
    verifyOnly: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--help" || argument === "-h") {
      usage();
      process.exit(0);
    } else if (argument === "--force") {
      options.force = true;
    } else if (argument === "--verify-only") {
      options.verifyOnly = true;
    } else if (argument === "--config") {
      const value = argv[index + 1];
      if (!value) throw new Error("--config requires a path");
      options.config = resolve(value);
      index += 1;
    } else {
      throw new Error(`Unknown option: ${argument}`);
    }
  }
  if (options.force && options.verifyOnly) {
    throw new Error("--force and --verify-only cannot be combined");
  }
  return options;
}

function pathInsideRoot(value, label) {
  const absolute = resolve(root, value);
  if (absolute !== root && !absolute.startsWith(`${root}${sep}`)) {
    throw new Error(`${label} must stay inside the repository`);
  }
  return absolute;
}

function validateConfig(config) {
  if (config.schemaVersion !== 1) throw new Error("Unsupported region schema");
  if (config.checksumAlgorithm !== "md5") {
    throw new Error("Geofabrik checksumAlgorithm must be md5");
  }
  for (const field of ["pbfUrl", "checksumUrl"]) {
    const url = new URL(config[field]);
    if (url.protocol !== "https:") throw new Error(`${field} must use HTTPS`);
  }
  if (
    new URL(config.pbfUrl).hostname !== new URL(config.checksumUrl).hostname
  ) {
    throw new Error("PBF and checksum must use the same trusted host");
  }
  if (!/^[\w.-]+\.osm\.pbf$/u.test(config.checksumFileName ?? "")) {
    throw new Error("checksumFileName must be an OSM PBF basename");
  }
  if (
    config.pinnedSha256 != null &&
    config.pinnedSha256 !== "" &&
    !/^[a-f0-9]{64}$/u.test(config.pinnedSha256)
  ) {
    throw new Error("pinnedSha256 must be null or 64 lowercase hex digits");
  }
  if (
    !Number.isSafeInteger(config.maxBytes) ||
    config.maxBytes < 1024 ||
    config.maxBytes > 100_000_000
  ) {
    throw new Error("maxBytes must be between 1024 and 100000000");
  }
}

async function fetchChecksum(config) {
  const response = await fetch(config.checksumUrl, {
    redirect: "follow",
    headers: {
      accept: "text/plain",
      "user-agent": "seychas-map-pipeline/1.0",
    },
  });
  if (!response.ok) {
    throw new Error(`Checksum download failed: HTTP ${response.status}`);
  }
  if (new URL(response.url).protocol !== "https:") {
    throw new Error("Checksum redirect left HTTPS");
  }
  const manifest = await response.text();
  if (Buffer.byteLength(manifest) > 8192) {
    throw new Error("Checksum manifest is unexpectedly large");
  }
  for (const line of manifest.split(/\r?\n/u)) {
    const match = /^([a-fA-F0-9]{32})\s+\*?(.+?)\s*$/u.exec(line);
    if (
      match &&
      basename(match[2].replaceAll("\\", "/")) === config.checksumFileName
    ) {
      return match[1].toLowerCase();
    }
  }
  throw new Error(
    `Checksum manifest has no exact ${config.checksumFileName} entry`,
  );
}

async function hashFile(path) {
  const md5 = createHash("md5");
  const sha256 = createHash("sha256");
  let bytes = 0;
  for await (const chunk of createReadStream(path)) {
    bytes += chunk.length;
    md5.update(chunk);
    sha256.update(chunk);
  }
  return { bytes, md5: md5.digest("hex"), sha256: sha256.digest("hex") };
}

function validateDigests(config, actual, expectedMd5) {
  if (actual.bytes === 0 || actual.bytes > config.maxBytes) {
    throw new Error(`Unexpected PBF size: ${actual.bytes}`);
  }
  if (actual.md5 !== expectedMd5) {
    throw new Error(
      `PBF MD5 mismatch: expected ${expectedMd5}, received ${actual.md5}`,
    );
  }
  if (config.pinnedSha256 && actual.sha256 !== config.pinnedSha256) {
    throw new Error(
      `PBF SHA-256 mismatch: expected ${config.pinnedSha256}, received ${actual.sha256}`,
    );
  }
}

async function verifyLocal(config, destination, metadataPath) {
  if (!existsSync(destination) || !existsSync(metadataPath)) {
    throw new Error(
      "Local PBF or checksum metadata is missing; download it first",
    );
  }
  const metadata = JSON.parse(readFileSync(metadataPath, "utf8"));
  if (
    metadata.schemaVersion !== 1 ||
    metadata.datasetId !== config.id ||
    metadata.checksumAlgorithm !== config.checksumAlgorithm ||
    !/^[a-f0-9]{32}$/u.test(metadata.checksums?.md5 ?? "") ||
    !/^[a-f0-9]{64}$/u.test(metadata.checksums?.sha256 ?? "")
  ) {
    throw new Error(
      "Local PBF metadata is invalid or belongs to another dataset",
    );
  }
  const actual = await hashFile(destination);
  validateDigests(config, actual, metadata.checksums.md5);
  if (actual.sha256 !== metadata.checksums.sha256) {
    throw new Error("Local PBF SHA-256 does not match its metadata sidecar");
  }
  process.stdout.write(
    `Verified ${relative(root, destination)} (${actual.bytes} bytes, sha256=${actual.sha256})\n`,
  );
  return actual;
}

async function download(config, destination, metadataPath) {
  const expectedBefore = await fetchChecksum(config);
  const response = await fetch(config.pbfUrl, {
    redirect: "follow",
    headers: {
      accept: "application/octet-stream",
      "user-agent": "seychas-map-pipeline/1.0",
    },
  });
  if (!response.ok || !response.body) {
    throw new Error(`Region download failed: HTTP ${response.status}`);
  }
  if (new URL(response.url).protocol !== "https:") {
    throw new Error("PBF redirect left HTTPS");
  }
  const declaredLength = Number(response.headers.get("content-length") ?? 0);
  if (declaredLength && declaredLength > config.maxBytes) {
    throw new Error(`Region exceeds configured ${config.maxBytes} byte limit`);
  }

  const partial = `${destination}.partial`;
  if (existsSync(partial)) unlinkSync(partial);
  const md5 = createHash("md5");
  const sha256 = createHash("sha256");
  let bytes = 0;
  let prefix = Buffer.alloc(0);
  const verifier = new Transform({
    transform(chunk, _encoding, callback) {
      const buffer = Buffer.from(chunk);
      bytes += buffer.length;
      if (bytes > config.maxBytes) {
        callback(new Error(`Region exceeds ${config.maxBytes} bytes`));
        return;
      }
      if (prefix.length < 64) {
        prefix = Buffer.concat([prefix, buffer]).subarray(0, 64);
      }
      md5.update(buffer);
      sha256.update(buffer);
      callback(null, buffer);
    },
  });

  try {
    await pipeline(
      Readable.fromWeb(response.body),
      verifier,
      createWriteStream(partial, { flags: "wx" }),
    );
    if (/^\s*</u.test(prefix.toString("utf8"))) {
      throw new Error("Downloaded content looks like HTML, not an OSM PBF");
    }
    const actual = {
      bytes,
      md5: md5.digest("hex"),
      sha256: sha256.digest("hex"),
    };
    const expectedAfter = await fetchChecksum(config);
    if (expectedAfter !== expectedBefore) {
      throw new Error("Remote checksum changed during download; retry later");
    }
    validateDigests(config, actual, expectedBefore);

    const metadata = {
      schemaVersion: 1,
      datasetId: config.id,
      datasetVersion: config.datasetVersion,
      sourceUrl: config.pbfUrl,
      resolvedSourceUrl: response.url,
      checksumUrl: config.checksumUrl,
      checksumAlgorithm: config.checksumAlgorithm,
      checksumFileName: config.checksumFileName,
      checksums: { md5: actual.md5, sha256: actual.sha256 },
      bytes: actual.bytes,
      etag: response.headers.get("etag"),
      lastModified: response.headers.get("last-modified"),
      verifiedAt: new Date().toISOString(),
    };
    const metadataPartial = `${metadataPath}.partial`;
    writeFileSync(metadataPartial, `${JSON.stringify(metadata, null, 2)}\n`, {
      flag: "w",
    });
    if (existsSync(destination)) unlinkSync(destination);
    renameSync(partial, destination);
    if (existsSync(metadataPath)) unlinkSync(metadataPath);
    renameSync(metadataPartial, metadataPath);
    process.stdout.write(
      `Downloaded and verified ${config.id}: ${actual.bytes} bytes -> ${relative(root, destination)}\nsha256=${actual.sha256}\n`,
    );
    if (!config.pinnedSha256) {
      process.stdout.write(
        "Release owners should copy this SHA-256 to pinnedSha256 before promoting the dataset.\n",
      );
    }
  } catch (error) {
    if (existsSync(partial)) unlinkSync(partial);
    throw error;
  }
}

const options = parseArgs(process.argv.slice(2));
const config = JSON.parse(readFileSync(options.config, "utf8"));
validateConfig(config);
const destination = pathInsideRoot(config.output, "output");
const metadataPath = pathInsideRoot(config.metadataOutput, "metadataOutput");
mkdirSync(dirname(destination), { recursive: true });
mkdirSync(dirname(metadataPath), { recursive: true });

if (options.verifyOnly) {
  await verifyLocal(config, destination, metadataPath);
} else if (existsSync(destination) && !options.force) {
  await verifyLocal(config, destination, metadataPath);
  process.stdout.write(
    "Use --force to fetch and verify the current upstream file.\n",
  );
} else {
  await download(config, destination, metadataPath);
}
