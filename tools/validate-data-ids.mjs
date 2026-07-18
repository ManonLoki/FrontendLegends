import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const dataDir = path.join(root, 'assets/Data');
const expectedVersion = 5;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const failures = [];

function readData(name) {
  const document = JSON.parse(fs.readFileSync(path.join(dataDir, `${name}.json`), 'utf8'));
  if (document.version !== expectedVersion) failures.push(`${name}.json version must be ${expectedVersion}`);
  return document;
}

function requireKnown(id, known, label) {
  if (id && !known.has(id)) failures.push(`${label}: unknown ID ${id}`);
}

function listFiles(directory, suffix) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? listFiles(file, suffix) : entry.name.endsWith(suffix) ? [file] : [];
  });
}

const itemsDocument = readData('items');
const npcsDocument = readData('npcs');
const skillsDocument = readData('skills');
const questsDocument = readData('quests');
const eventsDocument = readData('world_events');
const mapsDocument = readData('maps');
const groups = {
  item: Object.keys(itemsDocument.items ?? {}),
  npc: Object.keys(npcsDocument.npcs ?? {}),
  skill: Object.keys(skillsDocument.skills ?? {}),
  quest: Object.keys(questsDocument.quests ?? {}),
  quest_generator: Object.keys(questsDocument.generators ?? {}),
  quest_variant: Object.values(questsDocument.quests ?? {}).flatMap(quest => (quest.variants ?? []).map(variant => variant.id)),
  world_event_type: Object.keys(eventsDocument.archetypes ?? {}),
  world_event: (eventsDocument.placements ?? []).map(placement => placement.id),
  map: Object.keys(mapsDocument.maps ?? {}),
};
const globalOwner = new Map();
for (const [kind, ids] of Object.entries(groups)) {
  for (const id of ids) {
    if (!uuidPattern.test(id)) failures.push(`${kind}: non-UUID primary key ${id}`);
    if (globalOwner.has(id)) failures.push(`${kind}: duplicate global ID ${id} already used by ${globalOwner.get(id)}`);
    globalOwner.set(id, kind);
  }
}
const knownItems = new Set(groups.item);
const knownNpcs = new Set(groups.npc);
const knownSkills = new Set(groups.skill);
const knownQuests = new Set([...groups.quest, ...groups.quest_generator]);
const knownEvents = new Set(groups.world_event);
const knownEventTypes = new Set(groups.world_event_type);
const knownMaps = new Set(groups.map);

for (const [npcId, itemIds] of Object.entries(itemsDocument.vendorStock ?? {})) {
  requireKnown(npcId, knownNpcs, 'vendorStock npcId');
  for (const itemId of itemIds) requireKnown(itemId, knownItems, `vendorStock ${npcId}`);
}
for (const [itemId, definition] of Object.entries(itemsDocument.items ?? {})) {
  requireKnown(definition.dropNpcId, knownNpcs, `item ${itemId} dropNpcId`);
  requireKnown(definition.skillId, knownSkills, `item ${itemId} skillId`);
  requireKnown(definition.questId, knownQuests, `item ${itemId} questId`);
}
for (const [npcId, definition] of Object.entries(npcsDocument.npcs ?? {})) {
  for (const skillId of Object.keys(definition.skillLevels ?? {})) requireKnown(skillId, knownSkills, `npc ${npcId} skillLevels`);
  for (const skillId of definition.equippedSkillIds ?? []) requireKnown(skillId, knownSkills, `npc ${npcId} equippedSkillIds`);
  for (const itemId of definition.inventory ?? []) requireKnown(itemId, knownItems, `npc ${npcId} inventory`);
  for (const itemId of definition.equipment ?? []) requireKnown(itemId, knownItems, `npc ${npcId} equipment`);
  for (const drop of definition.loot ?? []) requireKnown(drop.itemId, knownItems, `npc ${npcId} loot`);
}
for (const [npcId, entries] of Object.entries(skillsDocument.teachStock ?? {})) {
  requireKnown(npcId, knownNpcs, 'teachStock npcId');
  for (const entry of entries) requireKnown(typeof entry === 'string' ? entry : entry.skillId, knownSkills, `teachStock ${npcId}`);
}
for (const [questId, definition] of Object.entries(questsDocument.quests ?? {})) {
  requireKnown(definition.giverNpcId, new Set([...knownNpcs, ...knownEvents]), `quest ${questId} giverNpcId`);
  requireKnown(definition.completionGiverId, new Set([...knownNpcs, ...knownEvents]), `quest ${questId} completionGiverId`);
}
for (const [generatorId, definition] of Object.entries(questsDocument.generators ?? {})) {
  requireKnown(definition.giverNpcId, new Set([...knownNpcs, ...knownEvents]), `generator ${generatorId} giverNpcId`);
  for (const itemId of definition.items ?? []) requireKnown(itemId, knownItems, `generator ${generatorId} items`);
  for (const mapId of definition.spawnMaps ?? []) requireKnown(mapId, knownMaps, `generator ${generatorId} spawnMaps`);
}
for (const placement of eventsDocument.placements ?? []) {
  requireKnown(placement.map, knownMaps, `world event ${placement.id} map`);
  requireKnown(placement.archetype, knownEventTypes, `world event ${placement.id} archetype`);
  requireKnown(placement.data?.questEndpoint, new Set([...knownEvents, ...knownQuests]), `world event ${placement.id} questEndpoint`);
}

const registeredPaths = new Set();
for (const [mapId, definition] of Object.entries(mapsDocument.maps ?? {})) {
  requireKnown(definition.parentMapId, knownMaps, `map ${mapId} parentMapId`);
  const relativePath = String(definition.path ?? '').replace(/^res:\/\//, '');
  const absolutePath = path.join(root, relativePath);
  if (!fs.existsSync(absolutePath)) {
    failures.push(`map ${mapId}: missing TMX ${definition.path}`);
    continue;
  }
  registeredPaths.add(path.resolve(absolutePath));
  const xml = fs.readFileSync(absolutePath, 'utf8');
  const declaredMapId = xml.match(/<property\s+name="mapId"\s+value="([^"]+)"/)?.[1];
  if (declaredMapId !== mapId) failures.push(`map ${mapId}: TMX declares ${declaredMapId ?? 'no mapId'}`);
  for (const [, propertyName, reference] of xml.matchAll(/<property\b[^>]*\bname="(from|to|parentMap|npcId)"[^>]*\bvalue="([^"]+)"/g)) {
    requireKnown(reference, propertyName === 'npcId' ? knownNpcs : knownMaps, `${definition.path} ${propertyName}`);
  }
}
for (const tmxPath of listFiles(path.join(root, 'assets/Map/maps'), '.tmx')) {
  if (!registeredPaths.has(path.resolve(tmxPath))) failures.push(`unregistered TMX ${path.relative(root, tmxPath)}`);
}

if (failures.length) {
  for (const failure of failures) console.error(failure);
  process.exit(1);
}
console.log(`Validated ${globalOwner.size} globally unique UUID primary keys across six v${expectedVersion} data documents.`);
