import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

void main() {
  group('EncryptHelper - convertPinToSecretKey', () {
    test('converts a PIN to a 32-char hex secret key', () {
      final key = EncryptHelper.convertPinToSecretKey('27272');
      expect(key, equals('98b02a2f02a3b6e383a985e0f8a5b93c'));
    });

    test('different PIN produces different key', () {
      final key1 = EncryptHelper.convertPinToSecretKey('11111');
      final key2 = EncryptHelper.convertPinToSecretKey('22222');
      expect(key1, isNot(equals(key2)));
    });
  });

  group('EncryptHelper - generateSecretKey', () {
    test('generates a 32-character hex string without dashes', () {
      final key = EncryptHelper.generateSecretKey();
      expect(key.length, 32);
      expect(key, contains(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('generates different keys on each call', () {
      final key1 = EncryptHelper.generateSecretKey();
      final key2 = EncryptHelper.generateSecretKey();
      expect(key1, isNot(equals(key2)));
    });
  });

  group('EncryptHelper - encrypt/decrypt field data', () {
    setUp(() {
      EncryptHelper.secretKey =
          EncryptHelper.convertPinToSecretKey('27272');
    });

    test('encrypt/decrypt round-trip', () {
      const sourceString = 'supercalifragilistichespiralidoso';
      final encryptedString = EncryptHelper.encrypt(sourceString);
      expect(
          encryptedString,
          equals(
              'h195oy843J6Vo5Ww5t5E0fssrrAuRYpmwSpelPLWdWRVVzMaKOKiezwQmrAjZLMQ'));
      final decryptedString = EncryptHelper.decrypt(encryptedString);
      expect(decryptedString, equals(sourceString));
    });

    test('decrypt known value', () {
      const encryptedString =
          'nF59ti5hkt2LspD/+NhdzP06ov0lT5Q56BVQjPTAaWdVKkh2SIDkAFJz/N4ob7gb';
      final decryptedString = EncryptHelper.decrypt(encryptedString);
      expect(decryptedString,
          equals('https://www.youtube.com/@MotorsportcomItalia'));
    });

    test('encrypt returns null for null input', () {
      expect(EncryptHelper.encrypt(null), isNull);
    });

    test('encrypt returns empty for empty input', () {
      expect(EncryptHelper.encrypt(''), equals(''));
    });

    test('decrypt returns null for null input', () {
      expect(EncryptHelper.decrypt(null), isNull);
    });

    test('decrypt returns empty for empty input', () {
      expect(EncryptHelper.decrypt(''), equals(''));
    });
  });

  group('EncryptHelper - password encryption', () {
    test('encryptPassword wraps with {AES} prefix', () {
      final encrypted = EncryptHelper.encryptPassword('my_password');
      expect(encrypted, startsWith('{AES}'));
      expect(encrypted!.length, greaterThan('{AES}'.length));
    });

    test('round-trip password encrypt/decrypt', () {
      const password = 'my_secret_password_123';
      final encrypted = EncryptHelper.encryptPassword(password);
      final decrypted = EncryptHelper.decryptPassword(encrypted);
      expect(decrypted, equals(password));
    });

    test('decryptPassword handles plaintext (legacy) without {AES} prefix', () {
      const plaintext = 'plain_password';
      final decrypted = EncryptHelper.decryptPassword(plaintext);
      expect(decrypted, equals(plaintext));
    });

    test('encryptPassword returns null for null input', () {
      expect(EncryptHelper.encryptPassword(null), isNull);
    });

    test('encryptPassword returns empty for empty input', () {
      expect(EncryptHelper.encryptPassword(''), equals(''));
    });
  });
}
