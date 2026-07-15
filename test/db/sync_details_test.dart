import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

void main() {
  group('SyncDetails (db)', () {
    test('fromDB parses all fields', () {
      // Generate a real encrypted password
      final encryptedPassword =
          EncryptHelper.encryptPassword('encrypted_password')!;
      final row = {
        'name': 'Test User',
        'clientid': 'client-1',
        'useremail': 'user@test.com',
        'userpassword': encryptedPassword,
        'lastsync': 1700000000000,
        'accesstoken': 'token-123',
        'refreshtoken': 'refresh-456',
        'accesstokenexpiration': 1700100000000,
      };
      final details = SyncDetails.fromDB(row);
      expect(details.name, equals('Test User'));
      expect(details.clientid, equals('client-1'));
      expect(details.useremail, equals('user@test.com'));
      expect(details.userpassword, equals('encrypted_password'));
      expect(details.lastsync,
          equals(DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true)));
      expect(details.accessToken, equals('token-123'));
      expect(details.refreshToken, equals('refresh-456'));
      expect(details.accessTokenExpiration,
          equals(DateTime.fromMillisecondsSinceEpoch(1700100000000, isUtc: true)));
    });

    test('fromDB handles plaintext password (legacy)', () {
      final row = {
        'name': null,
        'clientid': 'client-2',
        'useremail': 'user@test.com',
        'userpassword': 'plain_password',
        'lastsync': 0,
      };
      final details = SyncDetails.fromDB(row);
      expect(details.userpassword, equals('plain_password'));
    });

    test('fromDB handles null lastSync', () {
      final row = {
        'name': null,
        'clientid': 'client-3',
        'useremail': 'user@test.com',
        'userpassword': 'pwd',
        'lastsync': null,
      };
      final details = SyncDetails.fromDB(row);
      expect(details.lastsync,
          equals(DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)));
    });

    test('fromDB handles null accessTokenExpiration', () {
      final row = {
        'name': null,
        'clientid': 'client-4',
        'useremail': 'user@test.com',
        'userpassword': 'pwd',
        'lastsync': 0,
        'accesstokenexpiration': null,
      };
      final details = SyncDetails.fromDB(row);
      expect(details.accessTokenExpiration, isNull);
    });

    test('toMap applies EncryptHelper.encryptPassword', () {
      // Set up the secret key so encryption works
      EncryptHelper.secretKey = EncryptHelper.convertPinToSecretKey('27272');

      final details = SyncDetails(
        clientid: 'client-5',
        useremail: 'user@test.com',
        userpassword: 'my_password',
        lastsync: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      final map = details.toMap();
      expect(map['clientid'], equals('client-5'));
      expect(map['useremail'], equals('user@test.com'));
      expect(map['userpassword'], startsWith('{AES}'));
      expect(map['accesstoken'], isNull);
      expect(map['refreshtoken'], isNull);
      expect(map['accesstokenexpiration'], isNull);
    });
  });
}
