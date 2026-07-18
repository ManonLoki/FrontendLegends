import { isDeepStrictEqual } from 'node:util';
import path from 'node:path';
import XLSX from 'xlsx';
import {
  jsonFromWorkbookRows,
  objectRowsFromMatrix,
  readJsonData,
  workbookRowsFromJson,
} from './data-workbook.mjs';
import { DEFAULT_WORKBOOK_DIR, HEADERS, SHEETS, WORKBOOKS } from './workbook-schema.mjs';

const current = await readJsonData('.');
const rows = workbookRowsFromJson(current);
const generated = jsonFromWorkbookRows(rows);

for (const name of Object.keys(current)) {
  if (!isDeepStrictEqual(current[name], generated[name])) {
    throw new Error(`${name}.json 未通过 Excel 行模型往返校验`);
  }
}

if ((rows[SHEETS.worldEventTypes] ?? []).length !== 6) {
  throw new Error('WorldEventTypes 应包含 6 个事件原型');
}
if ((rows[SHEETS.worldEvents] ?? []).length !== 21) {
  throw new Error('WorldEvents 应包含 21 个事件摆放');
}

if ((rows[SHEETS.maps] ?? []).length !== 25) {
  throw new Error('Maps 应包含 25 个地图索引');
}

const excelRows = { [SHEETS.meta]: [] };
for (const definition of Object.values(WORKBOOKS).filter(entry => entry.dataFile)) {
  const file = path.join(DEFAULT_WORKBOOK_DIR, definition.file);
  const workbook = XLSX.readFile(file, { cellDates: false });
  for (const sheetName of [SHEETS.meta, ...definition.sheets]) {
    const sheet = workbook.Sheets[sheetName];
    if (!sheet) throw new Error(`${file} 缺少工作表 ${sheetName}`);
    const matrix = XLSX.utils.sheet_to_json(sheet, { header: 1, defval: '' });
    const actualHeaders = matrix[0] ?? [];
    for (const header of HEADERS[sheetName]) {
      if (!actualHeaders.includes(header)) throw new Error(`${file} / ${sheetName} 缺少列 ${header}`);
    }
    const sheetData = objectRowsFromMatrix(matrix);
    if (sheetName === SHEETS.meta) excelRows[SHEETS.meta].push(...sheetData);
    else excelRows[sheetName] = sheetData;
  }
}
const excelGenerated = jsonFromWorkbookRows(excelRows);
for (const name of Object.keys(current)) {
  if (!isDeepStrictEqual(current[name], excelGenerated[name])) {
    throw new Error(`${name}.json 未通过独立 Excel 文件往返校验`);
  }
}

console.log('data-workbook.test: PASS (6 JSON files, 6 event types, 21 event placements, 25 maps)');
