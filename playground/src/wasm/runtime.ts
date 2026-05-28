export type RuntimeMode = 'wasm' | 'dart_eval';

export interface ExecutionResult {
  sql: string;
  bindings: unknown[];
  logs: string[];
}

interface WasmResponse {
  ok: boolean;
  sql?: string;
  bindings?: unknown[];
  dialect?: string;
  error?: string;
  details?: string;
}

declare global {
  interface Window {
    knexBuildQuery?: (jsonInput: string) => string;
    knexRunExample?: (dialect: string) => string;
  }
}

let wasmReadyPromise: Promise<void> | undefined;

export async function initWasmRuntime(): Promise<void> {
  if (wasmReadyPromise) return wasmReadyPromise;

  wasmReadyPromise = (async () => {
    const wasmModulePromise = WebAssembly.compileStreaming(fetch('/wasm/main.wasm'));
    const runtimeUrl = `${window.location.origin}/wasm/main.mjs`;
    const runtime = await import(/* @vite-ignore */ runtimeUrl);
    if (typeof runtime.instantiate === 'function' && typeof runtime.invoke === 'function') {
      const instance = await runtime.instantiate(wasmModulePromise, {});
      await runtime.invoke(instance);
      return;
    }

    // Fallback for alternate generated runtime layouts.
    if (typeof runtime.main === 'function') {
      await runtime.main();
      return;
    }

    throw new Error('Unsupported wasm runtime exports from /wasm/main.mjs');
  })();

  return wasmReadyPromise;
}

function parseWasmJson(raw: string): WasmResponse {
  try {
    return JSON.parse(raw) as WasmResponse;
  } catch (error) {
    throw new Error(`Invalid JSON response from wasm runtime: ${String(error)}`);
  }
}

export async function runWasm(execInput: string, dialect: string): Promise<ExecutionResult> {
  await initWasmRuntime();

  const fn = window.knexBuildQuery;
  if (typeof fn !== 'function') {
    throw new Error('knexBuildQuery export was not initialized by wasm runtime');
  }

  const raw = fn(execInput);
  const response = parseWasmJson(raw);
  if (!response.ok) {
    throw new Error(response.details ? `${response.error}: ${response.details}` : response.error ?? 'Wasm execution failed');
  }

  return {
    sql: response.sql ?? '',
    bindings: response.bindings ?? [],
    logs: [`dialect=${response.dialect ?? dialect}`, 'runtime=wasm'],
  };
}

export async function runDartEval(code: string, _dialect: string): Promise<ExecutionResult> {
  // Stub to allow UI switching before integrating actual dart_eval strategy.
  return {
    sql: '-- dart_eval runtime placeholder\n-- integrate package and sandbox policy',
    bindings: [],
    logs: [`input_length=${code.length}`],
  };
}

export async function runCode(
  mode: RuntimeMode,
  execInput: string,
  dialect: string,
): Promise<ExecutionResult> {
  if (mode === 'dart_eval') {
    return runDartEval(execInput, dialect);
  }
  return runWasm(execInput, dialect);
}
