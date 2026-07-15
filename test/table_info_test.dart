import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

void main() {
  group('TableInfo', () {
    test('stores keyField', () {
      final info = TableInfo(keyField: 'rowguid');
      expect(info.keyField, equals('rowguid'));
    });

    test('binaryFields defaults to empty list', () {
      final info = TableInfo(keyField: 'id');
      expect(info.binaryFields, isEmpty);
    });

    test('encryptedFields defaults to empty list', () {
      final info = TableInfo(keyField: 'guid');
      expect(info.encryptedFields, isEmpty);
    });

    test('aliasesFields defaults to empty map', () {
      final info = TableInfo(keyField: 'pk');
      expect(info.aliasesFields, isEmpty);
    });

    test('stores all fields', () {
      final info = TableInfo(
        keyField: 'uuid',
        binaryFields: ['data', 'image'],
        encryptedFields: ['secret'],
        aliasesFields: {'old_name': 'new_name'},
      );
      expect(info.keyField, equals('uuid'));
      expect(info.binaryFields, containsAll(['data', 'image']));
      expect(info.encryptedFields, containsAll(['secret']));
      expect(info.aliasesFields, containsPair('old_name', 'new_name'));
    });
  });
}
