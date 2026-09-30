/// QueryBuilder.execute()/then are deprecated, never-implemented stubs.
///
/// On most drivers, a QueryBuilder returned by a driver wrapper's
/// `db('table')` / `db.queryBuilder()` is bound to a dialect-only client
/// used for SQL compilation, not the driver's real executing client (SQLite
/// is the exception: it binds to its real executing client, see the SQLite
/// driver's own test). Either way, both members are unconditional stubs
/// with no working generic implementation. These tests pin down that both
/// still throw `UnimplementedError`, so a future accidental "fix" that
/// silently starts returning wrong/empty results doesn't slip through.
library;

// ignore_for_file: deprecated_member_use

import 'package:test/test.dart';
import '../mocks/mock_client.dart';

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  group('QueryBuilder.execute()/then (deprecated stub)', () {
    test('execute() throws UnimplementedError', () {
      final qb = client.queryBuilder().table('users').select(['id']);
      expect(() => qb.execute(), throwsA(isA<UnimplementedError>()));
    });

    test('then throws UnimplementedError', () {
      final qb = client.queryBuilder().table('users').select(['id']);
      expect(() => qb.then, throwsA(isA<UnimplementedError>()));
    });
  });
}
