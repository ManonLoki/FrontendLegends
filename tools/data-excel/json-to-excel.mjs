import XLSX from 'xlsx';
import { DEFAULT_WORKBOOK, HEADERS, SHEETS, matrixFromRows, readJsonData, workbookRowsFromJson } from './data-workbook.mjs';

const args = new Map(process.argv.slice(2).map(arg => {
  const [key, value = ''] = arg.split('=');
  return [key, value];
}));
const output = args.get('--out') || DEFAULT_WORKBOOK;
const data = await readJsonData('.');
const rows = workbookRowsFromJson(data);
const workbook = XLSX.utils.book_new();

const readme = [
  ['FrontendLegends 数据维护工作簿'],
  ['编辑建议：优先维护 ID 字段；多对多关系放在独立关系表。'],
  ['导出 JSON：npm run data:json'],
  ['从当前 JSON 重建 Excel：npm run data:excel'],
  ['注意：Meta、Items、Skills、NPCs、Quests 的 configJson 会透传未展开字段，必须保持为合法 JSON。平衡公式详见 docs/balance_design.md。'],
  [],
  ['Sheet', '用途'],
  [SHEETS.items, 'items.json 道具主表'],
  [SHEETS.balanceRules, 'v4 数值目标、运行时公式与约束'],
  [SHEETS.vendorStock, '商店库存：npcId → itemId'],
  [SHEETS.skills, 'skills.json 技能主表；moves/ult 等复杂字段在 configJson'],
  [SHEETS.teachStock, '师父授艺：npcId → skillId'],
  [SHEETS.npcs, 'npcs.json NPC 主表'],
  [SHEETS.npcSkillLevels, 'NPC 技能等级：npcId + skillId'],
  [SHEETS.npcEquipment, 'NPC 装备：npcId + itemId'],
  [SHEETS.npcLoot, 'NPC 掉落：npcId + itemId'],
  [SHEETS.quests, '任务/生成器；复杂字段在 configJson'],
];
XLSX.utils.book_append_sheet(workbook, XLSX.utils.aoa_to_sheet(readme), SHEETS.readme);

for (const sheetName of [SHEETS.meta, SHEETS.balanceRules, SHEETS.items, SHEETS.vendorStock, SHEETS.skills, SHEETS.teachStock, SHEETS.npcs, SHEETS.npcSkillLevels, SHEETS.npcEquipment, SHEETS.npcLoot, SHEETS.quests]) {
  const matrix = matrixFromRows(sheetName, rows[sheetName] ?? []);
  const sheet = XLSX.utils.aoa_to_sheet(matrix);
  sheet['!freeze'] = { xSplit: 0, ySplit: 1 };
  sheet['!autofilter'] = { ref: XLSX.utils.encode_range({ s: { r: 0, c: 0 }, e: { r: Math.max(0, matrix.length - 1), c: HEADERS[sheetName].length - 1 } }) };
  sheet['!cols'] = HEADERS[sheetName].map(header => ({ wch: Math.min(48, Math.max(12, header.length + 4)) }));
  XLSX.utils.book_append_sheet(workbook, sheet, sheetName);
}

XLSX.writeFile(workbook, output);
console.log(`Wrote ${output}`);
