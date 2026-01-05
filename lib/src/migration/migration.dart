// Placeholder stub for Migration
// Full implementation in Week 14-15

abstract class Migration {
  Future<void> up(dynamic knex);
  Future<void> down(dynamic knex);
}
