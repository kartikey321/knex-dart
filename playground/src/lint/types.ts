export type PlaygroundDialect = 'postgres' | 'mysql' | 'sqlite';

export type PlaygroundSeverity = 'error' | 'warning' | 'info' | 'hint';

export interface PlaygroundDiagnostic {
  code: string;
  source: string;
  message: string;
  severity: PlaygroundSeverity;
  startOffset: number;
  endOffset: number;
}

export interface LintRequest {
  text: string;
  dialect: PlaygroundDialect;
}

export interface LintResponse {
  diagnostics: PlaygroundDiagnostic[];
}
