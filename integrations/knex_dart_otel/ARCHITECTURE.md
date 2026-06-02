# knex_dart_otel Architecture

This document explains how OpenTelemetry instrumentation works in
`knex_dart`, what it measures, and how query execution flows through the
instrumentation layer.

The implementation is split into two packages:

- `packages/knex_dart` defines the generic interceptor pipeline and execution
  metadata types. This package has no OpenTelemetry dependency.
- `integrations/knex_dart_otel` provides `KnexOtelInterceptor`, an implementation
  of `QueryInterceptor` that creates OpenTelemetry spans and records database
  client duration metrics.

## Design Goals

- Keep the core query builder independent from OpenTelemetry SDKs and exporters.
- Let applications attach instrumentation through driver wrapper constructors.
- Preserve the active async context so DB spans are children of the current
  request span.
- Add effectively zero instrumentation overhead when no interceptors are
  configured.
- Cover normal queries, raw SQL, schema execution, streaming queries,
  transactions, D1 batch execution, and explicit non-SQL operations where the
  driver exposes them.

## Public Setup

Applications create a tracer using their OpenTelemetry setup and pass the
interceptor into a driver wrapper:

```dart
import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';
import 'package:knex_dart_otel/knex_dart_otel.dart';
import 'package:knex_dart_postgres/knex_dart_postgres.dart';

final tracer = OTelAPI.tracerProvider().getTracer(
  'my-service',
  version: '1.0.0',
);

final db = await KnexPostgres.connect(
  host: 'localhost',
  port: 5432,
  database: 'myapp',
  username: 'user',
  password: 'pass',
  interceptors: [
    KnexOtelInterceptor(tracer: tracer),
  ],
);
```

`KnexOtelInterceptor` depends on `dartastic_opentelemetry_api`, not a concrete
SDK or exporter. The application remains responsible for installing and
configuring the actual OpenTelemetry SDK.

Important: initialize the OpenTelemetry SDK before constructing
`KnexOtelInterceptor`. The default histogram is created lazily and cached. If
it is created before a real SDK is installed, it may be bound to a no-op meter
provider. Pass `operationDurationHistogram` explicitly if you need exact
provider control.

## Core Architecture

### QueryInterceptor

Core package file:

```text
packages/knex_dart/lib/src/client/query_interceptor.dart
```

`QueryInterceptor` is the extension point:

```dart
abstract class QueryInterceptor {
  Future<T> intercept<T>(
    QueryExecutionContext ctx,
    Future<T> Function() next,
  );

  Stream<T> interceptStream<T>(
    QueryExecutionContext ctx,
    Stream<T> Function() next,
  ) => next();
}
```

Future-based operations use `intercept`. Stream-based operations use
`interceptStream` so the interceptor can bind span lifetime to stream
completion, stream error, or subscriber cancellation.

### QueryExecutionContext

Every intercepted operation is described by `QueryExecutionContext`.

Fields:

- `dbSystem`: OpenTelemetry `db.system.name`, for example `postgresql`,
  `mysql`, `sqlite`, `duckdb`, `mssql`, or other driver-specific values.
- `database`: OpenTelemetry `db.namespace`, when known.
- `serverAddress`: OpenTelemetry `server.address`, when known.
- `serverPort`: OpenTelemetry `server.port`, when known.
- `sql`: parameterized SQL text, used as `db.query.text` when query-text
  capture is enabled.
- `parameters`: bound parameters. These are not recorded by default.
- `operationName`: canonical SQL operation name, used as
  `db.operation.name`.
- `collectionName`: primary table/collection name, used as
  `db.collection.name` when safely known.
- `querySummary`: low-cardinality span name, usually `SELECT users`,
  `INSERT orders`, or just `SELECT` for raw SQL.
- `txId`: transaction identifier for operations executed inside a
  `KnexTransaction` facade.

### KnexInterceptorPipeline

Every instrumented driver wrapper owns a `KnexInterceptorPipeline`. The
pipeline stores connection-level metadata and an ordered list of interceptors.

Supported pipeline entry points:

- `run(query, execute, txId: ...)` for `QueryBuilder` operations.
- `runRaw(sql, parameters, execute, txId: ...)` for raw SQL execution.
- `runStream(query, execute, txId: ...)` for streaming query results.
- `runOperation(...)` for explicit non-standard operations, such as Snowflake
  async result polling.
- `runBatch(execute)` for batch-style drivers such as Cloudflare D1.

When `interceptors` is empty, each method immediately calls `execute()` or
returns the source stream. This is the no-op fast path.

