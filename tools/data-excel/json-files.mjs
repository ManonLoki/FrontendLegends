import fs from 'node:fs/promises';
import path from 'node:path';
import { DATA_DIR, DATA_FILES } from './workbook-schema.mjs';

export async function readJsonData(rootDir = '.', fileNames = DATA_FILES) {
  const out = {};
  for (const name of fileNames) {
    const file = path.join(rootDir, DATA_DIR, `${name}.json`);
    out[name] = JSON.parse(await fs.readFile(file, 'utf8'));
  }
  return out;
}

export async function writeJsonData(data, outDir = DATA_DIR, fileNames = DATA_FILES) {
  await fs.mkdir(outDir, { recursive: true });
  for (const name of fileNames) {
    await fs.writeFile(path.join(outDir, `${name}.json`), `${JSON.stringify(data[name], null, 2)}\n`, 'utf8');
  }
}
