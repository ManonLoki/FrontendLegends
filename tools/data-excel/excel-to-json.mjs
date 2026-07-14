import XLSX from 'xlsx';
import { DATA_DIR, DEFAULT_WORKBOOK, HEADERS, SHEETS, jsonFromWorkbookRows, objectRowsFromMatrix, writeJsonData } from './data-workbook.mjs';

const args = new Map(process.argv.slice(2).map(arg => {
  const [key, value = ''] = arg.split('=');
  return [key, value];
}));
const input = args.get('--input') || DEFAULT_WORKBOOK;
const outDir = args.get('--out') || DATA_DIR;
const workbook = XLSX.readFile(input, { cellDates: false });
const sheetRows = {};

for (const sheetName of Object.values(SHEETS)) {
  if (sheetName === SHEETS.readme) continue;
  const sheet = workbook.Sheets[sheetName];
  if (!sheet) throw new Error(`缺少工作表：${sheetName}`);
  const matrix = XLSX.utils.sheet_to_json(sheet, { header: 1, defval: '' });
  const headers = matrix[0] ?? [];
  const expected = HEADERS[sheetName] ?? [];
  for (const header of expected) {
    if (!headers.includes(header)) throw new Error(`${sheetName} 缺少列：${header}`);
  }
  sheetRows[sheetName] = objectRowsFromMatrix(matrix);
}

const data = jsonFromWorkbookRows(sheetRows);
await writeJsonData(data, outDir);
console.log(`Wrote JSON files to ${outDir}`);