When interceptors are present, the pipeline builds a `QueryExecutionContext`
and calls interceptors in list order. Each interceptor receives a `next`
function that invokes the next interceptor or the real driver execution.

The future chain is:

```text
driver wrapper method
  -> KnexInterceptorPipeline.run/runRaw/runOperation/runBatch
    -> interceptor[0].intercept(ctx, next)
      -> interceptor[1].intercept(ctx, next)
        -> real driver query execution
```

The stream chain is:

```text
driver wrapper stream method
  -> KnexInterceptorPipeline.runStream
    -> interceptor[0].interceptStream(ctx, next)
      -> interceptor[1].interceptStream(ctx, next)
        -> real driver stream
```

## How Operation Metadata Is Derived

### QueryBuilder Operations

For `QueryBuilder` operations, the pipeline compiles the query with
`query.toSQL()` and maps `query.method` through `queryMethodToSqlOperation`.

Current mapping:

- `select` -> `SELECT`
- `insert` -> `INSERT`
- `update` -> `UPDATE`
- `delete` -> `DELETE`
- `truncate` -> `TRUNCATE`
- `first` -> `SELECT`
- `pluck` -> `SELECT`

The primary table is read from `query.tableName`. This returns a string only
when the builder has a simple string table source. For subquery `FROM`, raw
queries, or unset tables, `collectionName` is null to avoid high-cardinality or
unsafe collection names.

### Raw SQL

For `rawSql`, the pipeline derives the operation through
`sqlOperationFromRaw(sql)`.

The parser:

- strips leading block comments (`/* ... */`)
- strips leading line comments (`-- ...`)
- trims leading whitespace
- matches known SQL verbs with a word-boundary check

Recognized raw operations:

- `SELECT`
- `INSERT`
- `UPDATE`
- `DELETE`
- `CREATE`
- `DROP`
- `ALTER`
- `TRUNCATE`
- `BEGIN`
- `COMMIT`
- `ROLLBACK`
- `SAVEPOINT`
- `MERGE`

Unknown raw SQL is reported as `DB`.

### Explicit Operations

Some driver operations are not normal SQL statements. For these, drivers can
use `runOperation` and provide the operation name directly. Snowflake async
result polling uses:

```text
operationName: GET_ASYNC_RESULT
querySummary: GET_ASYNC_RESULT
queryText: <snowflake async result>
```

The statement handle is intentionally not included in `db.query.text` to avoid
high-cardinality attributes.

### Batch Operations

D1 batches are reported as a single operation:

```text
operationName: BATCH
querySummary: BATCH
sql: <batch>
```

Individual statements are buffered by the D1 API and executed server-side as a
unit, so the current instrumentation reports one batch span rather than
per-statement spans.

## What KnexOtelInterceptor Measures

`KnexOtelInterceptor` records two things:

1. A client span for every intercepted operation.
2. A `db.client.operation.duration` histogram measurement for every
   intercepted operation.

### Spans

The span is created with:

```dart
_tracer.startSpan(ctx.querySummary, kind: SpanKind.client);
```

The span name is `QueryExecutionContext.querySummary`.

Examples:

- `SELECT users`
- `INSERT orders`
- `UPDATE accounts`
- `CREATE`
- `BATCH`
- `GET_ASYNC_RESULT`

Base span attributes:

- `db.system.name`: from `ctx.dbSystem`
- `db.operation.name`: from `ctx.operationName`
- `db.namespace`: from `ctx.database`, when not null
- `db.collection.name`: from `ctx.collectionName`, when not null
- `db.query.text`: parameterized SQL, when `captureQueryText` is true
- `server.address`: from `ctx.serverAddress`, when not null
- `server.port`: from `ctx.serverPort`, when not null

On success:

- Status is set to `SpanStatusCode.Ok`.
- `responseHook` receives `KnexOtelResult(isError: false, elapsed: ..., rowCount: ...)`.
- `rowCount` is set when the result is a `List`; otherwise it is null.
- Duration metric is recorded.
- Span is ended.

On error:

- `span.recordException(error, stackTrace: stackTrace)` is called.
- `error.type` is set to `error.runtimeType.toString()`.
- Status is set to `SpanStatusCode.Error`.
- `responseHook` receives `KnexOtelResult(isError: true, error: ..., stackTrace: ..., elapsed: ...)`.
- Duration metric is recorded.
- Span is ended.
- The original error is rethrown.

Hook errors are swallowed. Observability must not break database execution.

### Context Propagation

For future-based operations, `KnexOtelInterceptor.intercept` calls:

