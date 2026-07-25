import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, relative, resolve, sep } from "node:path";
import { deflateSync } from "node:zlib";

const root = resolve(import.meta.dirname, "../..");
const defaultOutput = resolve(root, "infra/maps/assets/v1");

function usage() {
  process.stdout.write(`Usage: node scripts/maps/generate-assets.mjs [options]

Generate deterministic versioned sprite and minimal glyph endpoint assets used
by the label-free v1 staging style.

Options:
  --output <path>  Output directory (default: infra/maps/assets/v1)
  --check          Verify generated files without changing them
  --help           Show this help
`);
}

function parseArgs(argv) {
  const options = { output: defaultOutput, check: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--help" || argument === "-h") {
      usage();
      process.exit(0);
    } else if (argument === "--check") {
      options.check = true;
    } else if (argument === "--output") {
      if (!argv[index + 1]) throw new Error("--output requires a path");
      options.output = resolve(argv[index + 1]);
      index += 1;
    } else {
      throw new Error(`Unknown option: ${argument}`);
    }
  }
  if (options.output !== root && !options.output.startsWith(`${root}${sep}`)) {
    throw new Error("--output must stay inside the repository");
  }
  return options;
}

const crcTable = Array.from({ length: 256 }, (_, index) => {
  let value = index;
  for (let bit = 0; bit < 8; bit += 1) {
    value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
  }
  return value >>> 0;
});

function crc32(buffer) {
  let value = 0xffffffff;
  for (const byte of buffer) {
    value = crcTable[(value ^ byte) & 0xff] ^ (value >>> 8);
  }
  return (value ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const name = Buffer.from(type, "ascii");
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(Buffer.concat([name, data])));
  return Buffer.concat([length, name, data, checksum]);
}

function transparentPng(width, height) {
  const signature = Buffer.from("89504e470d0a1a0a", "hex");
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  const scanlines = Buffer.alloc(height * (1 + width * 4));
  return Buffer.concat([
    signature,
    pngChunk("IHDR", header),
    pngChunk("IDAT", deflateSync(scanlines, { level: 9 })),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

function varint(input) {
  const bytes = [];
  let value = input;
  do {
    let byte = value & 0x7f;
    value >>>= 7;
    if (value) byte |= 0x80;
    bytes.push(byte);
  } while (value);
  return Buffer.from(bytes);
}

function protobufString(field, value) {
  const payload = Buffer.from(value, "utf8");
  return Buffer.concat([
    varint((field << 3) | 2),
    varint(payload.length),
    payload,
  ]);
}

function minimalGlyphPbf(fontstack, range) {
  const stack = Buffer.concat([
    protobufString(1, fontstack),
    protobufString(2, range),
  ]);
  return Buffer.concat([varint((1 << 3) | 2), varint(stack.length), stack]);
}

const options = parseArgs(process.argv.slice(2));
const files = new Map([
  ["sprites/sprite.json", Buffer.from("{}\n")],
  ["sprites/sprite.png", transparentPng(1, 1)],
  ["sprites/sprite@2x.json", Buffer.from("{}\n")],
  ["sprites/sprite@2x.png", transparentPng(2, 2)],
  [
    "glyphs/Noto Sans Regular/0-255.pbf",
    minimalGlyphPbf("Noto Sans Regular", "0-255"),
  ],
]);

const manifest = {
  schemaVersion: 1,
  styleVersion: "v1",
  note: "Deterministic empty sprite and minimal glyph envelope for the label-free staging style",
  files: Object.fromEntries(
    [...files].map(([path, content]) => [
      path,
      {
        bytes: content.length,
        sha256: createHash("sha256").update(content).digest("hex"),
      },
    ]),
  ),
};
files.set(
  "manifest.json",
  Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`),
);

const differences = [];
for (const [path, expected] of files) {
  const destination = resolve(options.output, path);
  if (options.check) {
    if (!existsSync(destination)) {
      differences.push(`${path}: missing`);
    } else if (!readFileSync(destination).equals(expected)) {
      differences.push(`${path}: content differs`);
    }
  } else {
    mkdirSync(dirname(destination), { recursive: true });
    writeFileSync(destination, expected);
  }
}

if (differences.length) {
  throw new Error(`Generated map assets are stale:\n${differences.join("\n")}`);
}
process.stdout.write(
  options.check
    ? `Verified generated assets in ${relative(root, options.output)}\n`
    : `Generated versioned assets in ${relative(root, options.output)}\n`,
);
