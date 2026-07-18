import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { hashWebBuild } from "./hash-web-build.mjs";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outputFile = resolve(projectRoot, process.argv[2] ?? "dist/web/index.html");

// godot-safe.sh 是 Godot 命令行唯一入口，负责选择二进制并把日志固定到可写目录。
const exportResult = spawnSync(
  resolve(projectRoot, "tools/godot-safe.sh"),
  ["--headless", "--export-release", "Web", outputFile],
  { cwd: projectRoot, stdio: "inherit" },
);
if (exportResult.error) throw exportResult.error;
if (exportResult.status !== 0) process.exit(exportResult.status ?? 1);

const result = await hashWebBuild(dirname(outputFile));
console.log(`Web build ready: ${result.directory}`);
console.log(`Asset version: ${result.hash}`);
