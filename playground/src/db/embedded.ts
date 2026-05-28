import { PGlite } from '@electric-sql/pglite';
import type { PlaygroundDialect } from '../lint/types';
import seedDartSource from './seed.dart?raw';

export type DbEngineMode = 'auto' | 'sqlite' | 'pglite' | 'none';

export interface EmbeddedExecutionInput {
  dialect: PlaygroundDialect;
  sql: string;
  bindings: unknown[];
  engine: DbEngineMode;
}

export interface EmbeddedExecutionResult {
  engine: 'sqlite' | 'pglite';
  durationMs: number;
  rowCount: number;
  columns: string[];
  rows: unknown[][];
}

export interface DbTableSnapshot {
  name: string;
  rowCount: number;
  columns: string[];
  rows: unknown[][];
}

export interface DbVisualizerSnapshot {
  engine: 'sqlite' | 'pglite';
  tables: DbTableSnapshot[];
}

export type DartRunner = (source: string) => Promise<Array<{ sql: string; bindings: unknown[] }>>;

type AnySqliteDb = any;
type AnyPglite = any;
type InitSqlJsFn = (config: { locateFile: (file: string) => string }) => Promise<any>;

let sqliteDb: AnySqliteDb | undefined;
let pglitePromise: Promise<AnyPglite> | undefined;
let initSqlJsPromise: Promise<InitSqlJsFn> | undefined;
let sqliteSeeded = false;
let pgliteSeeded = false;
const seedPromises: Partial<Record<'sqlite' | 'pglite', Promise<void>>> = {};

declare global {
  interface Window {
    initSqlJs?: InitSqlJsFn;
  }
}

function isFn(value: unknown): value is (...args: unknown[]) => unknown {
  return typeof value === 'function';
}

async function loadSqlJsInitializer(): Promise<InitSqlJsFn> {
  if (initSqlJsPromise) return initSqlJsPromise;
  if (isFn(window.initSqlJs)) return window.initSqlJs;

  initSqlJsPromise = (async () => {
    // Browser-safe script loader. Module wrappers for sql.js sometimes pull
    // Node shims (fs.readFileSync) through CDN transforms, so we avoid them.
    await new Promise<void>((resolve, reject) => {
      const existing = document.querySelector<HTMLScriptElement>(
        'script[data-sqljs-loader="1"]',
      );
      if (existing) {
        if (isFn(window.initSqlJs)) {
          resolve();
          return;
        }
        existing.addEventListener('load', () => resolve(), { once: true });
        existing.addEventListener(
          'error',
          () => reject(new Error('sql.js script failed to load')),
          { once: true },
        );
        return;
      }

      const script = document.createElement('script');
      script.src = 'https://cdn.jsdelivr.net/npm/sql.js@1.13.0/dist/sql-wasm.js';
      script.async = true;
      script.dataset.sqljsLoader = '1';
      script.onload = () => resolve();
      script.onerror = () => reject(new Error('sql.js script failed to load'));
      document.head.appendChild(script);
    });

    if (isFn(window.initSqlJs)) return window.initSqlJs;
    throw new Error('Unable to resolve initSqlJs from CDN module/script');
  })().catch((error) => {
    initSqlJsPromise = undefined;
    throw error;
  });

  return initSqlJsPromise;
}

function resolveEngine(engine: DbEngineMode, dialect: PlaygroundDialect): 'sqlite' | 'pglite' {
  if (engine === 'sqlite' || engine === 'pglite') return engine;
  if (dialect === 'postgres') return 'pglite';
  return 'sqlite';
}

async function getSqliteDb(): Promise<AnySqliteDb> {
  if (sqliteDb) return sqliteDb;

  const initSqlJs = await loadSqlJsInitializer();
  const SQL = await initSqlJs({
    locateFile: (file: string) => `https://cdn.jsdelivr.net/npm/sql.js@1.13.0/dist/${file}`,
  });
  sqliteDb = new SQL.Database();
  return sqliteDb;
}

async function getPgliteDb(): Promise<AnyPglite> {
  if (pglitePromise) return pglitePromise;
  pglitePromise = (async () => {
    const db = new PGlite();
    await db.waitReady;
    return db;
  })().catch((error) => {
    pglitePromise = undefined;
    throw error;
  });
  return pglitePromise;
}

async function executeSqlite(sql: string, bindings: unknown[]): Promise<EmbeddedExecutionResult> {
  const db = await getSqliteDb();
  const start = performance.now();

  const stmt = db.prepare(sql);
  stmt.bind(bindings as any[]);

  const columns = stmt.getColumnNames();
  const rows: unknown[][] = [];
  while (stmt.step()) {
    rows.push(stmt.get());
  }

  stmt.free();
  const durationMs = Number((performance.now() - start).toFixed(3));

  return {
    engine: 'sqlite',
    durationMs,
    rowCount: rows.length,
    columns,
    rows,
  };
}

