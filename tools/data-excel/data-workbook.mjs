import fs from 'node:fs/promises';
import path from 'node:path';

export const DEFAULT_WORKBOOK = 'docs/data/FrontendLegendsData.xlsx';
export const DATA_DIR = 'assets/Data';

export const SHEETS = {
  meta: 'Meta',
  readme: 'README',
  items: 'Items',
  vendorStock: 'VendorStock',
  skills: 'Skills',
  teachStock: 'TeachStock',
  npcs: 'NPCs',
  npcSkillLevels: 'NPCSkillLevels',
  npcEquipment: 'NPCEquipment',
  npcLoot: 'NPCLoot',
  quests: 'Quests',
};

export const HEADERS = {
  [SHEETS.meta]: ['file', 'version', 'note'],
  [SHEETS.items]: [
    'itemId', 'name', 'kind', 'slot', 'price',
    'rarity', 'weight', 'stackLimit', 'unique', 'discardable', 'consumeOnUse',
    'tags', 'questId', 'source',
    'effectFood', 'effectWater', 'effectHp', 'effectInjury', 'effectAppearance', 'effectPotential',
    'bonusAttack', 'bonusDefense', 'bonusHit', 'bonusDodge', 'bonusCrit',
    'skillId', 'maxLearnLevel',
    'attrStrength', 'attrAgility', 'attrConstitution', 'attrWisdom',
    'reqStrength', 'reqAgility', 'reqConstitution', 'reqWisdom',
    'sellable', 'description',
  ],
  [SHEETS.vendorStock]: ['npcId', 'itemId', 'sort'],
  [SHEETS.skills]: [
    'skillId', 'name', 'category', 'sect', 'tier', 'theme', 'maxLevel',
    'costBase', 'costFactor', 'reqSect', 'reqStrength', 'reqAgility',
    'reqConstitution', 'reqWisdom', 'reqMinSkillPower', 'reqMinAvgSkill',
    'prereqSkillId', 'prereqLevel', 'atkPerLv', 'defPerLv', 'hitPerLv',
    'dodgePerLv', 'parryPerLv', 'injuryReducePerLv', 'mpMaxPerLv', 'mpCost',
    'description', 'configJson',
  ],
  [SHEETS.teachStock]: ['npcId', 'skillId', 'maxTeachLevel', 'sort'],
  [SHEETS.npcs]: [
    'npcId', 'displayName', 'gender', 'age', 'sprite', 'roles', 'sect', 'title',
    'description', 'defaultLine',
    'attrStrength', 'attrAgility', 'attrConstitution', 'attrWisdom',
    'joinStrength', 'joinAgility', 'joinConstitution', 'joinWisdom',
    'combatHpMax', 'combatHp', 'combatMpMax', 'combatMp', 'inventory',
  ],
  [SHEETS.npcSkillLevels]: ['npcId', 'skillId', 'level', 'equipped'],
  [SHEETS.npcEquipment]: ['npcId', 'itemId', 'sort'],
  [SHEETS.npcLoot]: ['npcId', 'itemId', 'chance', 'min', 'max', 'sort'],
  [SHEETS.quests]: ['bucket', 'questId', 'type', 'title', 'configJson'],
};

const DATA_FILES = ['items', 'skills', 'npcs', 'quests'];
const ATTR_KEYS = ['strength', 'agility', 'constitution', 'wisdom'];

function blankToUndefined(value) {
  if (value == null) return undefined;
  if (typeof value === 'string' && value.trim() === '') return undefined;
  return value;
}

function str(value) {
  const v = blankToUndefined(value);
  return v == null ? undefined : String(v).trim();
}

function num(value) {
  const v = blankToUndefined(value);
  if (v == null) return undefined;
  const n = Number(v);
  return Number.isFinite(n) ? n : undefined;
}

function bool(value) {
  const v = blankToUndefined(value);
  if (v == null) return undefined;
  if (typeof v === 'boolean') return v;
  const s = String(v).trim().toLowerCase();
  if (['true', '1', 'yes', 'y'].includes(s)) return true;
  if (['false', '0', 'no', 'n'].includes(s)) return false;
  return undefined;
}

function csv(value) {
  return String(value ?? '')
    .split(/[,，]/)
    .map(s => s.trim())
    .filter(Boolean);
}

