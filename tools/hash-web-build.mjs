import { createHash } from "node:crypto";
import { readdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HASH_LENGTH = 12;
const HASHED_INDEX_RE = new RegExp(`^index\\.[0-9a-f]{${HASH_LENGTH}}\\.`);
const TEXT_FILE_RE = /\.(?:html|js|json|webmanifest)$/;

export async function hashWebBuild(outputDirectory) {
  const directory = resolve(outputDirectory);
  const initialNames = await readdir(directory);

  // Godot 不会清理上一次导出的文件；先移除旧 hash 和误导出的导入元数据。
  await Promise.all(initialNames.map(async (name) => {
    if (HASHED_INDEX_RE.test(name) || name.endsWith(".import")) {
      await rm(resolve(directory, name), { force: true });
    }
  }));

  const names = await readdir(directory);
  const assets = names.filter((name) => name.startsWith("index.") && name !== "index.html").sort();
  if (!assets.includes("index.js") || !assets.includes("index.wasm") || !assets.includes("index.pck")) {
    throw new Error(`Web build is incomplete in ${directory}`);
  }

  const digest = createHash("sha256");
  for (const name of assets) {
    digest.update(name);
    digest.update(await readFile(resolve(directory, name)));
  }
  const hash = digest.digest("hex").slice(0, HASH_LENGTH);
  const executable = `index.${hash}`;
  const replacements = new Map(assets.map((name) => [name, `${executable}${name.slice("index".length)}`]));

  for (const [oldName, newName] of replacements) {
    await rename(resolve(directory, oldName), resolve(directory, newName));
  }

  const finalNames = await readdir(directory);
  for (const name of finalNames.filter((candidate) => TEXT_FILE_RE.test(candidate))) {
    const path = resolve(directory, name);
    let content = await readFile(path, "utf8");
    for (const [oldName, newName] of replacements) {
      content = content.split(oldName).join(newName);
    }
    content = content.replace(/("executable"\s*:\s*)"index"/g, `$1"${executable}"`);
    await writeFile(path, content);
  }

  return { directory, executable, files: [...replacements.values()].sort(), hash };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const result = await hashWebBuild(process.argv[2] ?? "dist/web");
  console.log(`Hashed Web build: ${result.executable}`);
}