async function executePglite(sql: string, bindings: unknown[]): Promise<EmbeddedExecutionResult> {
  const db = await getPgliteDb();
  const start = performance.now();

  const result = await db.query(sql, bindings as any[]);
  const durationMs = Number((performance.now() - start).toFixed(3));

  const rows = result.rows.map((row: any) => Object.values(row));
  const columns = result.fields.map((field: any) => field.name);

  return {
    engine: 'pglite',
    durationMs,
    rowCount: rows.length,
    columns,
    rows,
  };
}

// Drops and recreates embedded DB instances so seed runs fresh.
export async function resetEmbeddedDb(
  engine: DbEngineMode,
  dialect: PlaygroundDialect,
  runner: DartRunner,
): Promise<void> {
  const resolvedEngine = resolveEngine(engine, dialect);
  await seedPromises[resolvedEngine]?.catch(() => {});
  if (resolvedEngine === 'sqlite') {
    sqliteDb?.close?.();
    sqliteDb = undefined;
    sqliteSeeded = false;
  } else {
    const db = await pglitePromise?.catch(() => undefined);
    await db?.close?.();
    pglitePromise = undefined;
    pgliteSeeded = false;
  }
  await seedEmbeddedDb(engine, dialect, runner);
}

// Seeds the embedded DB using knex_dart Dart code — runs once per engine instance.
export async function seedEmbeddedDb(
  engine: DbEngineMode,
  dialect: PlaygroundDialect,
  runner: DartRunner,
): Promise<void> {
  const resolvedEngine = resolveEngine(engine, dialect);
  if (resolvedEngine === 'sqlite' && sqliteSeeded) return;
  if (resolvedEngine === 'pglite' && pgliteSeeded) return;
  if (seedPromises[resolvedEngine]) return seedPromises[resolvedEngine];

  seedPromises[resolvedEngine] = (async () => {
    // Inject dialect so seed.dart picks the right knex_dart dialect
    const seedDialect = resolvedEngine === 'pglite' ? 'postgres' : 'sqlite';
    const source = seedDartSource.replace("defaultValue: 'sqlite'", `defaultValue: '${seedDialect}'`);

    const sentinels = await runner(source);
    for (const s of sentinels) {
      await executeEmbeddedQuery({ dialect, sql: s.sql, bindings: s.bindings, engine });
    }

    if (resolvedEngine === 'sqlite') sqliteSeeded = true;
    else pgliteSeeded = true;
  })().finally(() => {
    delete seedPromises[resolvedEngine];
  });

  return seedPromises[resolvedEngine];
}

export async function executeEmbeddedQuery(
  input: EmbeddedExecutionInput,
): Promise<EmbeddedExecutionResult> {
  const engine = resolveEngine(input.engine, input.dialect);
  if (engine === 'pglite') {
    return executePglite(input.sql, input.bindings);
  }
  return executeSqlite(input.sql, input.bindings);
}

async function snapshotSqlite(limit: number): Promise<DbVisualizerSnapshot> {
  const db = await getSqliteDb();
  const tableRows = db.exec(`
    select name
    from sqlite_master
    where type = 'table' and name not like 'sqlite_%'
    order by name;
  `);

  const tableNames = (tableRows[0]?.values ?? []).map((row: any[]) => String(row[0]));
  const tables: DbTableSnapshot[] = [];

  for (const name of tableNames) {
    const countRes = db.exec(`select count(*) as c from "${name}";`);
    const rowCount = Number(countRes[0]?.values?.[0]?.[0] ?? 0);

    const stmt = db.prepare(`select * from "${name}" limit ${limit};`);
    const columns = stmt.getColumnNames();
    const rows: unknown[][] = [];
    while (stmt.step()) {
      rows.push(stmt.get());
    }
    stmt.free();

    tables.push({ name, rowCount, columns, rows });
  }

  return { engine: 'sqlite', tables };
}

async function snapshotPglite(limit: number): Promise<DbVisualizerSnapshot> {
  const db = await getPgliteDb();
  const list = await db.query(`
    select tablename
    from pg_tables
    where schemaname = 'public'
    order by tablename;
  `);
  const tableNames = (list.rows as Array<{ tablename: string }>).map((r) => r.tablename);

  const tables: DbTableSnapshot[] = [];
  for (const name of tableNames) {
    const countRes = await db.query(`select count(*)::int as c from "${name}";`);
    const rowCount = Number((countRes.rows as Array<{ c: number }>)[0]?.c ?? 0);

    const result = await db.query(`select * from "${name}" limit ${limit};`);
    const columns = result.fields.map((f: any) => f.name);
    const rows = (result.rows as any[]).map((row) =>
      columns.map((c: string) => row[c]),
    );

    tables.push({ name, rowCount, columns, rows });
  }

  return { engine: 'pglite', tables };
}

export async function getDbVisualizerSnapshot(input: {
  dialect: PlaygroundDialect;
  engine: DbEngineMode;
  limit?: number;
}): Promise<DbVisualizerSnapshot> {
  const engine = resolveEngine(input.engine, input.dialect);
  const limit = input.limit ?? 20;
  if (engine === 'pglite') {
    return snapshotPglite(limit);
  }
  return snapshotSqlite(limit);
}
