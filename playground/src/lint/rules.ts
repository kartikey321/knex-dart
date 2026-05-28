import type {
  PlaygroundDiagnostic,
  PlaygroundDialect,
  LintRequest,
} from './types';

const SOURCE = 'knex_dart_lint(browser)';

const VALID_OPERATORS = new Set([
  '=',
  '!=',
  '<>',
  '<',
  '>',
  '<=',
  '>=',
  'like',
  'not like',
  'ilike',
  'not ilike',
  'similar to',
  'not similar to',
  '@>',
  '<@',
  '&&',
  '?',
  '?|',
  '?&',
  '#>>',
  '~~',
  '!~~',
  '~~*',
  '!~~*',
]);

const DIALECT_CAPS: Record<PlaygroundDialect, Set<string>> = {
  postgres: new Set([
    'returning',
    'fullOuterJoin',
    'joinLateral',
    'leftJoinLateral',
    'crossJoinLateral',
    'with',
    'withRecursive',
    'rowNumber',
    'denseRank',
    'rank',
    'jsonExtract',
    'jsonSet',
    'jsonInsert',
    'intersect',
    'except',
  ]),
  mysql: new Set(['with', 'withRecursive']),
  sqlite: new Set(['with', 'withRecursive']),
};

function makeDiag(
  code: string,
  message: string,
  startOffset: number,
  endOffset: number,
): PlaygroundDiagnostic {
  return {
    code,
    source: SOURCE,
    severity: 'warning',
    message,
    startOffset,
    endOffset,
  };
}

function collectInvalidWhereOperator(text: string): PlaygroundDiagnostic[] {
  const result: PlaygroundDiagnostic[] = [];
  const regex = /\.(where|orWhere|andWhere|having|orHaving)\s*\(\s*[^,]+,\s*(['"])(.*?)\2\s*,/g;
  let match: RegExpExecArray | null;

  while ((match = regex.exec(text)) != null) {
    const op = (match[3] || '').toLowerCase();
    if (VALID_OPERATORS.has(op)) continue;

    const full = match[0];
    const quotedIdx = full.indexOf(match[2] + match[3] + match[2]);
    const start = match.index + (quotedIdx >= 0 ? quotedIdx : 0);
    const end = start + match[3].length + 2;

    result.push(
      makeDiag(
        'invalid_where_operator',
        `"${match[3]}" is not a recognised SQL comparison operator.`,
        start,
        end,
      ),
    );
  }

  return result;
}

function collectWhereNullValue(text: string): PlaygroundDiagnostic[] {
  const result: PlaygroundDiagnostic[] = [];
  const regex =
    /\.(where|orWhere|andWhere)\s*\(\s*[^,]+\s*,\s*(?:[^,]+\s*,\s*)?(null)\s*\)/g;

  let match: RegExpExecArray | null;
  while ((match = regex.exec(text)) != null) {
    const nullIndex = match[0].lastIndexOf('null');
    const start = match.index + (nullIndex >= 0 ? nullIndex : 0);
    result.push(
      makeDiag(
        'where_null_value',
        'Passing null to .where() produces `col = NULL` which is always false in SQL.',
        start,
        start + 4,
      ),
    );
  }

  return result;
}

function collectDialectUnsupported(
  text: string,
  dialect: PlaygroundDialect,
): PlaygroundDiagnostic[] {
  const diagnostics: PlaygroundDiagnostic[] = [];
  const methods = [
    'returning',
    'fullOuterJoin',
    'joinLateral',
    'leftJoinLateral',
    'crossJoinLateral',
    'with',
    'withRecursive',
    'rowNumber',
    'denseRank',
    'rank',
    'jsonExtract',
    'jsonSet',
    'jsonInsert',
    'intersect',
    'except',
  ];
  const caps = DIALECT_CAPS[dialect];

  for (const method of methods) {
    if (caps.has(method)) continue;

    const regex = new RegExp(`\\.${method}\\s*\\(`, 'g');
    let match: RegExpExecArray | null;
    while ((match = regex.exec(text)) != null) {
      const start = match.index + 1;
      diagnostics.push(
        makeDiag(
          `dialect_unsupported_${method}`,
          `.${method}() is not supported by ${dialect} in this playground capability matrix.`,
          start,
          start + method.length,
        ),
      );
    }
  }

  return diagnostics;
}

function collectInvalidOrderDirection(text: string): PlaygroundDiagnostic[] {
  const result: PlaygroundDiagnostic[] = [];
  const regex = /\.orderBy\s*\(\s*[^,]+,\s*(['"])(.*?)\1\s*\)/g;
  const valid = new Set(['asc', 'desc']);

  let match: RegExpExecArray | null;
  while ((match = regex.exec(text)) != null) {
    const direction = (match[2] ?? '').toLowerCase();
    if (valid.has(direction)) continue;

    const full = match[0];
    const quotedIdx = full.indexOf(match[1] + match[2] + match[1]);
    const start = match.index + (quotedIdx >= 0 ? quotedIdx : 0);
    const end = start + match[2].length + 2;
    result.push(
      makeDiag(
        'invalid_order_direction',
        `Unsupported ORDER BY direction "${match[2]}". Use "asc" or "desc".`,
        start,
        end,
      ),
    );
  }

  return result;
}

export function runBrowserLint(request: LintRequest): PlaygroundDiagnostic[] {
  const { text, dialect } = request;
  return [
    ...collectInvalidWhereOperator(text),
    ...collectWhereNullValue(text),
    ...collectInvalidOrderDirection(text),
    ...collectDialectUnsupported(text, dialect),
  ];
}
