import fs from 'node:fs/promises';
import path from 'node:path';
import {
  BALANCE_RULE_ROWS,
  DATA_DIR,
  DATA_FILES,
  DEFAULT_WORKBOOK,
  HEADERS,
  SHEETS,
} from './workbook-schema.mjs';
import {
  attrsFromRow,
  attrsToRow,
  blankToUndefined,
  bool,
  cleanObject,
  csv,
  num,
  parseJsonCell,
  stableJson,
  str,
} from './workbook-values.mjs';

export { DATA_DIR, DEFAULT_WORKBOOK, HEADERS, SHEETS };

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
  rows[SHEETS.balanceRules] = BALANCE_RULE_ROWS.map(row => ({ ...row }));
  const topLevelCollections = {
    items: ['items', 'vendorStock'],
    skills: ['skills', 'teachStock'],
    npcs: ['npcs'],
    quests: ['quests', 'generators'],
  };
  rows[SHEETS.meta] = DATA_FILES.map(file => {
    const document = data[file] ?? {};
    const extra = { ...document };
    delete extra.version;
    delete extra._note;
    for (const key of topLevelCollections[file]) delete extra[key];
    return {
      file: `${file}.json`,
      version: document.version ?? 1,
      note: document._note ?? '',
      configJson: Object.keys(extra).length > 0 ? stableJson(extra) : '',
    };
  });

  rows[SHEETS.items] = Object.entries(data.items.items ?? {}).map(([itemId, def]) => {
    const {
      name, kind, slot, price, rarity, weight, stackLimit, unique, discardable,
      consumeOnUse, tags, questId, source, effects, equipmentBonus, skillId,
      maxLearnLevel, attributes, requires, sellable, description, ...rest
    } = def;
    return {
      itemId,
      name: name ?? '',
      kind: kind ?? '',
      slot: slot ?? '',
      price: price ?? '',
      rarity: rarity ?? '',
      weight: weight ?? '',
      stackLimit: stackLimit ?? '',
      unique: unique == null ? '' : unique,
      discardable: discardable == null ? '' : discardable,
      consumeOnUse: consumeOnUse == null ? '' : consumeOnUse,
      tags: (tags ?? []).join(','),
      questId: questId ?? '',
      source: source ?? '',
      effectFood: effects?.food ?? '',
      effectWater: effects?.water ?? '',
      effectHp: effects?.hp ?? '',
      effectInjury: effects?.injury ?? '',
      effectAppearance: effects?.appearance ?? '',
      effectPotential: effects?.potential ?? '',
      bonusAttack: equipmentBonus?.attack ?? '',
      bonusDefense: equipmentBonus?.defense ?? '',
      bonusHit: equipmentBonus?.hit ?? '',
      bonusDodge: equipmentBonus?.dodge ?? '',
      bonusCrit: equipmentBonus?.crit ?? '',
      bonusParry: equipmentBonus?.parry ?? '',
      bonusWoundInflict: equipmentBonus?.woundInflict ?? '',
      skillId: skillId ?? '',
      maxLearnLevel: maxLearnLevel ?? '',
      ...attrsToRow(attributes, 'attr'),
      ...attrsToRow(requires, 'req'),
      sellable: sellable == null ? '' : sellable,
      description: description ?? '',
      configJson: Object.keys(rest).length > 0 ? stableJson(rest) : '',
    };
  });

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
    const {
      displayName, gender, age, sprite, roles, sect, title, money,
      combatRank, combatRole, targetableByKillQuest, description, defaultLine,
      attributes, joinSect, combat, combatReward, inventory,
      skillLevels, equippedSkillIds, equipment, loot, ...rest
    } = def;
    rows[SHEETS.npcs].push({
      npcId,
      displayName: displayName ?? '',
      gender: gender ?? '',
      age: age ?? '',
      sprite: sprite ?? '',
      roles: (roles ?? []).join(','),
      sect: sect ?? '',
      title: title ?? '',
      money: money ?? '',
      combatRank: combatRank ?? '',
      combatRole: combatRole ?? '',
      targetableByKillQuest: targetableByKillQuest == null ? '' : targetableByKillQuest,
      description: description ?? '',
      defaultLine: defaultLine ?? '',
      ...attrsToRow(attributes, 'attr'),
      ...attrsToRow(joinSect, 'join'),
      combatHpMax: combat?.hpMax ?? '',
      combatHp: combat?.hp ?? '',
      combatMpMax: combat?.mpMax ?? '',
      combatMp: combat?.mp ?? '',
      rewardExperience: combatReward?.experience ?? '',
      rewardPotential: combatReward?.potential ?? '',
      rewardMoney: combatReward?.money ?? '',
      inventory: (inventory ?? []).join(','),
      configJson: Object.keys(rest).length > 0 ? stableJson(rest) : '',
    });
    const levels = { ...(skillLevels ?? {}) };
    const equippedOrder = new Map((equippedSkillIds ?? []).map((skillId, index) => [skillId, index + 1]));
    let levelIndex = 0;
    for (const [skillId, level] of Object.entries(levels)) {
      levelIndex += 1;
      rows[SHEETS.npcSkillLevels].push({
        npcId,
        skillId,
        level,
        equipped: equippedOrder.has(skillId),
        sort: equippedOrder.get(skillId) ?? 1000 + levelIndex,
      });
    }
    (equipment ?? []).forEach((itemId, index) => rows[SHEETS.npcEquipment].push({ npcId, itemId, sort: index + 1 }));
    (loot ?? []).forEach((entry, index) => rows[SHEETS.npcLoot].push({
      npcId,
      itemId: entry.itemId,
      chance: entry.chance,
      min: entry.min ?? '',
      max: entry.max ?? '',
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
    Object.assign(target, parseJsonCell(meta[`${key}.json`]?.configJson, `Meta.${key}.configJson`));
  }

  for (const row of sheetRows[SHEETS.items] ?? []) {
    const itemId = str(row.itemId);
    if (!itemId) continue;
    const extra = parseJsonCell(row.configJson, `Items.${itemId}.configJson`);
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
        parry: num(row.bonusParry),
        woundInflict: num(row.bonusWoundInflict),
      }),
      skillId: str(row.skillId),
      maxLearnLevel: num(row.maxLearnLevel),
      requires: attrsFromRow(row, 'req'),
      price: num(row.price) ?? 0,
      sellable: bool(row.sellable),
      ...extra,
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
    const extra = parseJsonCell(row.configJson, `NPCs.${npcId}.configJson`);
    const def = cleanObject({
      displayName: str(row.displayName) ?? npcId,
      gender: str(row.gender),
      age: num(row.age),
      sprite: str(row.sprite) ?? 'npc-1',
      roles: csv(row.roles),
      sect: str(row.sect),
      title: str(row.title),
      money: num(row.money),
      combatRank: str(row.combatRank),
      combatRole: str(row.combatRole),
      targetableByKillQuest: bool(row.targetableByKillQuest),
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
      combatReward: cleanObject({
        experience: num(row.rewardExperience),
        potential: num(row.rewardPotential),
        money: num(row.rewardMoney),
      }),
      inventory: csv(row.inventory),
      ...extra,
    });
    if (!def.roles || def.roles.length === 0) def.roles = ['civilian'];
    result.npcs.npcs[npcId] = def;
  }
  for (const row of [...(sheetRows[SHEETS.npcSkillLevels] ?? [])].sort((a, b) => (num(a.sort) ?? 0) - (num(b.sort) ?? 0))) {
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