function cleanObject(obj) {
  for (const key of Object.keys(obj)) {
    const value = obj[key];
    if (Array.isArray(value)) {
      if (value.length === 0) delete obj[key];
    } else if (value && typeof value === 'object') {
      cleanObject(value);
      if (Object.keys(value).length === 0) delete obj[key];
    } else if (value == null || value === '') {
      delete obj[key];
    }
  }
  return obj;
}

function stableJson(obj) {
  return JSON.stringify(obj ?? {}, null, 0);
}

function parseJsonCell(value, context) {
  const raw = str(value);
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch (error) {
    throw new Error(`${context} 不是合法 JSON：${error.message}`);
  }
}

function attrsFromRow(row, prefix = 'attr') {
  const out = {};
  const map = {
    strength: `${prefix}Strength`,
    agility: `${prefix}Agility`,
    constitution: `${prefix}Constitution`,
    wisdom: `${prefix}Wisdom`,
  };
  for (const key of ATTR_KEYS) {
    const value = num(row[map[key]]);
    if (value != null) out[key] = value;
  }
  return cleanObject(out);
}

function attrsToRow(obj, prefix = 'attr') {
  return {
    [`${prefix}Strength`]: obj?.strength ?? '',
    [`${prefix}Agility`]: obj?.agility ?? '',
    [`${prefix}Constitution`]: obj?.constitution ?? '',
    [`${prefix}Wisdom`]: obj?.wisdom ?? '',
  };
}

export async function readJsonData(rootDir = '.') {
  const out = {};
  for (const name of DATA_FILES) {
    const file = path.join(rootDir, DATA_DIR, `${name}.json`);
    out[name] = JSON.parse(await fs.readFile(file, 'utf8'));
  }
  return out;
}

