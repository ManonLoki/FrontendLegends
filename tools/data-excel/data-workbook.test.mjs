import { isDeepStrictEqual } from 'node:util';
import {
  jsonFromWorkbookRows,
  readJsonData,
  workbookRowsFromJson,
} from './data-workbook.mjs';
import { SHEETS } from './workbook-schema.mjs';

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

console.log('data-workbook.test: PASS (5 JSON files, 6 event types, 21 event placements)');
