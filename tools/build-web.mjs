import { existsSync } from "node:fs";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";
import { hashWebBuild } from "./hash-web-build.mjs";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outputFile = resolve(projectRoot, process.argv[2] ?? "dist/web/index.html");
const exportPresets = resolve(projectRoot, "export_presets.cfg");
const macGodot = "/Applications/Godot.app/Contents/MacOS/Godot";
const godot = process.env.GODOT_BIN || (existsSync(macGodot) ? macGodot : "godot");

// 移动 Chrome 证明 Project 策略仍会采用启动时的竖屏尺寸。构建期间强制 None，
// 让 HTML 的 480×320 Canvas 属性成为内部尺寸的唯一事实来源。
const originalPresets = await readFile(exportPresets, "utf8");
const fixedCanvasPresets = originalPresets.replace(
  /html\/canvas_resize_policy=\d+/,
  "html/canvas_resize_policy=0",
);
let exportResult;
try {
  await writeFile(exportPresets, fixedCanvasPresets);
  exportResult = spawnSync(
    godot,
    ["--headless", "--path", projectRoot, "--export-release", "Web", outputFile],
    { cwd: projectRoot, stdio: "inherit" },
  );
} finally {
  await writeFile(exportPresets, originalPresets);
}
if (exportResult.error) throw exportResult.error;
if (exportResult.status !== 0) process.exit(exportResult.status ?? 1);

const result = await hashWebBuild(dirname(outputFile));
console.log(`Web build ready: ${result.directory}`);
console.log(`Asset version: ${result.hash}`);
