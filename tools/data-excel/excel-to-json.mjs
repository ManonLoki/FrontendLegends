import path from 'node:path';
import XLSX from 'xlsx';
import {
  DATA_DIR,
  DEFAULT_WORKBOOK_DIR,
  HEADERS,
  SHEETS,
  WORKBOOKS,
} from './workbook-schema.mjs';
import { jsonFromWorkbookRows, objectRowsFromMatrix, writeJsonData } from './data-workbook.mjs';

const args = new Map(process.argv.slice(2).map(arg => {
  const [key, value = ''] = arg.split('=');
  return [key, value];
}));
const inputDir = args.get('--input') || DEFAULT_WORKBOOK_DIR;
const outDir = args.get('--out') || DATA_DIR;
const requested = args.get('--file');
const selected = requested
  ? [requested]
  : Object.keys(WORKBOOKS).filter(key => WORKBOOKS[key].dataFile);
for (const key of selected) {
  if (!WORKBOOKS[key]?.dataFile) throw new Error(`未知 JSON 数据工作簿：${key}`);
}

function readSheet(workbook, sheetName, source) {
  const sheet = workbook.Sheets[sheetName];
  if (!sheet) throw new Error(`${source} 缺少工作表：${sheetName}`);
  const matrix = XLSX.utils.sheet_to_json(sheet, { header: 1, defval: '' });
  const headers = matrix[0] ?? [];
  for (const header of HEADERS[sheetName] ?? []) {
    if (!headers.includes(header)) throw new Error(`${source} / ${sheetName} 缺少列：${header}`);
  }
  return objectRowsFromMatrix(matrix);
}

const sheetRows = { [SHEETS.meta]: [] };
for (const key of selected) {
  const definition = WORKBOOKS[key];
  const input = path.join(inputDir, definition.file);
  const workbook = XLSX.readFile(input, { cellDates: false });
  sheetRows[SHEETS.meta].push(...readSheet(workbook, SHEETS.meta, input));
  for (const sheetName of definition.sheets) {
    sheetRows[sheetName] = readSheet(workbook, sheetName, input);
  }
}

const data = jsonFromWorkbookRows(sheetRows);
const fileNames = selected.map(key => WORKBOOKS[key].dataFile);
await writeJsonData(data, outDir, fileNames);
console.log(`Wrote ${fileNames.join(', ')} JSON to ${outDir}`);
