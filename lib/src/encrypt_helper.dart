import 'dart:convert';

import 'package:crypto/crypto.dart'; // Used to encode pin and geneerate a secret key
import 'package:encrypt/encrypt.dart';
import 'package:uuid/data.dart';
import 'package:uuid/rng.dart';
import 'package:uuid/uuid.dart';

/// Allow to encrypt/decrypt data before
/// encodingKey MUST be set before using the class
///
/// If no field is marked as encrypted in the TableInfo data
/// no encryption is applied
///
class EncryptHelper {
  static Key? _key;
  static Encrypter? _encrypter;
  // Since version 5.0.2 of ecrypted
  // the behaviour of this has changed and the value became random
  // so it breaks existing coding
  //static final iv = IV.fromLength(16);
  static final iv = IV.allZerosOfLength(16);
  static String? secretKey;

  /// Encrypt a value by using the secret key stored in the DB
  static String? encrypt(String? sourceString) {
    if (sourceString == null || sourceString == "") return sourceString;
    final encrypted = _getEncrypter().encrypt(sourceString, iv: iv);
    return encrypted.base64;
  }

  /// Decrypt a value by using the secret key stored in the DB
  static String? decrypt(String? encryptedString) {
    if (encryptedString == null || encryptedString == "") {
      return encryptedString;
    }
    final Encrypted encrypted = Encrypted.fromBase64(encryptedString);
    return _getEncrypter().decrypt(encrypted, iv: iv);
  }

  /// Returns a new AES key to be used to encode/decode
  static String generateSecretKey() {
    final uuid = Uuid();
    final String v4Crypto = uuid.v4(config: V4Options(null, CryptoRNG()));
    return v4Crypto.replaceAll('-', '');
  }

  /// Simplify the creation of a secret key by generating one starting from a PIN
  static String convertPinToSecretKey(String pin) {
    Digest hash = sha256.convert(utf8.encode(pin));
    // print("PIN $pin - ${hash.toString()}");
    return hash.toString().substring(0, 32);
  }

  /// Return the secret key, check if it's been set or throws an Exception
  /// if the secretKey is missing
  static Key _getKey() {
    if (_key != null) return _key!;
    // secretKey MUST BE VALORIZED before encrypting/decrypting
    assert(secretKey != null && secretKey!.isNotEmpty,
        "The secretKey for encryption/decryption MUST BE CONFIGURED");
    _key = Key.fromUtf8(secretKey!);
    return _key!;
  }

  static const String _passwordPrefix = '{AES}';
  static Key? _passwordKey;
  static Encrypter? _passwordEncrypter;

  static Key _getPasswordKey() {
    if (_passwordKey != null) return _passwordKey!;
    final keyString = convertPinToSecretKey('sync_client_password_v1');
    _passwordKey = Key.fromUtf8(keyString);
    return _passwordKey!;
  }

  static Encrypter _getPasswordEncrypter() {
    if (_passwordEncrypter != null) return _passwordEncrypter!;
    _passwordEncrypter = Encrypter(AES(_getPasswordKey()));
    return _passwordEncrypter!;
  }

  /// Encrypt a password with {AES} prefix marker.
  /// No prefix means plaintext (backward compatible).
  /// Uses a dedicated key independent of the field-encryption secretKey.
  static String? encryptPassword(String? password) {
    if (password == null || password.isEmpty) return password;
    final encrypted = _getPasswordEncrypter().encrypt(password, iv: iv);
    return '$_passwordPrefix${encrypted.base64}';
  }

  /// Decrypt a password that may have {AES} prefix marker.
  /// No prefix means plaintext (legacy data).
  static String? decryptPassword(String? password) {
    if (password == null || password.isEmpty) return password;
    if (!password.startsWith(_passwordPrefix)) return password;
    final encrypted = Encrypted.fromBase64(password.substring(_passwordPrefix.length));
    return _getPasswordEncrypter().decrypt(encrypted, iv: iv);
  }

  /// Return the Encrypter and initialize it with the secret key
  static Encrypter _getEncrypter() {
    if (_encrypter != null) return _encrypter!;
    _encrypter = Encrypter(AES(_getKey()));
    return _encrypter!;
  }
}
