// Loads and initializes dart_analyzer.wasm for in-browser Dart type checking.
// Wraps dartAnalyzerInit + dartAnalyze into a Promise-based API.

declare global {
  function dartAnalyzerInit(
    sdkBytes: Uint8Array,
    packageNames: string[],
    packageSummaries: Uint8Array[],
  ): void;
  // dartAnalyze is async in dart2wasm — it returns a Promise<string>
  function dartAnalyze(source: string): Promise<string>;
}

const PACKAGES = [
  'collection',
  'logging',
  'meta',
  'typed_data',
  'universal_io',
  'knex_dart_capabilities',
  'knex_dart',
] as const;

let initPromise: Promise<boolean> | undefined;

export function initDartAnalyzer(): Promise<boolean> {
  if (initPromise) return initPromise;

  initPromise = (async () => {
    try {
      const base = '/analyzer';
      const [mjs, analyzerWasm, sdkBuf, ...sumBufs] = await Promise.all([
        import(/* @vite-ignore */ `${base}/dart_analyzer.mjs`),
        fetch(`${base}/dart_analyzer.wasm`),
        fetch(`${base}/dart_sdk.sum`).then((r) => r.arrayBuffer()),
        ...PACKAGES.map((p) =>
          fetch(`${base}/packages/${p}.sum`).then((r) => r.arrayBuffer()),
        ),
      ]);

      const compiled = await mjs.compileStreaming(analyzerWasm);
      const inst = await compiled.instantiate({});
      inst.invokeMain([]);

      const packageNames = [...PACKAGES];
      const packageSummaries = sumBufs.map((b) => new Uint8Array(b));

      // Try with all package summaries first; fall back to SDK-only if it crashes
      try {
        globalThis.dartAnalyzerInit(new Uint8Array(sdkBuf), packageNames, packageSummaries);
      } catch {
        console.warn('[dart_analyzer] init with packages failed, retrying SDK-only');
        globalThis.dartAnalyzerInit(new Uint8Array(sdkBuf), [], []);
      }

      return true;
    } catch (e) {
      console.error('[dart_analyzer] init failed:', e);
      return false;
    }
  })();

  return initPromise;
}

// dartAnalyze returns line/column positions (1-based), matching Monaco's format.
export interface DartDiagnostic {
  severity: 'error' | 'warning' | 'info' | 'hint';
  message: string;
  code: string;
  startLine: number;
  startColumn: number;
  endLine: number;
  endColumn: number;
}

export async function analyzeDart(source: string): Promise<DartDiagnostic[]> {
  if (typeof globalThis.dartAnalyze !== 'function') return [];
  try {
    const raw = await globalThis.dartAnalyze(source);
    const result = JSON.parse(raw) as Array<{
      severity: string;
      message: string;
      code: string;
      startLine?: number;
      startColumn?: number;
      endLine?: number;
      endColumn?: number;
    }>;
    return result.map((d) => ({
      severity: normalizeSeverity(d.severity),
      message: d.message,
      code: d.code ?? '',
      startLine: d.startLine ?? 1,
      startColumn: d.startColumn ?? 1,
      endLine: d.endLine ?? d.startLine ?? 1,
      endColumn: d.endColumn ?? (d.startColumn ?? 1) + 1,
    }));
  } catch {
    return [];
  }
}

function normalizeSeverity(s: string): DartDiagnostic['severity'] {
  switch (s?.toLowerCase()) {
    case 'error':   return 'error';
    case 'warning': return 'warning';
    case 'info':    return 'info';
    default:        return 'hint';
  }
}
