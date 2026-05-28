import * as monaco from 'monaco-editor';
import editorWorkerUrl from 'monaco-editor/esm/vs/editor/editor.worker?url';
import { lintInWorker } from './lint/client';
import type { PlaygroundDiagnostic, PlaygroundDialect, PlaygroundSeverity } from './lint/types';
import { executeEmbeddedQuery, getDbVisualizerSnapshot, seedEmbeddedDb, resetEmbeddedDb, type DbEngineMode, type DartRunner } from './db/embedded';
import { initDartAnalyzer, analyzeDart, type DartDiagnostic } from './lint/dart_analyzer';
import { initDartRuntime, runDart, parseSqlSentinels } from './wasm/dart_runtime';
import { EXAMPLES } from './examples';
import sampleCode from './sample.dart?raw';
import './styles.css';

// ── DOM nodes ─────────────────────────────────────────────────────────────────
const editorNode       = document.getElementById('editor')!;
const outputNode       = document.getElementById('output') as HTMLPreElement;
const dbTableWrapNode  = document.getElementById('db-table-wrap') as HTMLDivElement;
const dbVisualizerNode = document.getElementById('db-visualizer') as HTMLDivElement;
const refreshDbVizBtn  = document.getElementById('refresh-db-viz') as HTMLButtonElement;
const resetDbBtn       = document.getElementById('reset-db') as HTMLButtonElement;
const diagnosticsNode  = document.getElementById('diagnostics') as HTMLUListElement;
const runStatusNode    = document.getElementById('run-status') as HTMLDivElement;
const runStatusTextNode= document.getElementById('run-status-text') as HTMLSpanElement;
const runButton        = document.getElementById('run') as HTMLButtonElement;
const runBtnSpinner    = document.getElementById('run-btn-spinner') as HTMLSpanElement;
const runBtnText       = document.getElementById('run-btn-text') as HTMLSpanElement;
const dbEngineNode     = document.getElementById('db-engine') as HTMLSelectElement;
const dialectNode      = document.getElementById('dialect') as HTMLSelectElement;
const timingNode       = document.getElementById('timing') as HTMLSpanElement;
const examplesNode     = document.getElementById('examples') as HTMLSelectElement;
const shareBtn         = document.getElementById('share') as HTMLButtonElement;
const copyOutputBtn    = document.getElementById('copy-output') as HTMLButtonElement;
const toastNode        = document.getElementById('toast') as HTMLDivElement;

// ── URL hash: encode/decode (URL-safe base64, no padding) ────────────────────
function encodeCode(code: string): string {
  const bytes = new TextEncoder().encode(code);
  let bin = '';
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

function decodeCode(b64: string): string | null {
  try {
    const norm = b64.replace(/-/g, '+').replace(/_/g, '/');
    const pad  = norm + '==='.slice((norm.length + 3) % 4);
    const bin  = atob(pad);
    const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
    return new TextDecoder().decode(bytes);
  } catch { return null; }
}

function getHashParams(): { code: string | null; dialect: string | null } {
  const params = new URLSearchParams(location.hash.slice(1));
  const raw = params.get('code');
  return { code: raw ? decodeCode(raw) : null, dialect: params.get('dialect') };
}

function setHashCode(code: string) {
  const params = new URLSearchParams();
  params.set('code', encodeCode(code));
  params.set('dialect', dialectNode.value);
  history.replaceState(null, '', '#' + params.toString());
}

// ── Toast ─────────────────────────────────────────────────────────────────────
let toastTimer: number | undefined;
function showToast(msg: string) {
  toastNode.textContent = msg;
  toastNode.classList.remove('hidden');
  clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => toastNode.classList.add('hidden'), 2000);
}

// ── Monaco worker ─────────────────────────────────────────────────────────────
(window as any).MonacoEnvironment = {
  getWorker(_: string, _label: string) {
    return new Worker(editorWorkerUrl, { type: 'module' });
  },
};

