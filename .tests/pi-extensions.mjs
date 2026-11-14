#!/usr/bin/env node
// Checks the pi extensions in pi/.pi/agent/extensions against the installed pi release.
//
//   node .tests/pi-extensions.mjs            run every *.test.ts
//   node .tests/pi-extensions.mjs focus      only files whose path contains "focus"
//   node .tests/pi-extensions.mjs --staged   only extension directories with staged changes (the pre-commit hook)
//   node .tests/pi-extensions.mjs --types    type-check instead of running tests (needs `tsc` on PATH)
//
// Tests run under `node --test`. They import pi's packages the way a loaded extension does: through
// pi's bundled jiti, with the installed release aliased in. The alias map follows getAliases() in pi's
// dist/core/extensions/loader.js; when an extension imports a pi package missing here, add it.
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");
const extensionsPath = "pi/.pi/agent/extensions";
const extensions = join(repo, extensionsPath);
const install = join(homedir(), ".pi/agent/install");

const args = process.argv.slice(2);
const staged = args.includes("--staged");
const types = args.includes("--types");
const filters = args.filter((arg) => !arg.startsWith("--"));

// A machine without pi has nothing to load the extensions into; the pre-commit hook must not block there.
if (!existsSync(join(install, "current-version"))) {
  console.log(`pi-extensions: skipped, no pi install at ${install}`);
  process.exit(0);
}

const modules = join(install, "releases", readFileSync(join(install, "current-version"), "utf8").trim(), "node_modules");
const pi = join(modules, "@earendil-works");
const alias = {
  "@earendil-works/pi-coding-agent": join(pi, "pi-coding-agent/dist/index.js"),
  "@earendil-works/pi-agent-core": join(pi, "pi-agent-core/dist/index.js"),
  "@earendil-works/pi-tui": join(pi, "pi-tui/dist/index.js"),
  "@earendil-works/pi-ai": join(pi, "pi-coding-agent/dist/core/extensions/pi-ai-extension-view.js"),
};
const jiti = join(modules, "jiti/lib/jiti-register.mjs");
const missing = [jiti, ...Object.values(alias)].filter((path) => !existsSync(path));
if (missing.length > 0) {
  console.error(`pi-extensions: this pi release moved files the extensions import:\n  ${missing.join("\n  ")}`);
  process.exit(1);
}

/** Extension directories with staged changes, as path prefixes such as "focus/". */
function stagedDirectories() {
  const diff = spawnSync("git", ["-C", repo, "diff", "--cached", "--name-only", "--diff-filter=ACMR", "--", extensionsPath], { encoding: "utf8" });
  const names = diff.stdout.split("\n").map((path) => path.slice(extensionsPath.length + 1).split("/")).filter((parts) => parts.length > 1);
  return [...new Set(names.map(([directory]) => `${directory}/`))];
}

const directories = staged ? stagedDirectories() : [];
const selected = (path) =>
  (!staged || directories.some((directory) => path.startsWith(directory))) &&
  (filters.length === 0 || filters.some((filter) => path.includes(filter)));
const sources = readdirSync(extensions, { recursive: true })
  .filter((path) => path.endsWith(".ts") && !path.includes("node_modules") && selected(path))
  .sort();
const files = sources.filter((path) => types || path.endsWith(".test.ts")).map((path) => join(extensions, path));

if (files.length === 0) {
  if (staged) process.exit(0); // nothing staged here that has tests
  console.error(`pi-extensions: no ${types ? "TypeScript" : "test"} files match ${filters.join(" ") || "anything"} in ${extensions}`);
  process.exit(1);
}

function typeCheck() {
  const config = mkdtempSync(join(tmpdir(), "pi-extensions-types-"));
  const declarations = Object.entries(alias).map(([name, path]) => [name, [path.replace(/\.js$/, ".d.ts")]]);
  writeFileSync(join(config, "tsconfig.json"), JSON.stringify({
    compilerOptions: {
      noEmit: true, strict: true, target: "es2023", lib: ["es2023"], module: "esnext", moduleResolution: "bundler",
      allowImportingTsExtensions: true, skipLibCheck: true, types: ["node"], typeRoots: [join(modules, "@types")],
      paths: Object.fromEntries(declarations),
    },
    files,
  }));
  try {
    return spawnSync("tsc", ["-p", config, "--pretty"], { stdio: "inherit", timeout: 300_000 });
  } finally {
    rmSync(config, { recursive: true, force: true });
  }
}

function test() {
  // DEP0205: jiti registers its loader with module.register(), which newer Node versions deprecate.
  const flags = ["--disable-warning=DEP0205", "--import", jiti, "--test", "--test-timeout=30000"];
  return spawnSync(process.execPath, [...flags, ...files], {
    stdio: "inherit",
    env: { ...process.env, JITI_ALIAS: JSON.stringify(alias) },
    timeout: 120_000,
  });
}

const run = types ? typeCheck() : test();
if (run.error) console.error(`pi-extensions: ${run.error.message}`);
process.exit(run.status ?? 1);
