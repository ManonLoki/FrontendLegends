import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, rm, stat } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";
import { tmpdir } from "node:os";
import { hashWebBuild } from "./hash-web-build.mjs";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outputFile = resolve(projectRoot, process.argv[2] ?? "dist/web/index.html");
const outputDirectory = dirname(outputFile);
const packsDirectory = resolve(outputDirectory, "packs");
const godotSafe = resolve(projectRoot, "tools/godot-safe.sh");

const relativeOutputDirectory = relative(projectRoot, outputDirectory);
if (
  !relativeOutputDirectory
  || isAbsolute(relativeOutputDirectory)
  || relativeOutputDirectory === ".."
  || relativeOutputDirectory.startsWith(`..${sep}`)
) {
  throw new Error(`Web output directory must stay inside the project: ${outputDirectory}`);
}

// 每次从空发布目录开始，避免中断导出的裸 index.* 与旧哈希文件混入部署。
await rm(outputDirectory, { recursive: true, force: true });
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
await verifySplitExport(result);
console.log(`Web build ready: ${result.directory}`);
console.log(`Asset version: ${result.hash}`);
console.log(`Content pack manifest: ${result.packManifest}`);
console.log(`Main PCK: ${formatMib(await fileSize(result.files, ".pck"))}`);
console.log(`Engine WASM: ${formatMib(await fileSize(result.files, ".wasm"))}`);
const lazyPackBytes = (await Promise.all(result.packs.map((name) => stat(resolve(packsDirectory, name))))).reduce(
  (total, info) => total + info.size,
  0,
);
console.log(`Lazy content packs: ${result.packs.length}, ${formatMib(lazyPackBytes)} total`);

async function verifySplitExport(build) {
  const mainPack = resolve(outputDirectory, build.files.find((name) => name.endsWith(".pck")));
  const testDirectory = await mkdtemp(resolve(tmpdir(), "frontend-legends-web-export-"));
  const checks = [
    resolve(projectRoot, "tests/audio/split_audio_export_test.gd"),
    resolve(projectRoot, "tests/maps/split_map_export_test.gd"),
  ];
  try {
    for (const script of checks) {
      const check = spawnSync(
        godotSafe,
        ["--path", testDirectory, "--headless", "--main-pack", mainPack, "--script", script, "--", packsDirectory],
        { cwd: projectRoot, stdio: "inherit" },
      );
      if (check.error) throw check.error;
      if (check.status !== 0) process.exit(check.status ?? 1);
    }
  } finally {
    await rm(testDirectory, { recursive: true, force: true });
  }
}

async function fileSize(files, extension) {
  const name = files.find((candidate) => candidate.endsWith(extension));
  if (!name) throw new Error(`Web build is missing ${extension}`);
  return (await stat(resolve(outputDirectory, name))).size;
}

function formatMib(bytes) {
  return `${(bytes / 1024 / 1024).toFixed(1)} MiB`;
}
