import 'package:sync_client/src/api/models/password_change.dart';
import 'package:test/test.dart';

void main() {
  group('PasswordChange', () {
    test('toMap includes email, password, and pin', () {
      final change = PasswordChange(
        email: 'user@test.com',
        password: 'new_password',
        pin: '123456',
      );
      final map = change.toMap();
      expect(map['email'], equals('user@test.com'));
      expect(map['password'], equals('new_password'));
      expect(map['pin'], equals('123456'));
    });
  });
}
