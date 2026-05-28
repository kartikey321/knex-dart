/// <reference lib="webworker" />

import { runBrowserLint } from './rules';
import type { LintRequest, LintResponse } from './types';

self.onmessage = (event: MessageEvent<LintRequest>) => {
  const diagnostics = runBrowserLint(event.data);
  const response: LintResponse = { diagnostics };
  self.postMessage(response);
};
