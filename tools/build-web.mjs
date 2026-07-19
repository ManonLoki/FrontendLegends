import { spawnSync } from "node:child_process";
import { mkdir, rm } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { hashWebBuild } from "./hash-web-build.mjs";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outputFile = resolve(projectRoot, process.argv[2] ?? "dist/web/index.html");
const outputDirectory = dirname(outputFile);
const packsDirectory = resolve(outputDirectory, "packs");
const godotSafe = resolve(projectRoot, "tools/godot-safe.sh");

await rm(packsDirectory, { recursive: true, force: true });
await mkdir(packsDirectory, { recursive: true });

// godot-safe.sh 是 Godot 命令行唯一入口，负责选择二进制并把日志固定到可写目录。
const exportResult = spawnSync(
  godotSafe,
  ["--headless", "--export-release", "Web Split", outputFile],
  { cwd: projectRoot, stdio: "inherit" },
);
if (exportResult.error) throw exportResult.error;
if (exportResult.status !== 0) process.exit(exportResult.status ?? 1);

const packsResult = spawnSync(
  godotSafe,
  ["--headless", "--script", "res://tools/build_audio_packs.gd", "--", packsDirectory],
  { cwd: projectRoot, stdio: "inherit" },
);
if (packsResult.error) throw packsResult.error;
if (packsResult.status !== 0) process.exit(packsResult.status ?? 1);

const mapPacksResult = spawnSync(
  godotSafe,
  ["--headless", "--script", "res://tools/build_map_packs.gd", "--", packsDirectory],
  { cwd: projectRoot, stdio: "inherit" },
);
if (mapPacksResult.error) throw mapPacksResult.error;
if (mapPacksResult.status !== 0) process.exit(mapPacksResult.status ?? 1);

const result = await hashWebBuild(outputDirectory);
console.log(`Web build ready: ${result.directory}`);
console.log(`Asset version: ${result.hash}`);
console.log(`Content pack manifest: ${result.packManifest}`);
console.log(`Lazy content packs: ${result.packs.length}`);
