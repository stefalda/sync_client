import 'package:sync_client/src/api/models/user_registration.dart';
import 'package:test/test.dart';

void main() {
  group('UserRegistration', () {
    test('toMap includes all fields for new registration', () {
      final reg = UserRegistration()
        ..name = 'John'
        ..email = 'john@test.com'
        ..password = 'secret'
        ..clientId = 'client-1'
        ..clientDescription = '{"name":"iPhone"}'
        ..newRegistration = true
        ..deleteRemoteData = false
        ..language = 'en';
      final map = reg.toMap();
      expect(map['name'], equals('John'));
      expect(map['email'], equals('john@test.com'));
      expect(map['password'], equals('secret'));
      expect(map['clientId'], equals('client-1'));
      expect(map['clientDescription'], equals('{"name":"iPhone"}'));
      expect(map['newRegistration'], isTrue);
      expect(map['deleteRemoteData'], isFalse);
      expect(map['language'], equals('en'));
    });

    test('toMap includes all fields for unregister', () {
      final reg = UserRegistration()
        ..email = 'john@test.com'
        ..password = 'secret'
        ..clientId = 'client-1'
        ..deleteRemoteData = true;
      final map = reg.toMap();
      expect(map['email'], equals('john@test.com'));
      expect(map['password'], equals('secret'));
      expect(map['clientId'], equals('client-1'));
      expect(map['deleteRemoteData'], isTrue);
    });

    test('default newRegistration is false', () {
      final reg = UserRegistration();
      expect(reg.newRegistration, isFalse);
    });

    test('default deleteRemoteData is false', () {
      final reg = UserRegistration();
      expect(reg.deleteRemoteData, isFalse);
    });
  });
}
