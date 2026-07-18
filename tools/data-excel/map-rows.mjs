import { cleanObject, parseJsonCell, stableJson, str } from './workbook-values.mjs';

export function mapsRowsFromJson(document = {}) {
  return Object.entries(document.maps ?? {}).map(([mapId, definition]) => {
    const { path, displayName, mapType, parentMapId, ...rest } = definition;
    return {
      mapId,
      path: path ?? '',
      displayName: displayName ?? '',
      mapType: mapType ?? '',
      parentMapId: parentMapId ?? '',
      configJson: Object.keys(rest).length > 0 ? stableJson(rest) : '',
    };
  });
}

export function mapsFromRows(rows = []) {
  const maps = {};
  for (const row of rows) {
    const mapId = str(row.mapId);
    if (!mapId) continue;
    maps[mapId] = cleanObject({
      path: str(row.path),
      displayName: str(row.displayName),
      mapType: str(row.mapType),
      parentMapId: str(row.parentMapId),
      ...parseJsonCell(row.configJson, `Maps.${mapId}.configJson`),
    });
  }
  return maps;
}
