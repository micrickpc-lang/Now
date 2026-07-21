import { readdirSync, readFileSync, statSync } from "node:fs";
import { extname, relative, resolve } from "node:path";

const root = resolve(import.meta.dirname, "../..");
const ignored = new Set([
  "node_modules",
  ".git",
  ".dart_tool",
  "build",
  ".next",
  "dist",
]);
const extensions = new Set([
  ".ts",
  ".tsx",
  ".dart",
  ".json",
  ".yaml",
  ".yml",
  ".env",
  ".md",
  ".conf",
  ".xml",
  ".kt",
  ".swift",
]);
const patterns = [
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/u,
  /AKIA[0-9A-Z]{16}/u,
  /ghp_[A-Za-z0-9]{30,}/u,
  /sk-(?:live|prod)-[A-Za-z0-9_-]{20,}/u,
];
const findings = [];
function walk(directory) {
  for (const entry of readdirSync(directory)) {
    if (ignored.has(entry) || entry.endsWith(".lock")) continue;
    const path = resolve(directory, entry);
    const stats = statSync(path);
    if (stats.isDirectory()) walk(path);
    else if (extensions.has(extname(path)) || entry === ".env.example") {
      const content = readFileSync(path, "utf8");
      if (patterns.some((pattern) => pattern.test(content)))
        findings.push(relative(root, path));
    }
  }
}
walk(root);
if (findings.length) {
  process.stderr.write(`Possible production secrets: ${findings.join(", ")}\n`);
  process.exit(1);
}
process.stdout.write(
  "No private keys or known production token formats found\n",
);
