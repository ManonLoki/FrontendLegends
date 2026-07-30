import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const project = fs.readFileSync(path.join(root, 'project.godot'), 'utf8');
const presetsSource = fs.readFileSync(path.join(root, 'export_presets.cfg'), 'utf8');
const webShell = fs.readFileSync(path.join(root, 'web/index_shell.html'), 'utf8');
const version = project.match(/^config\/version="([^"]+)"$/m)?.[1] ?? '';
const failures = [];

if (!/^\d+\.\d+\.\d+$/.test(version)) failures.push(`project.godot version is not semver: ${version || '(empty)'}`);
const [versionMajor, versionMinor, versionPatch] = version.split('.').map(Number);
const androidVersionCode = versionMajor * 10000 + versionMinor * 100 + versionPatch;
const baseSections = [...presetsSource.matchAll(/\[preset\.(\d+)\]\n([\s\S]*?)(?=\n\[preset\.\1\.options\])/g)];
const optionSections = new Map([...presetsSource.matchAll(/\[preset\.(\d+)\.options\]\n([\s\S]*?)(?=\n\[preset\.\d+\]|$)/g)].map(match => [match[1], match[2]]));
const expectedPlatforms = new Set(['macOS', 'Windows Desktop', 'Android', 'Web', 'iOS']);
const requiredExcludes = ['addons/web_version_sync/*', 'dist/*', 'node_modules/*', 'tests/*', 'tools/*', 'docs/*'];

if (!project.includes('enabled=PackedStringArray("res://addons/web_version_sync/plugin.cfg")')) failures.push('Web version sync export plugin is not enabled');
if (!webShell.includes('<div id="loading-version">v__FRONTEND_LEGENDS_VERSION__</div>')) failures.push('Web loading page must use the project version token');

for (const [, index, body] of baseSections) {
  const platform = body.match(/^platform="([^"]+)"$/m)?.[1] ?? '';
  expectedPlatforms.delete(platform);
  const include = body.match(/^include_filter="([^"]*)"$/m)?.[1] ?? '';
  const exclude = body.match(/^exclude_filter="([^"]*)"$/m)?.[1] ?? '';
  for (const extension of ['*.ogg', '*.tmx', '*.tsx', '*.tpsheet']) {
    if (!include.includes(extension)) failures.push(`${platform}: include_filter misses ${extension}`);
  }
  for (const entry of requiredExcludes) {
    if (!exclude.includes(entry)) failures.push(`${platform}: exclude_filter misses ${entry}`);
  }
  const options = optionSections.get(index) ?? '';
  if (platform === 'macOS' || platform === 'iOS') {
    if (!options.includes(`application/short_version="${version}"`)) failures.push(`${platform}: short version differs from ${version}`);
    if (!options.includes('application/version="1"')) failures.push(`${platform}: build version must be 1`);
  } else if (platform === 'Windows Desktop') {
    if (!options.includes(`application/product_version="${version}.0"`)) failures.push(`Windows Desktop: product version differs from ${version}.0`);
    if (!options.includes(`application/file_version="${version}.0"`)) failures.push(`Windows Desktop: file version differs from ${version}.0`);
  } else if (platform === 'Android') {
    if (!options.includes(`version/name="${version}"`)) failures.push(`Android: version name differs from ${version}`);
    if (!options.includes(`version/code=${androidVersionCode}`)) failures.push(`Android: version code differs from ${androidVersionCode}`);
  }
}

if (baseSections.length !== 5) failures.push(`expected 5 export presets, found ${baseSections.length}`);
for (const platform of expectedPlatforms) failures.push(`missing export preset: ${platform}`);
for (const resource of [...presetsSource.matchAll(/"res:\/\/([^"\n]+)"/g)].map(match => match[1])) {
  if (!fs.existsSync(path.join(root, resource))) failures.push(`export resource does not exist: res://${resource}`);
}

if (failures.length) {
  failures.forEach(failure => console.error(`ERROR: ${failure}`));
  process.exit(1);
}
console.log(`Release contract: PASS (${baseSections.length} presets, version ${version})`);
