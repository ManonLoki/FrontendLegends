import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outputPath = path.resolve(process.argv[2] ?? '');
const project = fs.readFileSync(path.join(root, 'project.godot'), 'utf8');
const version = project.match(/^config\/version="([^"]+)"$/m)?.[1] ?? '';
const html = fs.readFileSync(outputPath, 'utf8');
const expected = `<div id="loading-version">v${version}</div>`;

if (!version || !html.includes(expected) || html.includes('__FRONTEND_LEGENDS_VERSION__')) {
  console.error(`ERROR: Web export loading version is not synchronized to ${version || '(missing)'}`);
  process.exit(1);
}
console.log(`Web export version: PASS (v${version})`);