export function workbookRowsFromJson(data) {
  const rows = {};
  rows[SHEETS.meta] = DATA_FILES.map(file => ({
    file: `${file}.json`,
    version: data[file]?.version ?? 1,
    note: data[file]?._note ?? '',
  }));

  rows[SHEETS.items] = Object.entries(data.items.items ?? {}).map(([itemId, def]) => ({
    itemId,
    name: def.name ?? '',
    kind: def.kind ?? '',
    slot: def.slot ?? '',
    price: def.price ?? '',
    rarity: def.rarity ?? '',
    weight: def.weight ?? '',
    stackLimit: def.stackLimit ?? '',
    unique: def.unique == null ? '' : def.unique,
    discardable: def.discardable == null ? '' : def.discardable,
    consumeOnUse: def.consumeOnUse == null ? '' : def.consumeOnUse,
    tags: (def.tags ?? []).join(','),
    questId: def.questId ?? '',
    source: def.source ?? '',
    effectFood: def.effects?.food ?? '',
    effectWater: def.effects?.water ?? '',
    effectHp: def.effects?.hp ?? '',
    effectInjury: def.effects?.injury ?? '',
    effectAppearance: def.effects?.appearance ?? '',
    effectPotential: def.effects?.potential ?? '',
    bonusAttack: def.equipmentBonus?.attack ?? '',
    bonusDefense: def.equipmentBonus?.defense ?? '',
    bonusHit: def.equipmentBonus?.hit ?? '',
    bonusDodge: def.equipmentBonus?.dodge ?? '',
    bonusCrit: def.equipmentBonus?.crit ?? '',
    skillId: def.skillId ?? '',
    maxLearnLevel: def.maxLearnLevel ?? '',
    ...attrsToRow(def.attributes, 'attr'),
    ...attrsToRow(def.requires, 'req'),
    sellable: def.sellable == null ? '' : def.sellable,
    description: def.description ?? '',
  }));

  rows[SHEETS.vendorStock] = [];
  for (const [npcId, itemIds] of Object.entries(data.items.vendorStock ?? {})) {
    itemIds.forEach((itemId, index) => rows[SHEETS.vendorStock].push({ npcId, itemId, sort: index + 1 }));
  }

  rows[SHEETS.skills] = Object.entries(data.skills.skills ?? {}).map(([skillId, def]) => {
    // 列未覆盖的复杂字段（moves 被动招式 / ult 门派绝招等）整体走 configJson 透传，防丢失
    const {
      name, category, sect, tier, theme, maxLevel, costBase, costFactor,
      requires, combat, description, ...rest
    } = def;
    return {
      skillId,
      name: name ?? '',
      category: category ?? '',
      sect: sect ?? '',
      tier: tier ?? '',
      theme: theme ?? '',
      maxLevel: maxLevel ?? '',
      costBase: costBase ?? '',
      costFactor: costFactor ?? '',
      reqSect: requires?.sect ?? '',
      reqStrength: requires?.attrs?.strength ?? '',
      reqAgility: requires?.attrs?.agility ?? '',
      reqConstitution: requires?.attrs?.constitution ?? '',
      reqWisdom: requires?.attrs?.wisdom ?? '',
      reqMinSkillPower: requires?.minSkillPower ?? '',
      reqMinAvgSkill: requires?.minAvgSkill ?? '',
      prereqSkillId: requires?.prereq?.skillId ?? '',
      prereqLevel: requires?.prereq?.level ?? '',
      atkPerLv: combat?.atkPerLv ?? '',
      defPerLv: combat?.defPerLv ?? '',
      hitPerLv: combat?.hitPerLv ?? '',
      dodgePerLv: combat?.dodgePerLv ?? '',
      parryPerLv: combat?.parryPerLv ?? '',
      injuryReducePerLv: combat?.injuryReducePerLv ?? '',
      mpMaxPerLv: combat?.mpMaxPerLv ?? '',
      mpCost: combat?.mpCost ?? '',
      description: description ?? '',
      configJson: Object.keys(rest).length > 0 ? stableJson(rest) : '',
    };
  });

  rows[SHEETS.teachStock] = [];
  for (const [npcId, entries] of Object.entries(data.skills.teachStock ?? {})) {
    entries.forEach((entry, index) => {
      rows[SHEETS.teachStock].push({
        npcId,
        skillId: typeof entry === 'string' ? entry : entry.skillId,
        maxTeachLevel: typeof entry === 'string' ? '' : entry.maxTeachLevel ?? '',
        sort: index + 1,
      });
    });
  }

  rows[SHEETS.npcs] = [];
  rows[SHEETS.npcSkillLevels] = [];
  rows[SHEETS.npcEquipment] = [];
  rows[SHEETS.npcLoot] = [];
  for (const [npcId, def] of Object.entries(data.npcs.npcs ?? {})) {
    rows[SHEETS.npcs].push({
      npcId,
      displayName: def.displayName ?? '',
      gender: def.gender ?? '',
      age: def.age ?? '',
      sprite: def.sprite ?? '',
      roles: (def.roles ?? []).join(','),
      sect: def.sect ?? '',
      title: def.title ?? '',
      description: def.description ?? '',
      defaultLine: def.defaultLine ?? '',
      ...attrsToRow(def.attributes, 'attr'),
      ...attrsToRow(def.joinSect, 'join'),
      combatHpMax: def.combat?.hpMax ?? '',
      combatHp: def.combat?.hp ?? '',
      combatMpMax: def.combat?.mpMax ?? '',
      combatMp: def.combat?.mp ?? '',
      inventory: (def.inventory ?? []).join(','),
    });
    const skillLevels = { ...(def.skillLevels ?? {}) };
    const equipped = new Set(def.equippedSkillIds ?? []);
    for (const [skillId, level] of Object.entries(skillLevels)) {
      rows[SHEETS.npcSkillLevels].push({ npcId, skillId, level, equipped: equipped.has(skillId) });
    }
    (def.equipment ?? []).forEach((itemId, index) => rows[SHEETS.npcEquipment].push({ npcId, itemId, sort: index + 1 }));
    (def.loot ?? []).forEach((loot, index) => rows[SHEETS.npcLoot].push({
      npcId,
      itemId: loot.itemId,
      chance: loot.chance,
      min: loot.min ?? '',
      max: loot.max ?? '',
      sort: index + 1,
    }));
  }

  rows[SHEETS.quests] = [];
  for (const [bucket, collection] of [['quests', data.quests.quests ?? {}], ['generators', data.quests.generators ?? {}]]) {
    for (const [questId, def] of Object.entries(collection)) {
      const { type, title, ...rest } = def;
      rows[SHEETS.quests].push({ bucket, questId, type, title: title ?? '', configJson: stableJson(rest) });
    }
  }

  return rows;
}

export function matrixFromRows(sheetName, rows) {
  const headers = HEADERS[sheetName];
  return [headers, ...rows.map(row => headers.map(header => row[header] ?? ''))];
}

