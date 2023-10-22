import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests', () {
    //final SyncClient syncClient = SyncClient();

    // syncClient.register(email, password, dbName: "");

    setUp(() {
      // Additional setup goes here.
    });

    test('Encrypt key from pin Test', () {
      final key = EncryptHelper.convertPinToSecretKey("27272");
      expect(key, equals("98b02a2f02a3b6e383a985e0f8a5b93c"));
    });

    test('Encrypt/Decrypt value "supercalifragilistichespiralidoso"', () {
      final String sourceString = "supercalifragilistichespiralidoso";
      EncryptHelper.secretKey = EncryptHelper.convertPinToSecretKey("27272");
      final String? encryptedString = EncryptHelper.encrypt(sourceString);
      print(encryptedString);

      expect(
          encryptedString,
          equals(
              "h195oy843J6Vo5Ww5t5E0fssrrAuRYpmwSpelPLWdWRVVzMaKOKiezwQmrAjZLMQ"));
      final decryptedString = EncryptHelper.decrypt(encryptedString);
      expect(decryptedString, equals(sourceString));
    });

    test('Decrypt value', () {
      final encryptedString =
          "nF59ti5hkt2LspD/+NhdzP06ov0lT5Q56BVQjPTAaWdVKkh2SIDkAFJz/N4ob7gb";

      // Set the secret key
      EncryptHelper.secretKey = EncryptHelper.convertPinToSecretKey("27272");
      final decryptedString = EncryptHelper.decrypt(encryptedString);
      expect(decryptedString,
          equals("https://www.youtube.com/@MotorsportcomItalia"));
    });
  });
}
