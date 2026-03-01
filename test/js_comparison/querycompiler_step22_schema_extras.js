const knex = require('knex');

const sqlite = knex({ client: 'sqlite3', useNullAsDefault: true });
const pg = knex({ client: 'pg' });
const mysql = knex({ client: 'mysql' });
const mysql2 = knex({ client: 'mysql2' });

const queries = [
  {
    name: 'PG dropTimestamps',
    builder: pg.schema.alterTable('users', t => t.dropTimestamps()),
    expected: [
      { sql: 'alter table "users" drop column "created_at", drop column "updated_at"' }
    ]
  },
  {
    name: 'PG dropTimestamps camelCase',
    builder: pg.schema.alterTable('users', t => t.dropTimestamps(true)),
    expected: [
      { sql: 'alter table "users" drop column "createdAt", drop column "updatedAt"' }
    ]
  },
  {
    name: 'PG setNullable',
    builder: pg.schema.alterTable('users', t => t.setNullable('email')),
    expected: [
      { sql: 'alter table "users" alter column "email" drop not null' }
    ]
  },
  {
    name: 'PG dropNullable',
    builder: pg.schema.alterTable('users', t => t.dropNullable('email')),
    expected: [
      { sql: 'alter table "users" alter column "email" set not null' }
    ]
  },
  {
    name: 'PG fluent foreign',
    builder: pg.schema.alterTable('users', t => t.foreign('company_id').references('id').inTable('companies').onDelete('CASCADE').onUpdate('RESTRICT')),
    expected: [
      { sql: 'alter table "users" add constraint "users_company_id_foreign" foreign key ("company_id") references "companies" ("id") on delete CASCADE on update RESTRICT' }
    ]
  },
  {
    name: 'MYSQL dropTimestamps',
    builder: mysql.schema.alterTable('users', t => t.dropTimestamps()),
    expected: [
      { sql: 'alter table `users` drop `created_at`, drop `updated_at`' }
    ]
  },
  {
    name: 'MYSQL fluent foreign',
    builder: mysql.schema.alterTable('users', t => t.foreign('company_id').references('id').inTable('companies').onDelete('CASCADE').onUpdate('RESTRICT')),
    expected: [
      { sql: 'alter table `users` add constraint `users_company_id_foreign` foreign key (`company_id`) references `companies` (`id`) on delete CASCADE on update RESTRICT' }
    ]
  }
];

let hasErrors = false;
for (const q of queries) {
  const sql = q.builder.toSQL();
  const actualObj = sql.map(s => ({ sql: s.sql }));
  
  if (JSON.stringify(actualObj) !== JSON.stringify(q.expected)) {
    console.error(`Mismatch for: ${q.name}`);
    console.error('Expected:', q.expected);
    console.error('Actual:', actualObj);
    hasErrors = true;
  } else {
    console.log(`PASS: ${q.name}`);
  }
}

sqlite.destroy();
pg.destroy();
mysql.destroy();
mysql2.destroy();

if (hasErrors) {
  process.exit(1);
}
