---
title: Schema Builder
description: Create, alter, and drop tables and indexes with a fluent DDL API
---

# Schema Builder

The Schema Builder provides a fluent, dialect-aware API for defining and modifying database schema — `CREATE TABLE`, `ALTER TABLE`, `DROP TABLE`, indexes, foreign keys, and more.

All DDL is generated based on the active driver — the same code produces `serial primary key` for PostgreSQL, `int unsigned auto_increment primary key` for MySQL, and `integer primary key autoincrement` for SQLite.

## Running Schema Operations

Use `db.executeSchema()` to generate and execute DDL:

```dart
await db.executeSchema(
  db.schema.createTable('users', (t) {
    t.increments('id');
    t.string('name').notNullable();
    t.string('email').unique();
    t.boolean('active').defaultTo(true);
    t.timestamps();
  }),
);
```

---

## createTable

```dart
db.schema.createTable('posts', (t) {
  t.increments('id');
  t.integer('user_id').notNullable();
  t.string('title', 200).notNullable();
  t.text('body');
  t.boolean('published').defaultTo(false);
  t.timestamp('published_at').nullable();
  t.timestamps();
});
```

## dropTable / dropTableIfExists

```dart
db.schema.dropTable('posts');
db.schema.dropTableIfExists('posts');
```

## hasTable / hasColumn

Check existence (returns a SQL query — execute with `db.select`):

```dart
db.schema.hasTable('users');
db.schema.hasColumn('users', 'email');
```

---

## Column Types

All column methods return a `ColumnBuilder` that can be chained with modifiers.

### Numeric

| Method | PostgreSQL | MySQL | SQLite |
|---|---|---|---|
| `increments('id')` | `serial primary key` | `int unsigned auto_increment primary key` | `integer primary key autoincrement` |
| `bigIncrements('id')` | `bigserial primary key` | `bigint unsigned auto_increment primary key` | `integer primary key autoincrement` |
| `integer('col')` | `integer` | `integer` | `integer` |
| `bigInteger('col')` | `bigint` | `bigint` | `bigint` |
| `float('col')` | `real` | `float` | `float` |
| `doublePrecision('col')` | `double precision` | `double precision` | `double precision` |
| `decimal('col', 10, 2)` | `decimal(10,2)` | `decimal(10,2)` | `decimal(10,2)` |

```dart
t.increments('id');
t.integer('quantity').notNullable().defaultTo(0);
t.decimal('price', 10, 2).notNullable();
```

### String / Text

| Method | SQL Type |
|---|---|
| `string('col')` | `varchar(255)` |
| `string('col', 100)` | `varchar(100)` |
| `text('col')` | `text` |
| `uuid('col')` | `uuid` (PG) / `char(36)` (MySQL, SQLite) |

```dart
t.string('name').notNullable();
t.string('slug', 100).unique();
t.text('description').nullable();
t.uuid('external_id');
```

### Boolean

```dart
t.boolean('active').defaultTo(true);
// PG: boolean   MySQL: tinyint(1)   SQLite: boolean
```

### Date and Time

| Method | PostgreSQL | MySQL | SQLite |
|---|---|---|---|
| `date('col')` | `date` | `date` | `date` |
| `datetime('col')` | `timestamptz` | `datetime` | `datetime` |
| `timestamp('col')` | `timestamptz` | `datetime` | `datetime` |
| `time('col')` | `time` | `time` | `time` |

```dart
t.date('birth_date').nullable();
t.timestamp('created_at').notNullable();
```

### Timestamps Helper

Adds `created_at` and `updated_at` columns in one call:

```dart
t.timestamps();
// created_at timestamptz, updated_at timestamptz
```

With defaults:

```dart
t.timestamps(false, true);  // defaultToNow = true
// created_at timestamptz default CURRENT_TIMESTAMP,
// updated_at timestamptz default CURRENT_TIMESTAMP
```

### Binary and JSON

| Method | PostgreSQL | MySQL | SQLite |
|---|---|---|---|
| `binary('col')` | `bytea` | `blob` | `blob` |
| `json('col')` | `json` | `json` | `text` |
| `jsonb('col')` | `jsonb` | `json` | `text` |

```dart
t.json('metadata').nullable();
t.jsonb('settings').nullable();
```

### Enum

```dart
t.enu('status', ['pending', 'active', 'banned']);
// MySQL: enum('pending', 'active', 'banned')
// PG/SQLite: text check ("status" in ('pending', 'active', 'banned'))
```

### Raw Type

For any type not covered above:

```dart
t.specificType('geo', 'geometry(Point, 4326)');
```

---

## Column Modifiers

Every column method returns a `ColumnBuilder` — chain modifiers for constraints and defaults.

