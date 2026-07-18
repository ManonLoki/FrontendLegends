import fs from 'node:fs';
import path from 'node:path';
import XLSX from 'xlsx';
import {
  DEFAULT_WORKBOOK_DIR,
  HEADERS,
  SHEETS,
  WORKBOOKS,
} from './workbook-schema.mjs';
import { matrixFromRows, readJsonData, workbookRowsFromJson } from './data-workbook.mjs';

const args = new Map(process.argv.slice(2).map(arg => {
  const [key, value = ''] = arg.split('=');
  return [key, value];
}));
const outputDir = args.get('--out') || DEFAULT_WORKBOOK_DIR;
const requested = args.get('--file');
const selected = requested ? [requested] : Object.keys(WORKBOOKS);
for (const key of selected) {
  if (!WORKBOOKS[key]) throw new Error(`未知数据工作簿：${key}`);
}

const descriptions = {
  [SHEETS.meta]: '对应运行时 JSON 的版本、说明和未展开顶层配置',
  [SHEETS.balanceRules]: '数值目标、运行时公式与约束',
  [SHEETS.items]: '道具主表',
  [SHEETS.vendorStock]: '商店库存：npcId → itemId',
  [SHEETS.skills]: '技能主表；moves/ult 等复杂字段在 configJson',
  [SHEETS.teachStock]: '师父授艺：npcId → skillId',
  [SHEETS.npcs]: 'NPC 主表',
  [SHEETS.npcSkillLevels]: 'NPC 技能等级：npcId + skillId',
  [SHEETS.npcEquipment]: 'NPC 装备：npcId + itemId',
  [SHEETS.npcLoot]: 'NPC 掉落：npcId + itemId',
  [SHEETS.quests]: '固定任务与任务生成器；复杂字段在 configJson',
  [SHEETS.worldEventTypes]: '世界事件原型：统一行为与默认参数',
  [SHEETS.worldEvents]: '世界事件摆放：地图、格子范围与实例文案',
  [SHEETS.maps]: '地图 UUID、TMX 路径、类型和父区域',
};

function addMatrixSheet(workbook, sheetName, matrix) {
  const sheet = XLSX.utils.aoa_to_sheet(matrix);
  sheet['!freeze'] = { xSplit: 0, ySplit: 1 };
  if (HEADERS[sheetName]) {
    sheet['!autofilter'] = {
      ref: XLSX.utils.encode_range({
        s: { r: 0, c: 0 },
        e: { r: Math.max(0, matrix.length - 1), c: HEADERS[sheetName].length - 1 },
      }),
    };
    sheet['!cols'] = HEADERS[sheetName].map(header => ({
      wch: /description|defaultLine|configJson|path|formula|notes|prompt|text/i.test(header) ? 36 : 18,
    }));
  }
  XLSX.utils.book_append_sheet(workbook, sheet, sheetName);
}

fs.mkdirSync(outputDir, { recursive: true });
const data = await readJsonData('.');
const rows = workbookRowsFromJson(data);
for (const key of selected) {
  const definition = WORKBOOKS[key];
  const workbook = XLSX.utils.book_new();
  const maintenanceNotes = definition.dataFile ? [
    [`仅导出本领域 JSON：npm run data:json -- --file=${key}`],
    [`从当前 JSON 重建本工作簿：npm run data:excel -- --file=${key}`],
    ['configJson 用于无损透传未展开的复杂字段，必须保持为合法 JSON。'],
  ] : [
    ['本工作簿是设计规则参考，不导出运行时 JSON。'],
    [`从代码中的规则清单重建：npm run data:excel -- --file=${key}`],
    ['运行时实现仍以 Godot 场景与 GDScript 为唯一事实来源。'],
  ];
  const readme = [
    [`FrontendLegends · ${definition.title}`],
    [definition.dataFile
      ? '本工作簿可独立维护和导出；ID 是跨工作簿引用的稳定主键，请勿填写显示名。'
      : '本工作簿独立记录平衡规则；运行时实现仍以 Godot 场景与 GDScript 为准。'],
    ...maintenanceNotes,
    [],
    ['Sheet', '用途'],
    ...(definition.dataFile ? [[SHEETS.meta, descriptions[SHEETS.meta]]] : []),
    ...definition.sheets.map(sheetName => [sheetName, descriptions[sheetName] ?? '维护数据']),
  ];
  addMatrixSheet(workbook, SHEETS.readme, readme);
  if (definition.dataFile) {
    const metaRows = (rows[SHEETS.meta] ?? []).filter(row => row.file === `${definition.dataFile}.json`);
    addMatrixSheet(workbook, SHEETS.meta, matrixFromRows(SHEETS.meta, metaRows));
  }
  for (const sheetName of definition.sheets) {
    addMatrixSheet(workbook, sheetName, matrixFromRows(sheetName, rows[sheetName] ?? []));
  }
  const output = path.join(outputDir, definition.file);
  XLSX.writeFile(workbook, output);
  console.log(`Wrote ${output}`);
}