// ── Monaco editor ─────────────────────────────────────────────────────────────
monaco.languages.register({ id: 'dart' });
monaco.languages.setLanguageConfiguration('dart', {
  comments: { lineComment: '//', blockComment: ['/*', '*/'] },
  brackets: [['{', '}'], ['[', ']'], ['(', ')']],
});

const { code: hashCode, dialect: hashDialect } = getHashParams();
if (hashDialect && (dialectNode.querySelector(`option[value="${hashDialect}"]`))) {
  dialectNode.value = hashDialect;
}
const initialCode = hashCode ?? sampleCode;
const model = monaco.editor.createModel(initialCode, 'dart');
const editor = monaco.editor.create(editorNode, {
  model,
  automaticLayout: true,
  minimap: { enabled: false },
  fontSize: 14,
  theme: 'vs-dark',
  scrollBeyondLastLine: false,
});

// Cmd/Ctrl+Enter → Run
editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.Enter, () => {
  runButton.click();
});

// ── Examples dropdown ─────────────────────────────────────────────────────────
for (const ex of EXAMPLES) {
  const opt = document.createElement('option');
  opt.value = ex.name;
  opt.textContent = ex.name;
  examplesNode.appendChild(opt);
}

examplesNode.addEventListener('change', () => {
  const ex = EXAMPLES.find((e) => e.name === examplesNode.value);
  if (!ex) return;
  model.setValue(ex.code);
  dialectNode.value = ex.dialect;
  examplesNode.value = '';          // reset so same example can be re-selected
  runLint().catch(() => {});
  refreshDbVisualizer().catch(() => {});
});

// ── Background init ────────────────────────────────────────────────────────────
let analyzerReady = false;
initDartAnalyzer().then((ok) => {
  analyzerReady = ok;
  if (ok) runLint().catch(() => {});
});

const dartRunner: DartRunner = async (source) => {
  const result = await runDart(source);
  return parseSqlSentinels(result.lines);
};

async function ensureEmbeddedDbReady(engine: DbEngineMode, dialect: PlaygroundDialect) {
  if (engine === 'none') return;
  await initDartRuntime();
  await seedEmbeddedDb(engine, dialect, dartRunner);
}

ensureEmbeddedDbReady(
  dbEngineNode.value as DbEngineMode,
  dialectNode.value as PlaygroundDialect,
)
  .then(() => refreshDbVisualizer())
  .catch((e) => console.warn('[dart_runtime] init/seed failed:', e));

// ── Helpers ───────────────────────────────────────────────────────────────────
function severityToMonaco(sev: PlaygroundSeverity): monaco.MarkerSeverity {
  switch (sev) {
    case 'error':   return monaco.MarkerSeverity.Error;
    case 'warning': return monaco.MarkerSeverity.Warning;
    case 'info':    return monaco.MarkerSeverity.Info;
    default:        return monaco.MarkerSeverity.Hint;
  }
}

function offsetToLineCol(text: string, offset: number) {
  let line = 1, col = 1;
  for (let i = 0; i < Math.min(offset, text.length); i++) {
    if (text[i] === '\n') { line++; col = 1; } else col++;
  }
  return { line, col };
}

function applyMonacoMarkers(text: string, diagnostics: PlaygroundDiagnostic[]) {
  monaco.editor.setModelMarkers(model, 'knex-lint', diagnostics.map((d) => {
    const s = offsetToLineCol(text, d.startOffset);
    const e = offsetToLineCol(text, Math.max(d.endOffset, d.startOffset + 1));
    return {
      code: d.code, message: d.message, source: d.source,
      severity: severityToMonaco(d.severity),
      startLineNumber: s.line, startColumn: s.col,
      endLineNumber: e.line, endColumn: e.col,
    };
  }));
}

function renderDiagnostics(diagnostics: PlaygroundDiagnostic[]) {
  diagnosticsNode.innerHTML = '';
  if (diagnostics.length === 0) {
    diagnosticsNode.innerHTML = '<li class="diag-ok">No issues.</li>';
    return;
  }
  for (const d of diagnostics) {
    const li = document.createElement('li');
    li.className = d.severity === 'error' ? 'diag-error' : 'diag-warning';
    li.textContent = `[${d.code}] ${d.message}`;
    diagnosticsNode.appendChild(li);
  }
}

