import { HEADERS } from './workbook-schema.mjs';
import { blankToUndefined } from './workbook-values.mjs';

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
