// dart_lsp.ts
// Wraps dart-live's dart_lsp.wasm — the full Dart analysis server compiled to
// WebAssembly.  Speaks LSP JSON-RPC over globalThis.lspSend / lspReceive and
// wires Monaco completion, hover, and diagnostic providers.
//
// Replaces the old dart_analyzer.wasm + .sum approach (removed upstream).
// Loads the DPKG source bundle (dart_packages.bin) for external packages.

import type * as Monaco from 'monaco-editor';

declare global {
  function lspSend(message: string): void;
  function lspStart(sdkSummary: Uint8Array, packageBundle: Uint8Array): void;
}

const BASE = '/dart-live';
const LSP_FILE_URI = 'file:///user/lib/main.dart';

interface DartLspModule {
  compileStreaming(response: Response): Promise<{
    instantiate(imports: Record<string, unknown>): Promise<{ invokeMain(): void }>;
  }>;
}

// ── Internal LSP transport ────────────────────────────────────────────────────

let _lspRequestId = 1;
const _lspPending = new Map<number, { resolve: (v: unknown) => void; reject: (e: unknown) => void }>();
const _lspNotifyHandlers = new Map<string, (params: unknown) => unknown>();

function _lspSendReq(method: string, params: unknown): Promise<unknown> {
  const id = _lspRequestId++;
  return new Promise((resolve, reject) => {
    _lspPending.set(id, { resolve, reject });
    globalThis.lspSend(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
  });
}

function _lspNotify(method: string, params: unknown): void {
  globalThis.lspSend(JSON.stringify({ jsonrpc: '2.0', method, params }));
}

// dart_lsp.wasm calls globalThis.lspReceive with every server → client message.
(globalThis as Record<string, unknown>).lspReceive = (jsonText: string) => {
  let m: Record<string, unknown>;
  try { m = JSON.parse(jsonText) as Record<string, unknown>; } catch { return; }
  const id = m.id as number | undefined;
  if (id !== undefined && (m.result !== undefined || m.error !== undefined)) {
    const w = _lspPending.get(id);
    if (!w) return;
    _lspPending.delete(id);
    m.error ? w.reject(m.error) : w.resolve(m.result);
  } else if (m.method && id !== undefined) {
    // Server→client request. Dart uses this for workspace/applyEdit after
    // command-based code actions, so handle known methods before replying.
    const h = _lspNotifyHandlers.get(m.method as string);
    const result = h ? h(m.params) : null;
    globalThis.lspSend(JSON.stringify({ jsonrpc: '2.0', id, result }));
  } else if (m.method) {
    const h = _lspNotifyHandlers.get(m.method as string);
    if (h) h(m.params);
  }
};

// ── Diagnostics ───────────────────────────────────────────────────────────────

type DiagHandler = (markers: Monaco.editor.IMarkerData[]) => void;
let _diagHandler: DiagHandler | null = null;
// Keep original LSP diagnostics so codeAction can pass them back verbatim.
// Reconstructing from Monaco markers corrupts the message (appends [code])
// and the Dart LSP won't match them to provide quickfixes.
let _latestDiags: LspDiagnostic[] = [];

_lspNotifyHandlers.set('textDocument/publishDiagnostics', (params: unknown) => {
  const p = params as { uri?: string; diagnostics?: LspDiagnostic[] };
  if (p?.uri !== LSP_FILE_URI) return;
  _latestDiags = p.diagnostics ?? [];
  _diagHandler?.(lspDiagsToMonaco(_latestDiags));
});

interface LspDiagnostic {
  severity?: number;
  message?: string;
  code?: string | number;
  range?: { start: LspPos; end: LspPos };
}
interface LspPos { line: number; character: number }

const SEV_MAP: Record<number, Monaco.MarkerSeverity> = {
  1: 8, // Error
  2: 4, // Warning
  3: 2, // Info
  4: 1, // Hint
};

function lspDiagsToMonaco(diags: LspDiagnostic[]): Monaco.editor.IMarkerData[] {
  return diags.map((d) => ({
    severity: SEV_MAP[d.severity ?? 4] ?? 2,
    message: `${d.message ?? ''}${d.code ? ` [${d.code}]` : ''}`,
    startLineNumber: (d.range?.start.line ?? 0) + 1,
    startColumn: (d.range?.start.character ?? 0) + 1,
    endLineNumber: (d.range?.end.line ?? 0) + 1,
    endColumn: (d.range?.end.character ?? 0) + 1,
  }));
}

// ── Position helpers ──────────────────────────────────────────────────────────

function monacoToLsp(pos: Monaco.IPosition): LspPos {
  return { line: pos.lineNumber - 1, character: pos.column - 1 };
}

function lspRangeToMonaco(r: { start: LspPos; end: LspPos }): Monaco.IRange {
  return {
    startLineNumber: r.start.line + 1,
    startColumn: r.start.character + 1,
    endLineNumber: r.end.line + 1,
    endColumn: r.end.character + 1,
  };
}

// ── Workspace edit helpers ────────────────────────────────────────────────────

interface LspTextEdit {
  range: { start: LspPos; end: LspPos };
  newText: string;
}

interface LspWorkspaceEdit {
  changes?: Record<string, LspTextEdit[]>;
  documentChanges?: Array<{
    textDocument: { uri: string };
    edits: LspTextEdit[];
  }>;
}

interface LspCodeAction {
  title: string;
  kind?: string;
  isPreferred?: boolean;
  edit?: LspWorkspaceEdit;
  command?: { title: string; command: string; arguments?: unknown[] };
}

function lspTextEditsToWorkspaceEdit(
  textEdits: LspTextEdit[],
  monaco: typeof Monaco,
  modelUri: Monaco.Uri,
): Monaco.languages.WorkspaceEdit {
  return lspWorkspaceEditToMonaco(
    { changes: { [LSP_FILE_URI]: textEdits } },
    monaco,
    modelUri,
  );
}

function lspWorkspaceEditToMonaco(
  edit: LspWorkspaceEdit,
  monaco: typeof Monaco,
  modelUri: Monaco.Uri,
): Monaco.languages.WorkspaceEdit {
  const edits: Monaco.languages.IWorkspaceTextEdit[] = [];

  const pushEdits = (uri: string, textEdits: LspTextEdit[]) => {
    // The LSP uses file:///user/lib/main.dart; Monaco's model has its own URI.
    // Map them so Monaco can locate the model to patch.
    const resource = uri === LSP_FILE_URI ? modelUri : monaco.Uri.parse(uri);
    for (const e of textEdits) {
      edits.push({
        resource,
        versionId: undefined,
        textEdit: { range: lspRangeToMonaco(e.range), text: e.newText },
      });
    }
  };

  if (edit.changes) {
    for (const [uri, textEdits] of Object.entries(edit.changes)) {
      pushEdits(uri, textEdits);
    }
  }
  if (edit.documentChanges) {
    for (const change of edit.documentChanges) {
      if ('edits' in change) pushEdits(change.textDocument.uri, change.edits);
    }
  }

  return { edits };
}

// ── Monaco provider registration ──────────────────────────────────────────────

function registerMonacoProviders(monaco: typeof Monaco, model: Monaco.editor.ITextModel): void {
  // workspace/applyEdit — server pushes edits (e.g. organise imports) directly.
  _lspNotifyHandlers.set('workspace/applyEdit', (params: unknown) => {
    const p = params as { edit?: LspWorkspaceEdit };
    if (!p?.edit) return { applied: false };
    const we = lspWorkspaceEditToMonaco(p.edit, monaco, model.uri);
    for (const e of we.edits as Monaco.languages.IWorkspaceTextEdit[]) {
      model.applyEdits([e.textEdit]);
    }
    return { applied: true };
  });
  // Completion
  monaco.languages.registerCompletionItemProvider('dart', {
    triggerCharacters: ['.', ' ', '(', '<', '"', "'", '/'],
    async provideCompletionItems(model, position) {
      try {
        const r = await _lspSendReq('textDocument/completion', {
          textDocument: { uri: LSP_FILE_URI },
          position: monacoToLsp(position),
        }) as { items?: LspCompletionItem[]; isIncomplete?: boolean } | LspCompletionItem[] | null;
        const lspItems = Array.isArray(r) ? r : (r as { items?: LspCompletionItem[] })?.items ?? [];
        const incomplete = !Array.isArray(r) && (r as { isIncomplete?: boolean })?.isIncomplete === true;
        const word = model.getWordUntilPosition(position);
        const fallbackRange = {
          startLineNumber: position.lineNumber,
          startColumn: word.startColumn,
          endLineNumber: position.lineNumber,
          endColumn: word.endColumn,
        };
        return {
          suggestions: lspItems.map((item) => lspCompletionToMonaco(item, monaco, fallbackRange)),
          incomplete,
        };
      } catch { return { suggestions: [] }; }
    },
    async resolveCompletionItem(monacoItem) {
      // Send the original LSP item back — the server needs it verbatim (especially
      // the 'data' field) to fill in additionalTextEdits for auto-import.
      const lspItem = (monacoItem as unknown as { _lspItem?: LspCompletionItem })._lspItem;
      if (!lspItem?.data) return monacoItem;
      try {
        const resolved = await _lspSendReq('completionItem/resolve', lspItem) as LspCompletionItem;
        return lspCompletionToMonaco(resolved, monaco, monacoItem.range as Monaco.IRange);
      } catch { return monacoItem; }
    },
  });

  // Hover
  monaco.languages.registerHoverProvider('dart', {
    async provideHover(_model, position) {
      try {
        const r = await _lspSendReq('textDocument/hover', {
          textDocument: { uri: LSP_FILE_URI },
          position: monacoToLsp(position),
        }) as { contents?: { kind: string; value: string }[]; range?: { start: LspPos; end: LspPos } } | null;
        if (!r?.contents?.length) return null;
        return {
          contents: r.contents.map((c) => ({ value: c.value })),
          range: r.range ? lspRangeToMonaco(r.range) : undefined,
        };
      } catch { return null; }
    },
  });

  // Code actions — quick fixes and auto-import.
  monaco.languages.registerCodeActionProvider('dart', {
    async provideCodeActions(_model, range, context) {
      if (!_lspReady) return { actions: [], dispose() {} };
      try {
        const lspStart = range.startLineNumber - 1;
        const lspEnd   = range.endLineNumber   - 1;

        // The Dart LSP only returns "Add import" quickfixes when the request
        // range touches the identifier that has the error.  If the lightbulb
        // fires on a different line, we also query at each diagnostic's range
        // so quickfixes are always available regardless of cursor position.
        const diagRanges = _latestDiags
          .filter((d) => d.range != null)
          .map((d) => d.range!);

        const request = (lspRange: { start: LspPos; end: LspPos }) =>
          _lspSendReq('textDocument/codeAction', {
            textDocument: { uri: LSP_FILE_URI },
            range: lspRange,
            context: { diagnostics: _latestDiags },
          }).catch(() => null);

        const completionImportActions = async () => {
          const imports: Monaco.languages.CodeAction[] = [];
          const imported = new Set<string>();
          for (const diag of _latestDiags) {
            if (!diag.range || !/undefined/i.test(diag.message ?? '')) continue;
            const identifier = model.getValueInRange(lspRangeToMonaco(diag.range)).trim();
            if (!identifier || imported.has(identifier)) continue;
            const completion = await _lspSendReq('textDocument/completion', {
              textDocument: { uri: LSP_FILE_URI },
              // Ask at the end of the unresolved identifier; that is where Dart
              // returns unimported-library completions.
              position: diag.range.end,
            }).catch(() => null) as { items?: LspCompletionItem[] } | LspCompletionItem[] | null;
            const items = Array.isArray(completion) ? completion : completion?.items ?? [];
            const match = items.find((item) => item.label === identifier);
            if (!match) continue;
            const resolved = await _lspSendReq('completionItem/resolve', match)
              .catch(() => null) as LspCompletionItem | null;
            if (!resolved?.additionalTextEdits?.length) continue;
            imported.add(identifier);
            imports.push({
              title: `Add import for '${identifier}'`,
              kind: 'quickfix',
              isPreferred: true,
              edit: lspTextEditsToWorkspaceEdit(
                resolved.additionalTextEdits,
                monaco,
                model.uri,
              ),
            });
          }
          return imports;
        };

        const results = await Promise.all([
          request({ start: { line: lspStart, character: range.startColumn - 1 }, end: { line: lspEnd, character: range.endColumn - 1 } }),
          ...diagRanges.map(request),
        ]);

        // Merge and deduplicate by title.
        const seen = new Set<string>();
        const r: (LspCodeAction | { title: string; command: string; arguments?: unknown[] })[] = [];
        for (const res of results) {
          if (!Array.isArray(res)) continue;
          for (const item of res as typeof r) {
            const title = (item as LspCodeAction).title;
            if (!seen.has(title)) { seen.add(title); r.push(item); }
          }
        }

        const actions: Monaco.languages.CodeAction[] = [];
        actions.push(...await completionImportActions());
        for (const item of r) {
          const ca = item as LspCodeAction;
          if (ca.edit) {
            // Direct workspace edit (most common for "Add import").
            actions.push({
              title: ca.title,
              kind: ca.kind ?? 'quickfix',
              isPreferred: ca.isPreferred,
              edit: lspWorkspaceEditToMonaco(ca.edit, monaco, model.uri),
            });
          } else if (ca.command) {
            // Command-based action — execute it, server will push workspace/applyEdit.
            const cmd = ca.command;
            actions.push({
              title: ca.title,
              kind: ca.kind ?? 'quickfix',
              isPreferred: ca.isPreferred,
              command: {
                id: 'dart.lsp.executeCommand',
                title: ca.title,
                arguments: [cmd],
              },
            });
          }
        }

        return { actions, dispose() {} };
      } catch (e) {
        console.error('[dart_lsp] codeAction failed:', e);
        return { actions: [], dispose() {} };
      }
    },
  });
}

interface LspCompletionItem {
  label: string;
  kind?: number;
  detail?: string;
  documentation?: { kind: string; value: string } | string;
  insertText?: string;
  insertTextFormat?: number;
  textEdit?: { newText: string; range: { start: LspPos; end: LspPos } };
  additionalTextEdits?: { newText: string; range: { start: LspPos; end: LspPos } }[];
  data?: unknown;
  sortText?: string;
  filterText?: string;
}

// LSP completion kind → Monaco completion item kind
const COMP_KIND_MAP: Record<number, Monaco.languages.CompletionItemKind> = {
  1: 17, // Text
  2: 1,  // Method
  3: 1,  // Function → Method
  4: 0,  // Constructor
  5: 3,  // Field
  6: 5,  // Variable
  7: 6,  // Class
  8: 7,  // Interface
  9: 8,  // Module
  10: 9, // Property
  11: 10, // Unit
  12: 11, // Value
  13: 12, // Enum
  14: 14, // Keyword
  15: 15, // Snippet
  16: 16, // Color
  17: 16, // File
  18: 17, // Reference
};

function lspCompletionToMonaco(
  item: LspCompletionItem,
  monaco: typeof Monaco,
  fallbackRange: Monaco.IRange,
): Monaco.languages.CompletionItem {
  const range = item.textEdit?.range
    ? lspRangeToMonaco(item.textEdit.range)
    : fallbackRange;
  const insertText = item.textEdit?.newText ?? item.insertText ?? item.label;
  const doc =
    typeof item.documentation === 'string'
      ? { value: item.documentation }
      : item.documentation
        ? { value: item.documentation.value }
        : undefined;
  return {
    label: item.label,
    kind: COMP_KIND_MAP[item.kind ?? 1] ?? monaco.languages.CompletionItemKind.Text,
    detail: item.detail,
    documentation: doc,
    insertText,
    insertTextRules: item.insertTextFormat === 2
      ? monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet
      : undefined,
    range,
    additionalTextEdits: item.additionalTextEdits?.map((e) => ({
      text: e.newText,
      range: lspRangeToMonaco(e.range),
    })),
    sortText: item.sortText,
    filterText: item.filterText,
    // Store the original LSP item so resolveCompletionItem can send it back
    // verbatim — the server uses the 'data' field to locate the full item.
    _lspItem: item,
  } as Monaco.languages.CompletionItem & { _lspItem: LspCompletionItem };
}

// ── Init ──────────────────────────────────────────────────────────────────────

let _lspReady = false;
let _docVersion = 1;
let _initPromise: Promise<boolean> | null = null;

export function isLspReady(): boolean { return _lspReady; }

export function initDartLsp(
  monaco: typeof Monaco,
  model: Monaco.editor.ITextModel,
  onDiagnostics: DiagHandler,
  initialText: string,
): Promise<boolean> {
  if (_initPromise) return _initPromise;
  _diagHandler = onDiagnostics;

  _initPromise = (async () => {
    try {
      const [lspMjs, lspWasm, sdkBuf, pkgBuf] = await Promise.all([
        import(/* @vite-ignore */ `${BASE}/dart_lsp.mjs`),
        fetch(`${BASE}/dart_lsp.wasm`),
        fetch(`${BASE}/dart_sdk.sum`).then((r) => r.arrayBuffer()),
        fetch(`${BASE}/knex_dart_packages.bin`)
          .then((r) => (r.ok ? r.arrayBuffer() : new ArrayBuffer(0))),
      ]);

      const inst = await (await (lspMjs as DartLspModule).compileStreaming(lspWasm)).instantiate({});
      inst.invokeMain();

      globalThis.lspStart(new Uint8Array(sdkBuf), new Uint8Array(pkgBuf));

      // LSP initialize handshake
      await _lspSendReq('initialize', {
        processId: null,
        rootUri: 'file:///user',
        initializationOptions: {
          completionBudgetMilliseconds: 5000,
          suggestFromUnimportedLibraries: true,
          onlyAnalyzeProjectsWithOpenFiles: false,
          outline: true,
        },
        capabilities: {
          textDocument: {
            synchronization: { didOpen: true, didChange: true },
            completion: {
              completionItem: {
                snippetSupport: false,
                resolveSupport: { properties: ['additionalTextEdits', 'detail', 'documentation'] },
              },
            },
            hover: { contentFormat: ['markdown', 'plaintext'] },
            publishDiagnostics: { relatedInformation: false },
          },
          workspace: { applyEdit: true },
        },
        workspaceFolders: [{ uri: 'file:///user', name: 'user' }],
      });
      _lspNotify('initialized', {});

      // Open the virtual file — must happen before warmup completions.
      _lspNotify('textDocument/didOpen', {
        textDocument: { uri: LSP_FILE_URI, languageId: 'dart', version: _docVersion, text: initialText },
      });

      // Register the command executor for command-based code actions.
      monaco.editor.addCommand({
        id: 'dart.lsp.executeCommand',
        run: async (_accessor, cmd: { command: string; arguments?: unknown[] }) => {
          try {
            await _lspSendReq('workspace/executeCommand', {
              command: cmd.command,
              arguments: cmd.arguments ?? [],
            });
          } catch (e) {
            console.error('[dart_lsp] executeCommand failed:', e);
          }
        },
      });

      registerMonacoProviders(monaco, model);

      // Warm up the unimported-libraries index so auto-import completions are
      // ready on the first keypress.  Mirror what dart-live's index.html does.
      for (let i = 0; i < 5; i++) {
        try {
          const r = await _lspSendReq('textDocument/completion', {
            textDocument: { uri: LSP_FILE_URI },
            position: { line: 0, character: 0 },
          }) as { isIncomplete?: boolean } | null;
          if (r && (r as { isIncomplete?: boolean }).isIncomplete === false) break;
        } catch { /* ignore warmup errors */ }
        await new Promise((res) => setTimeout(res, 400));
      }

      _lspReady = true;
      return true;
    } catch (e) {
      console.error('[dart_lsp] init failed:', e);
      return false;
    }
  })();

  return _initPromise;
}

// Notify LSP server when editor content changes.
export function lspDidChange(text: string): void {
  if (!_lspReady) return;
  _docVersion += 1;
  _lspNotify('textDocument/didChange', {
    textDocument: { uri: LSP_FILE_URI, version: _docVersion },
    contentChanges: [{ text }],
  });
}