let isRunning = false;
let isResettingDb = false;

function syncControls() {
  runButton.disabled = isRunning;
  dialectNode.disabled = isRunning;
  dbEngineNode.disabled = isRunning;
  examplesNode.disabled = isRunning;
  refreshDbVizBtn.disabled = isRunning;
  resetDbBtn.disabled = isRunning || isResettingDb;
}

function setRunning(running: boolean, msg = 'Running…') {
  isRunning = running;
  syncControls();
  runBtnSpinner.classList.toggle('hidden', !running);
  runBtnText.textContent = running ? msg : '▶ Run';
  runStatusTextNode.textContent = msg;
  runStatusNode.classList.toggle('hidden', !running);
}

function buildTable(columns: string[], rows: unknown[][]): HTMLTableElement {
  const table = document.createElement('table');
  table.className = 'result-table';
  const thead = document.createElement('thead');
  const hr = document.createElement('tr');
  for (const col of columns) {
    const th = document.createElement('th');
    th.textContent = col;
    hr.appendChild(th);
  }
  thead.appendChild(hr);
  table.appendChild(thead);
  const tbody = document.createElement('tbody');
  for (const row of rows) {
    const tr = document.createElement('tr');
    for (const val of row) {
      const td = document.createElement('td');
      td.textContent = val == null ? 'NULL' : String(val);
      tr.appendChild(td);
    }
    tbody.appendChild(tr);
  }
  table.appendChild(tbody);
  return table;
}

let dbVisualizerRunId = 0;

async function refreshDbVisualizer() {
  const runId = ++dbVisualizerRunId;
  const engine = dbEngineNode.value as DbEngineMode;
  if (engine === 'none') {
    dbVisualizerNode.textContent = '';
    return;
  }
  const dialect = dialectNode.value as PlaygroundDialect;
  await ensureEmbeddedDbReady(engine, dialect);
  const snap = await getDbVisualizerSnapshot({ dialect, engine, limit: 10 });
  if (runId !== dbVisualizerRunId) return;
  dbVisualizerNode.innerHTML = '';
  if (snap.tables.length === 0) { dbVisualizerNode.textContent = 'No tables.'; return; }
  for (const t of snap.tables) {
    const card = document.createElement('div');
    card.className = 'db-table-card';
    const title = document.createElement('div');
    title.className = 'db-table-title';
    title.textContent = `${t.name} (${t.rowCount} rows)`;
    card.appendChild(title);
    if (t.columns.length > 0) card.appendChild(buildTable(t.columns, t.rows));
    dbVisualizerNode.appendChild(card);
  }
}

// ── Lint ──────────────────────────────────────────────────────────────────────
let lintTimer: number | undefined;
let lintRunId = 0;

function applyWasmMarkers(diags: DartDiagnostic[]) {
  monaco.editor.setModelMarkers(model, 'dart-analyzer', diags.map((d) => ({
    message: d.message,
    source: `dart_analyzer [${d.code}]`,
    severity: severityToMonaco(d.severity),
    startLineNumber: d.startLine,
    startColumn: d.startColumn,
    endLineNumber: d.endLine,
    endColumn: d.endColumn,
  })));
}

async function runLint() {
  const text = model.getValue();
  const dialect = dialectNode.value as PlaygroundDialect;
  const runId = ++lintRunId;
  const [regexDiags, wasmDiags] = await Promise.all([
    lintInWorker({ text, dialect }),
    analyzerReady ? analyzeDart(text) : Promise.resolve([] as DartDiagnostic[]),
  ]);
  if (runId !== lintRunId) return;
  if (text !== model.getValue()) return;
  if (dialect !== (dialectNode.value as PlaygroundDialect)) return;
  applyMonacoMarkers(text, regexDiags);
  applyWasmMarkers(wasmDiags);
  const wasmAsPanel: PlaygroundDiagnostic[] = wasmDiags.map((d) => ({
    code: d.code, source: 'dart_analyzer', message: d.message,
    severity: d.severity as PlaygroundSeverity,
    startOffset: 0, endOffset: 0,
  }));
  renderDiagnostics([...wasmAsPanel, ...regexDiags]);
}

