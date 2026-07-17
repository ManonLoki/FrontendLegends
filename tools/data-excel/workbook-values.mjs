const ATTR_KEYS = ['strength', 'agility', 'constitution', 'wisdom'];

export function blankToUndefined(value) {
  if (value == null) return undefined;
  if (typeof value === 'string' && value.trim() === '') return undefined;
  return value;
}

export function str(value) {
  const normalized = blankToUndefined(value);
  return normalized == null ? undefined : String(normalized).trim();
}

export function num(value) {
  const normalized = blankToUndefined(value);
  if (normalized == null) return undefined;
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : undefined;
}

export function bool(value) {
  const normalized = blankToUndefined(value);
  if (normalized == null) return undefined;
  if (typeof normalized === 'boolean') return normalized;
  const text = String(normalized).trim().toLowerCase();
  if (['true', '1', 'yes', 'y'].includes(text)) return true;
  if (['false', '0', 'no', 'n'].includes(text)) return false;
  return undefined;
}

export function csv(value) {
  return String(value ?? '')
    .split(/[,，]/)
    .map(text => text.trim())
    .filter(Boolean);
}

export function cleanObject(object) {
  for (const key of Object.keys(object)) {
    const value = object[key];
    if (Array.isArray(value)) {
      if (value.length === 0) delete object[key];
    } else if (value && typeof value === 'object') {
      cleanObject(value);
      if (Object.keys(value).length === 0) delete object[key];
    } else if (value == null || value === '') {
      delete object[key];
    }
  }
  return object;
}

export function stableJson(object) {
  return JSON.stringify(object ?? {}, null, 0);
}

export function parseJsonCell(value, context) {
  const raw = str(value);
  if (!raw) return {};
  try {
    return JSON.parse(raw);
  } catch (error) {
    throw new Error(`${context} 不是合法 JSON：${error.message}`);
  }
}

export function attrsFromRow(row, prefix = 'attr') {
  const result = {};
  const columns = {
    strength: `${prefix}Strength`,
    agility: `${prefix}Agility`,
    constitution: `${prefix}Constitution`,
    wisdom: `${prefix}Wisdom`,
  };
  for (const key of ATTR_KEYS) {
    const value = num(row[columns[key]]);
    if (value != null) result[key] = value;
  }
  return cleanObject(result);
}

export function attrsToRow(object, prefix = 'attr') {
  return {
    [`${prefix}Strength`]: object?.strength ?? '',
    [`${prefix}Agility`]: object?.agility ?? '',
    [`${prefix}Constitution`]: object?.constitution ?? '',
    [`${prefix}Wisdom`]: object?.wisdom ?? '',
  };
}
