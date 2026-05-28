// dart_runtime.ts
// Wraps dart-live's CFE + VM WASM for in-browser Dart compilation + execution.
// CFE (dart_cfe.wasm) compiles Dart source to kernel bytes.
// VM  (dart_il.wasm)  runs kernel bytes and calls onDartPrint() per print() line.

const BASE = '/dart-live';

export interface DartRunResult {
  output: string;
  lines: string[];
  compileMs: number;
  runMs: number;
  error?: string;
}

declare global {
  function dartCompile(
    source: string,
    platformBytes: Uint8Array,
    packageDills: Uint8Array[],
  ): Promise<Uint8Array>;
}

// Module-level state so onDartPrint can be swapped per run without reinit.
let _printLines: string[] = [];
let _onLine: ((line: string) => void) | null = null;

function _onDartPrint(line: string) {
  _printLines.push(line);
  _onLine?.(line);
}

let _vm: any = null;
let _platformBytes: Uint8Array | null = null;
let _packageDills: Uint8Array[] = [];
let _initPromise: Promise<void> | null = null;

export function initDartRuntime(): Promise<void> {
  if (_initPromise) return _initPromise;

  _initPromise = (async () => {
    // 1. Boot the VM (Emscripten module — defines cwrap, malloc, HEAPU8, etc.)
    const { default: createDartIL } = await import(
      /* @vite-ignore */ `${BASE}/dart_il.mjs`
    );
    _vm = await createDartIL({
      onDartPrint: _onDartPrint,
      locateFile: (path: string) => `${BASE}/${path}`,
    });

    // 2. Boot the CFE WASM — registers globalThis.dartCompile
    const { compileStreaming } = await import(
      /* @vite-ignore */ `${BASE}/dart_cfe.mjs`
    );
    const cfeApp = await compileStreaming(fetch(`${BASE}/dart_cfe.wasm`));
    const cfeInst = await cfeApp.instantiate({});
    cfeInst.invokeMain([]);

    // 3. Load SDK platform + knex_dart.dill
    const [platformBuf, knexBuf] = await Promise.all([
      fetch(`${BASE}/vm_platform.dill`).then((r) => r.arrayBuffer()),
      fetch(`${BASE}/knex_dart.dill`).then((r) => r.arrayBuffer()),
    ]);
    _platformBytes = new Uint8Array(platformBuf);
    _packageDills = [new Uint8Array(knexBuf)];
  })();

  return _initPromise;
}

const _runAsync = () =>
  _vm.cwrap('dart_il_run', 'number', ['number', 'number'], { async: true });

export async function runDart(
  source: string,
  onLine?: (line: string) => void,
): Promise<DartRunResult> {
  await initDartRuntime();

  // Reset per-run state
  _printLines = [];
  _onLine = onLine ?? null;

  // Compile
  const t0 = performance.now();
  let kernel: Uint8Array;
  try {
    kernel = new Uint8Array(
      await globalThis.dartCompile(source, _platformBytes!, _packageDills),
    );
    // dart-live patches bytes 8–17 to 0x30 before running — mirror that
    for (let i = 8; i < 18; i++) kernel[i] = 0x30;
  } catch (e: any) {
    return {
      output: '',
      lines: [],
      compileMs: 0,
      runMs: 0,
      error: String(e?.error ?? e?.message ?? e),
    };
  }
  const compileMs = Number((performance.now() - t0).toFixed(1));

  // Run
  const t1 = performance.now();
  const ptr = _vm._malloc(kernel.length);
  _vm.HEAPU8.set(kernel, ptr);
  let output = '';
  try {
    const resPtr = await _runAsync()(ptr, kernel.length);
    output = _vm.UTF8ToString(resPtr);
    // Yield to let Asyncify state settle (mirrors dart-live workaround)
    await new Promise((r) => setTimeout(r, 0));
  } finally {
    _vm._free(ptr);
  }
  const runMs = Number((performance.now() - t1).toFixed(1));

  return { output, lines: [..._printLines], compileMs, runMs };
}

// Parse a print() line as a knex SQL result sentinel.
// Convention: any line that is valid JSON with {sql: string, bindings: unknown[]}
// is treated as SQL to execute against the embedded DB.
export interface KnexSqlResult {
  sql: string;
  bindings: unknown[];
}

export function parseSqlSentinels(lines: string[]): KnexSqlResult[] {
  const results: KnexSqlResult[] = [];
  for (const line of lines) {
    const t = line.trim();
    if (!t.startsWith('{')) continue;
    try {
      const obj = JSON.parse(t) as Record<string, unknown>;
      if (typeof obj.sql === 'string' && Array.isArray(obj.bindings)) {
        results.push({ sql: obj.sql, bindings: obj.bindings });
      }
    } catch {
      // not JSON — skip
    }
  }
  return results;
}
