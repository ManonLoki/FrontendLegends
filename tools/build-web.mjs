import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";
import { hashWebBuild } from "./hash-web-build.mjs";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outputFile = resolve(projectRoot, process.argv[2] ?? "dist/web/index.html");
const macGodot = "/Applications/Godot.app/Contents/MacOS/Godot";
const godot = process.env.GODOT_BIN || (existsSync(macGodot) ? macGodot : "godot");

const exportResult = spawnSync(
  godot,
  ["--headless", "--path", projectRoot, "--export-release", "Web", outputFile],
  { cwd: projectRoot, stdio: "inherit" },
);
if (exportResult.error) throw exportResult.error;
if (exportResult.status !== 0) process.exit(exportResult.status ?? 1);

const result = await hashWebBuild(dirname(outputFile));
console.log(`Web build ready: ${result.directory}`);
console.log(`Asset version: ${result.hash}`);
