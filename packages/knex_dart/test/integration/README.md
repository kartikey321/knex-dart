# PostgreSQL Integration Tests

Integration tests for PostgreSQL database connectivity.

## Prerequisites

1. **Docker and Docker Compose** installed
2. **PostgreSQL container** running

## Quick Start

```bash
# 1. Start PostgreSQL
cd /Users/kartik/StudioProjects/knex/knex-dart
docker-compose up -d postgres

# 2. Wait for database to be ready
docker-compose exec postgres pg_isready -U test

# 3. Run integration tests
dart test test/integration/postgres_test.dart

# 4. Stop database when done
docker-compose down
```

## What's Tested

- ✅ PostgreSQL connection
- ✅ Basic SELECT queries  
- ✅ WHERE clauses
- ✅ JOINs
- ✅ Aggregates
- ✅ Subqueries
- ✅ UNION operations
- ✅ CTEs (WITH clauses)
- ✅ ORDER BY / LIMIT
- ✅ Complex queries

## Database Schema

Test database includes:
- `users` table (5 records)
- `orders` table (7 records)
- `products` table (5 records)

See `sql/postgres_schema.sql` and `sql/postgres_seed.sql` for details.