model.onDidChangeContent(() => {
  clearTimeout(lintTimer);
  lintTimer = window.setTimeout(() => runLint().catch(() => {}), 300);
  // Persist to localStorage
  localStorage.setItem('knex_playground_code', model.getValue());
});

dialectNode.addEventListener('change', () => {
  runLint().catch(() => {});
  refreshDbVisualizer().catch(() => {});
});

dbEngineNode.addEventListener('change', () => refreshDbVisualizer().catch(() => {}));

// ── Run ───────────────────────────────────────────────────────────────────────
async function doRun() {
  const source = model.getValue();
  const dialect = dialectNode.value as PlaygroundDialect;
  const engine  = dbEngineNode.value as DbEngineMode;

  outputNode.textContent = '';
  dbTableWrapNode.innerHTML = '';
  timingNode.textContent = '';

  try {
    setRunning(true, 'Compiling…');
    const result = await runDart(source, (line) => {
      outputNode.textContent += line + '\n';
    });

    if (result.error) {
      outputNode.textContent = result.error;
      return;
    }

    timingNode.textContent = `compile ${result.compileMs}ms · run ${result.runMs}ms`;

    const sentinels = parseSqlSentinels(result.lines);
    if (!outputNode.textContent.trim()) outputNode.textContent = '(no output)';

    if (sentinels.length > 0 && engine !== 'none') {
      setRunning(true, 'Executing…');
      await ensureEmbeddedDbReady(engine, dialect);
      dbTableWrapNode.innerHTML = '';
      for (const sentinel of sentinels) {
        const dbResult = await executeEmbeddedQuery({
          dialect, sql: sentinel.sql, bindings: sentinel.bindings, engine,
        });
        if (dbResult.columns.length > 0) {
          dbTableWrapNode.innerHTML = '';
          dbTableWrapNode.appendChild(buildTable(dbResult.columns, dbResult.rows));
        } else if (sentinels.length === 1) {
          dbTableWrapNode.innerHTML = `<p class="db-meta">${dbResult.rowCount} rows affected · ${dbResult.durationMs}ms</p>`;
        }
      }
      await refreshDbVisualizer();
    }
  } catch (err) {
    outputNode.textContent = `Error: ${String(err)}`;
  } finally {
    setRunning(false);
  }
}

runButton.addEventListener('click', doRun);

// ── Share ─────────────────────────────────────────────────────────────────────
shareBtn.addEventListener('click', () => {
  const code = model.getValue();
  setHashCode(code);
  navigator.clipboard.writeText(location.href).then(() => {
    showToast('Link copied to clipboard!');
  }).catch(() => {
    showToast(location.href);
  });
});

// ── Copy output ───────────────────────────────────────────────────────────────
copyOutputBtn.addEventListener('click', () => {
  const text = outputNode.textContent ?? '';
  navigator.clipboard.writeText(text).then(() => showToast('Output copied!'));
});

// ── Reset DB ──────────────────────────────────────────────────────────────────
resetDbBtn.addEventListener('click', async () => {
  const engine  = dbEngineNode.value as DbEngineMode;
  const dialect = dialectNode.value as PlaygroundDialect;
  isResettingDb = true;
  syncControls();
  try {
    await resetEmbeddedDb(engine, dialect, dartRunner);
    await refreshDbVisualizer();
    showToast('DB reset to seed data.');
  } finally {
    isResettingDb = false;
    syncControls();
  }
});

refreshDbVizBtn.addEventListener('click', () => refreshDbVisualizer().catch(() => {}));

// ── Init ──────────────────────────────────────────────────────────────────────
// Restore from localStorage if no URL hash code
if (!hashCode) {
  const saved = localStorage.getItem('knex_playground_code');
  if (saved) model.setValue(saved);
}

runLint().catch(() => {});
refreshDbVisualizer().catch(() => {});
syncControls();

window.addEventListener('beforeunload', () => { editor.dispose(); model.dispose(); });