```dart
await _tracer.withSpanAsync(span, next);
```

This makes the DB span current while the real driver operation runs. Any child
spans created by lower-level code during that operation can be parented to the
DB span.

Because the interceptor is invoked synchronously from the driver wrapper method,
the span is created in the same async zone as the original user call, for
example:

```dart
await db.select(db('users').where('active', true));
```

That allows the DB span to be a child of the current request span when an
OpenTelemetry SDK is using zone-based context propagation.

### Stream Spans

`interceptStream` uses a custom `StreamController` instead of
`StreamTransformer.fromHandlers`.

Reasons:

- A stream might be created but never listened to. The span is created lazily
  in `onListen` so a never-subscribed stream cannot leak an open span.
- A subscriber can cancel before the stream reaches `done`. The controller
  handles `onCancel` and ends the span.
- Error and done paths can both occur depending on stream behavior. A
  `finishOnce` guard ensures duration is recorded and the span is ended exactly
  once.
- `onPause` and `onResume` forward to the upstream subscription.

Stream lifecycle:

```text
stream returned by driver wrapper
  -> user listens
    -> span starts
    -> real driver stream is subscribed under _tracer.withSpan(...)
    -> rows flow through
    -> normal done, error, or cancel
      -> histogram records elapsed seconds
      -> responseHook runs
      -> span ends exactly once
```

On cancellation, upstream `cancel()` is awaited before the span is finished so
the driver can release cursors or connections before the span closes.

### Histogram Metric

`KnexOtelInterceptor` records:

```text
db.client.operation.duration
```

Properties:

- type: histogram
- value unit: seconds
- value: `elapsed.inMicroseconds / Duration.microsecondsPerSecond`
- description: `Duration of database client operations.`
- default boundaries:
  - `0.001`
  - `0.005`
  - `0.01`
  - `0.05`
  - `0.1`
  - `0.5`
  - `1`
  - `5`
  - `10`

Metric attributes:

- `db.system.name`
- `db.operation.name`
- `db.namespace`, when not null
- `db.collection.name`, when not null
- `server.address`, when not null
- `server.port`, when not null

The metric intentionally does not include `db.query.text` or bound parameter
values. Those would create high-cardinality metric series.

The default histogram is shared by all `KnexOtelInterceptor` instances that do
not provide `operationDurationHistogram`. This avoids registering duplicate
default instruments for the same process.

## Options and Hooks

`KnexOtelOptions` controls span enrichment:

```dart
KnexOtelOptions({
  bool captureQueryText = true,
  int maxQueryTextLength = 1024,
  KnexOtelRequestHook? requestHook,
  KnexOtelResponseHook? responseHook,
})
```

`maxQueryTextLength` must be non-negative. Invalid values throw
`ArgumentError`, including in production builds.

`captureQueryText` controls whether `db.query.text` is set. The SQL emitted by
knex_dart is parameterized, so this does not include parameter values unless
the user embeds values manually in raw SQL.

`requestHook` runs after base span attributes are set and before execution:

```dart
requestHook: (span, ctx) {
  if (ctx.txId != null) {
    span.setStringAttribute('db.transaction.id', ctx.txId!);
  }
}
```

`responseHook` runs after execution succeeds or fails, before the span is
ended:

```dart
responseHook: (span, ctx, result) {
  if (result.rowCount != null) {
    span.setIntAttribute('db.response.row_count', result.rowCount!);
  }
}
```

The hook context type is `KnexOtelSpanContext`. It contains:

- `dbSystem`
- `database`
- `serverAddress`
- `serverPort`
- `sql`
- `operationName`
- `collectionName`
- `querySummary`
- `txId`

The response result type is `KnexOtelResult`. It contains:

- `isError`
- `error`
- `stackTrace`
- `rowCount`
- `elapsed`

## Driver Coverage

The instrumentation is attached at the driver wrapper layer, not the low-level
client layer. Driver wrappers accept `interceptors` and route execution through
`KnexInterceptorPipeline`.

Covered wrapper surfaces:

- `select`
- `execute`
- `insert`
- `update`
- `delete`
- `rawSql`
- `executeSchema`
- streaming methods such as `streamQuery` or driver-specific stream wrappers
- wrapper-level transaction facades implementing `KnexTransaction`
- D1 `batch`
- D1 simulated `trx` as one `BATCH` operation
- Snowflake `getAsyncResult` as `GET_ASYNC_RESULT`

The canonical raw execution method is `rawSql`. Some drivers keep older
aliases such as `raw` or `executeRaw`, but those aliases delegate to `rawSql`
in the wrappers where present.

