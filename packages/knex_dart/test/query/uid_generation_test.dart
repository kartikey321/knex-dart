import 'package:knex_dart/knex_dart.dart';
import 'package:test/test.dart';

import '../mocks/mock_client.dart';

void main() {
  group('compiled SQL uid generation', () {
    test('QueryCompiler generates monotonic JS-safe query ids', () {
      final knex = KnexQuery.forDialect(KnexDialect.sqlite);

      final first = knex.from('users').select(['id']).toSQL().uid;
      final second = knex.from('users').select(['name']).toSQL().uid;

      expect(first, matches(RegExp(r'^q[0-9a-f]{8}$')));
      expect(second, matches(RegExp(r'^q[0-9a-f]{8}$')));
      expect(_uidValue(second!), greaterThan(_uidValue(first!)));
    });

    test('Raw generates monotonic JS-safe raw ids', () {
      final client = MockClient();

      final first = Raw(client).set('select 1').toSQL().uid;
      final second = Raw(client).set('select 2').toSQL().uid;

      expect(first, matches(RegExp(r'^r[0-9a-f]{8}$')));
      expect(second, matches(RegExp(r'^r[0-9a-f]{8}$')));
      expect(_uidValue(second!), greaterThan(_uidValue(first!)));
    });
  });
}

int _uidValue(String uid) => int.parse(uid.substring(1), radix: 16);
