import type { LintRequest, LintResponse, PlaygroundDiagnostic } from './types';

const worker = new Worker(new URL('./worker.ts', import.meta.url), {
  type: 'module',
});

let pending:
  | {
      resolve: (diagnostics: PlaygroundDiagnostic[]) => void;
      reject: (error: unknown) => void;
    }
  | undefined;

worker.onmessage = (event: MessageEvent<LintResponse>) => {
  if (!pending) return;
  pending.resolve(event.data.diagnostics);
  pending = undefined;
};

worker.onerror = (error) => {
  if (!pending) return;
  pending.reject(error);
  pending = undefined;
};

export function lintInWorker(request: LintRequest): Promise<PlaygroundDiagnostic[]> {
  return new Promise((resolve, reject) => {
    pending = { resolve, reject };
    worker.postMessage(request);
  });
}
