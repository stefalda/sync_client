import 'package:encrypt/encrypt.dart';
import 'package:uuid/uuid.dart';
import 'package:uuid/uuid_util.dart';

/// Allow to encrypt/decrypt data before
/// encodingKey MUST be set before using the class
class EncryptHelper {
  static Key? _key;
  static Encrypter? _encrypter;
  static final iv = IV.fromLength(16);

  static String? secretKey;

  static Key _getKey() {
    if (_key != null) return _key!;
    // secretKey MUST BE VALORIZED before encrypting/decrypting
    assert(secretKey != null,
        "The secretKey for encryption/decryption MUST BE CONFIGURED");
    _key = Key.fromUtf8(secretKey!);
    return _key!;
  }

  static Encrypter _getEncrypter() {
    if (_encrypter != null) return _encrypter!;
    _encrypter = Encrypter(AES(_getKey()));
    return _encrypter!;
  }

  static String? encrypt(String? sourceString) {
    if (sourceString == null || sourceString == "") return sourceString;
    final encrypted = _getEncrypter().encrypt(sourceString, iv: iv);
    return encrypted.base64;
  }

  static String? decrypt(String? encryptedString) {
    if (encryptedString == null || encryptedString == "")
      return encryptedString;
    final Encrypted encrypted = Encrypted.fromBase64(encryptedString);
    return _getEncrypter().decrypt(encrypted, iv: iv);
  }

  /// Returns a new AES key to be used to encode/decode
  static String generateSecretKey() {
    return Uuid(options: {'rng': UuidUtil.cryptoRNG}).v4().replaceAll('-', '');
  }
}