```dart
t.string('email')
  .notNullable()   // NOT NULL
  .unique()        // UNIQUE constraint
  .defaultTo('user@example.com');

t.integer('score')
  .nullable()      // NULL allowed (default)
  .defaultTo(0)
  .unsigned();     // UNSIGNED (MySQL)
```

### Inline Foreign Key

```dart
t.integer('user_id')
  .notNullable()
  .references('id')
  .inTable('users')
  .onDelete('CASCADE')
  .onUpdate('CASCADE');
```

---

## Indexes and Constraints

Add indexes and constraints at the table level (separate from column definitions):

### Index

```dart
db.schema.createTable('orders', (t) {
  t.increments('id');
  t.integer('user_id');
  t.string('status');

  t.index(['user_id']);                    // single-column index
  t.index(['user_id', 'status'], 'idx_orders_user_status'); // named index
});
```

### Unique Constraint

```dart
t.unique(['first_name', 'last_name'], 'uq_full_name');
```

### Primary Key

```dart
t.primary(['tenant_id', 'user_id']);  // composite primary key
```

### Foreign Key (table-level fluent)

```dart
t.foreign('user_id')
  .references('id')
  .inTable('users')
  .onDelete('CASCADE');
```

---

## alterTable

Modify existing tables without recreating them:

```dart
await db.executeSchema(
  db.schema.alterTable('users', (t) {
    // Add columns
    t.string('phone').nullable();
    t.boolean('verified').defaultTo(false);

    // Drop columns
    t.dropColumn('legacy_field');
    t.dropColumns(['old_field_1', 'old_field_2']);

    // Rename
    t.renameColumn('fullname', 'full_name');

    // Add index
    t.index(['phone']);

    // Drop constraints
    t.dropIndex(['phone']);
    t.dropUnique(['email']);

    // Nullability
    t.setNullable('middle_name');    // DROP NOT NULL
    t.dropNullable('email');         // SET NOT NULL
  }),
);
```

---

## Complete Example: Full Schema

```dart
// Create all tables for a simple blog

await db.executeSchema(
  db.schema.createTable('users', (t) {
    t.increments('id');
    t.string('name').notNullable();
    t.string('email').notNullable().unique();
    t.string('password_hash').notNullable();
    t.enu('role', ['admin', 'editor', 'viewer']).defaultTo('viewer');
    t.boolean('active').defaultTo(true);
    t.timestamps(false, true);
  }),
);

await db.executeSchema(
  db.schema.createTable('posts', (t) {
    t.increments('id');
    t.integer('author_id').notNullable()
      .references('id').inTable('users').onDelete('CASCADE');
    t.string('title').notNullable();
    t.string('slug', 200).notNullable().unique();
    t.text('body');
    t.enu('status', ['draft', 'published', 'archived']).defaultTo('draft');
    t.timestamp('published_at').nullable();
    t.timestamps(false, true);

    t.index(['author_id']);
    t.index(['status', 'published_at']);
  }),
);

await db.executeSchema(
  db.schema.createTable('comments', (t) {
    t.increments('id');
    t.integer('post_id').notNullable()
      .references('id').inTable('posts').onDelete('CASCADE');
    t.integer('user_id').notNullable()
      .references('id').inTable('users').onDelete('CASCADE');
    t.text('body').notNullable();
    t.timestamps(false, true);

    t.index(['post_id']);
  }),
);
```

---

## Column Type Reference

| Method | Arguments | Notes |
|---|---|---|
| `increments(col)` | — | Auto PK |
| `bigIncrements(col)` | — | Big auto PK |
| `integer(col)` | — | |
| `bigInteger(col)` | — | |
| `float(col)` | — | |
| `doublePrecision(col)` | — | |
| `decimal(col, precision, scale)` | `(8, 2)` defaults | |
| `string(col, length?)` | `255` default | VARCHAR |
| `text(col)` | — | |
| `uuid(col)` | — | |
| `boolean(col)` | — | |
| `date(col)` | — | |
| `datetime(col)` | — | |
| `timestamp(col)` | — | |
| `time(col)` | — | |
| `binary(col)` | — | |
| `json(col)` | — | |
| `jsonb(col)` | — | PG native jsonb |
| `enu(col, values)` | `List<String>` | |
| `specificType(col, type)` | raw SQL type | Escape hatch |
| `timestamps()` | `(useCamelCase, defaultToNow)` | Adds created_at + updated_at |

## Next Steps

- [Write Operations](/query-building/write-operations) — INSERT, UPDATE, DELETE
- [Transactions](/query-building/transactions) — Wrap DDL + DML in a transaction
- [Database Support](/database-support) — Dialect differences