export function objectRowsFromMatrix(matrix) {
  const [headers = [], ...body] = matrix;
  return body
    .filter(row => row.some(value => blankToUndefined(value) != null))
    .map(row => Object.fromEntries(headers.map((header, index) => [header, row[index] ?? ''])));
}

export function jsonFromWorkbookRows(sheetRows) {
  const meta = Object.fromEntries((sheetRows[SHEETS.meta] ?? []).map(row => [str(row.file), row]));
  const result = {
    items: { version: num(meta['items.json']?.version) ?? 1, items: {}, vendorStock: {} },
    skills: { version: num(meta['skills.json']?.version) ?? 1, skills: {}, teachStock: {} },
    npcs: { version: num(meta['npcs.json']?.version) ?? 1, npcs: {} },
    quests: { version: num(meta['quests.json']?.version) ?? 1, quests: {}, generators: {} },
  };
  for (const [key, target] of Object.entries(result)) {
    const note = str(meta[`${key}.json`]?.note);
    if (note) target._note = note;
  }

  for (const row of sheetRows[SHEETS.items] ?? []) {
    const itemId = str(row.itemId);
    if (!itemId) continue;
    const def = cleanObject({
      name: str(row.name) ?? itemId,
      kind: str(row.kind),
      slot: str(row.slot),
      rarity: str(row.rarity),
      weight: num(row.weight),
      stackLimit: num(row.stackLimit),
      unique: bool(row.unique),
      discardable: bool(row.discardable),
      consumeOnUse: bool(row.consumeOnUse),
      tags: csv(row.tags),
      questId: str(row.questId),
      source: str(row.source),
      effects: cleanObject({
        food: num(row.effectFood),
        water: num(row.effectWater),
        hp: num(row.effectHp),
        injury: num(row.effectInjury),
        appearance: num(row.effectAppearance),
        potential: num(row.effectPotential),
      }),
      attributes: attrsFromRow(row, 'attr'),
      equipmentBonus: cleanObject({
        attack: num(row.bonusAttack),
        defense: num(row.bonusDefense),
        hit: num(row.bonusHit),
        dodge: num(row.bonusDodge),
        crit: num(row.bonusCrit),
      }),
      skillId: str(row.skillId),
      maxLearnLevel: num(row.maxLearnLevel),
      requires: attrsFromRow(row, 'req'),
      price: num(row.price) ?? 0,
      sellable: bool(row.sellable),
      description: str(row.description),
    });
    result.items.items[itemId] = def;
  }
  for (const row of [...(sheetRows[SHEETS.vendorStock] ?? [])].sort((a, b) => (num(a.sort) ?? 0) - (num(b.sort) ?? 0))) {
    const npcId = str(row.npcId);
    const itemId = str(row.itemId);
    if (!npcId || !itemId) continue;
    if (!result.items.vendorStock[npcId]) result.items.vendorStock[npcId] = [];
    result.items.vendorStock[npcId].push(itemId);
  }

  for (const row of sheetRows[SHEETS.skills] ?? []) {
    const skillId = str(row.skillId);
    if (!skillId) continue;
    const attrs = cleanObject({
      strength: num(row.reqStrength),
      agility: num(row.reqAgility),
      constitution: num(row.reqConstitution),
      wisdom: num(row.reqWisdom),
    });
    const prereq = cleanObject({ skillId: str(row.prereqSkillId), level: num(row.prereqLevel) });
    const requires = cleanObject({
      sect: str(row.reqSect) ?? str(row.sect),
      attrs,
      minSkillPower: num(row.reqMinSkillPower),
      minAvgSkill: num(row.reqMinAvgSkill),
      prereq,
    });
    const combat = cleanObject({
      atkPerLv: num(row.atkPerLv),
      defPerLv: num(row.defPerLv),
      hitPerLv: num(row.hitPerLv),
      dodgePerLv: num(row.dodgePerLv),
      parryPerLv: num(row.parryPerLv),
      injuryReducePerLv: num(row.injuryReducePerLv),
      mpMaxPerLv: num(row.mpMaxPerLv),
      mpCost: num(row.mpCost),
    });
    // configJson 透传字段（moves / ult 等）插回 description 之前，保持 skills.json 键序稳定
    const extra = parseJsonCell(row.configJson, `Skills.${skillId}.configJson`);
    result.skills.skills[skillId] = cleanObject({
      name: str(row.name) ?? skillId,
      category: str(row.category),
      sect: str(row.sect),
      tier: str(row.tier),
      theme: str(row.theme),
      maxLevel: num(row.maxLevel) ?? 0,
      costBase: num(row.costBase) ?? 0,
      costFactor: num(row.costFactor) ?? 1,
      requires,
      combat,
      ...extra,
      description: str(row.description),
    });
  }
  for (const row of [...(sheetRows[SHEETS.teachStock] ?? [])].sort((a, b) => (num(a.sort) ?? 0) - (num(b.sort) ?? 0))) {
    const npcId = str(row.npcId);
    const skillId = str(row.skillId);
    if (!npcId || !skillId) continue;
    if (!result.skills.teachStock[npcId]) result.skills.teachStock[npcId] = [];
    const maxTeachLevel = num(row.maxTeachLevel);
    result.skills.teachStock[npcId].push(maxTeachLevel == null ? skillId : { skillId, maxTeachLevel });
  }

  for (const row of sheetRows[SHEETS.npcs] ?? []) {
    const npcId = str(row.npcId);
    if (!npcId) continue;
    const def = cleanObject({
      displayName: str(row.displayName) ?? npcId,
      gender: str(row.gender),
      age: num(row.age),
      sprite: str(row.sprite) ?? 'npc-1',
      roles: csv(row.roles),
      sect: str(row.sect),
      title: str(row.title),
      description: str(row.description),
      defaultLine: str(row.defaultLine),
      attributes: attrsFromRow(row, 'attr'),
      joinSect: attrsFromRow(row, 'join'),
      combat: cleanObject({
        hpMax: num(row.combatHpMax),
        hp: num(row.combatHp),
        mpMax: num(row.combatMpMax),
        mp: num(row.combatMp),
      }),
      inventory: csv(row.inventory),
    });
    if (!def.roles || def.roles.length === 0) def.roles = ['civilian'];
    result.npcs.npcs[npcId] = def;
  }
  for (const row of sheetRows[SHEETS.npcSkillLevels] ?? []) {
    const npcId = str(row.npcId);
    const skillId = str(row.skillId);
    if (!npcId || !skillId || !result.npcs.npcs[npcId]) continue;
    const def = result.npcs.npcs[npcId];
    if (!def.skillLevels) def.skillLevels = {};
    def.skillLevels[skillId] = num(row.level) ?? 0;
    if (bool(row.equipped)) {
      if (!def.equippedSkillIds) def.equippedSkillIds = [];
      def.equippedSkillIds.push(skillId);
    }
  }
  for (const row of [...(sheetRows[SHEETS.npcEquipment] ?? [])].sort((a, b) => (num(a.sort) ?? 0) - (num(b.sort) ?? 0))) {
    const npcId = str(row.npcId);
    const itemId = str(row.itemId);
    if (!npcId || !itemId || !result.npcs.npcs[npcId]) continue;
    const def = result.npcs.npcs[npcId];
    if (!def.equipment) def.equipment = [];
    def.equipment.push(itemId);
  }
  for (const row of [...(sheetRows[SHEETS.npcLoot] ?? [])].sort((a, b) => (num(a.sort) ?? 0) - (num(b.sort) ?? 0))) {
    const npcId = str(row.npcId);
    const itemId = str(row.itemId);
    if (!npcId || !itemId || !result.npcs.npcs[npcId]) continue;
    const def = result.npcs.npcs[npcId];
    if (!def.loot) def.loot = [];
    def.loot.push(cleanObject({ itemId, chance: num(row.chance) ?? 0, min: num(row.min), max: num(row.max) }));
  }

  for (const row of sheetRows[SHEETS.quests] ?? []) {
    const bucket = str(row.bucket);
    const questId = str(row.questId);
    if (!bucket || !questId) continue;
    const config = parseJsonCell(row.configJson, `Quests.${questId}.configJson`);
    const def = cleanObject({ type: str(row.type), title: str(row.title), ...config });
    if (bucket === 'generators') result.quests.generators[questId] = def;
    else result.quests.quests[questId] = def;
  }

  return result;
}

export async function writeJsonData(data, outDir = DATA_DIR) {
  await fs.mkdir(outDir, { recursive: true });
  for (const name of DATA_FILES) {
    await fs.writeFile(path.join(outDir, `${name}.json`), `${JSON.stringify(data[name], null, 2)}\n`, 'utf8');
  }
}