## Transactions

The core transaction abstraction is `KnexTransaction`.

It exposes:

- `txId`
- `queryBuilder()`
- callable shorthand `tx([tableName])`
- `select`
- `execute`
- `insert`
- `update`
- `delete`
- `rawSql`
- `streamQuery`, where supported
- nested `trx`

Driver wrapper transaction facades route transaction queries through the same
pipeline as top-level queries and pass `txId` into the context.

Typical flow:

```text
db.trx((tx) async {
  await tx.insert(...);
})
  -> wrapper creates txId with pipeline.nextUid()
  -> transaction facade receives low-level transaction client
  -> tx.insert routes through _pipeline.run(..., txId: txId)
  -> KnexOtelInterceptor sees ctx.txId
```

Nested transactions/savepoints create child transaction identifiers. For
drivers that expose savepoint SQL through the facade, savepoint statements also
go through `rawSql` and are observable as raw operations.

SQLite handles savepoints internally in its client implementation. The
SQLite transaction facade still gives nested operations a child `txId` prefix,
but SQLite savepoint SQL itself is not emitted as a separate OTel span.

D1 transactions are simulated through its batch API. The wrapper reports the
whole simulated transaction as one `BATCH` operation rather than individual
statement spans.

## Schema Execution

`executeSchema` receives a callback that mutates a `SchemaBuilder`.

The wrapper compiles the schema builder to SQL statements and executes those
statements through the pipeline. This means schema operations are observable as
raw SQL operations such as:

- `CREATE`
- `ALTER`
- `DROP`

Example:

```dart
await db.executeSchema((schema) {
  schema.createTable('users', (table) {
    table.increments('id');
    table.string('email').notNullable();
  });
});
```

Each compiled schema statement is measured separately.

## What Is Not Measured

The following are intentionally outside the current OTel package scope:

- SQL generation-only APIs such as `KnexQuery.forDialect(...)` and
  `KnexQuery.forClient(...)`. These compile SQL but do not execute against a
  live database.
- Direct low-level client usage, such as internal `PostgresClient` or
  `SQLiteClient` objects, if used outside wrapper APIs.
- Migrations that run through the separate migrator/facade path in
  `packages/knex_dart/lib/src/migration/migration.dart`.
- Bound parameter values. They are present in `QueryExecutionContext.parameters`
  but are not recorded by `KnexOtelInterceptor` by default.
- Per-statement D1 batch spans. D1 batch execution is currently measured as one
  `BATCH` span.

If migration timing is needed today, wrap the migrator call in a manual span in
application code.

## Failure Behavior

Instrumentation must not change query behavior.

Therefore:

- `requestHook` exceptions are swallowed.
- `responseHook` exceptions are swallowed.
- Metric recording exceptions are swallowed.
- Query execution errors are recorded on the span and then rethrown unchanged.
- Stream errors are recorded on the span and forwarded to the stream consumer.
- Stream cancellation ends the span and records duration.

## Testing Strategy

The current tests cover the main contract in three layers:

- Core pipeline and SQL operation tests under `packages/knex_dart/test/interceptor/`.
- OTel interceptor span, metric, options, error, and stream lifecycle tests under
  `integrations/knex_dart_otel/test/`.
- SQLite integration tests under
  `drivers/knex_dart_sqlite/test/integration/sqlite_pipeline_test.dart`, which
  verify real wrapper routing for CRUD, raw SQL, schema execution, streams, and
  transactions.

Key cases verified by tests include:

- span status and end behavior on success
- error recording and rethrow behavior
- `db.query.text` capture and truncation
- histogram value and attributes
- stream done, stream error, and stream cancellation lifecycle
- transaction `txId` propagation
- nested transaction `txId` hierarchy
- subquery `FROM` collection-name safety
- no-interceptor fast path

## Maintenance Rules

When adding a new driver operation:

1. Route it through `KnexInterceptorPipeline` if it executes database work.
2. Use `run` for `QueryBuilder` operations.
3. Use `runRaw` for SQL strings.
4. Use `runStream` for streams.
5. Use `runOperation` for non-SQL driver operations.
6. Use `runBatch` for atomic buffered batch execution.
7. Pass `txId` for transaction-scoped operations.
8. Add or update tests proving the operation is visible to a spy interceptor.

When adding new span attributes or metric dimensions:

1. Prefer OpenTelemetry semantic convention names.
2. Avoid high-cardinality values in metrics.
3. Do not record parameter values by default.
4. Keep hook errors and metric errors isolated from query execution.
