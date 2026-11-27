@TestOn('vm')

import 'dart:convert';

import 'package:sync_client/sync_client.dart';
import 'package:test/test.dart';

import '../helpers/fake_http_helper.dart';
import '../helpers/test_db.dart';

/// Il token viene rinnovato solo quando scade.
///
/// Prima la scadenza non veniva mai salvata (`accessTokenExpiration` restava
/// null, il codice era commentato) e `_getToken` faceva `_refreshToken` a ogni
/// chiamata: con le sync paginate è una richiesta in più per pagina, e su
/// `/login` il server di produzione consente 10 richieste al minuto.
void main() {
  late SQLiteWrapperSync db;
  late FakeHttpHelper fakeHttp;
  late SyncRepository repository;

  final refreshRegex = RegExp(r'/login/([^/]+)/refreshToken$');

  /// JWT finto: solo il payload conta (il client ne legge il claim `exp`).
  String jwtWithExp(Duration fromNow) {
    String encode(Map<String, dynamic> value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final exp = DateTime.now().add(fromNow).millisecondsSinceEpoch ~/ 1000;
    return '${encode({'alg': 'HS256', 'typ': 'JWT'})}.'
        '${encode({'userid': 'u', 'exp': exp})}.firma';
  }

  setUp(() async {
    db = await openInMemoryDb();
    fakeHttp = FakeHttpHelper();
    repository = SyncRepository(
      sqliteWrapperSync: db,
      serverUrl: 'http://localhost:8076',
      realm: 'TEST_REALM',
      customHttpHelper: fakeHttp,
    );
    await repository.register(
      name: 'Test User',
      email: 'test@test.com',
      password: 'test',
      deviceInfo: '{"name":"TEST"}',
      newRegistration: true,
      language: 'en',
      secretKey: '',
      dbName: 'test',
    );
    fakeHttp.clearCalls();
  });

  int refreshCalls() =>
      fakeHttp.calledUrls.where((u) => u.contains('/refreshToken')).length;

  test('token non scaduto: nessun refresh, una sola login', () async {
    // Il default del fake: expires_on = adesso + 1 giorno.
    await repository.sync(dbName: 'test');

    expect(refreshCalls(), 0);
    expect(
      fakeHttp.calledUrls.where((u) => u.contains('/login/')).length,
      1,
      reason: 'una sola login per ottenere il token',
    );
  });

  test('token scaduto: un refresh e poi le chiamate riusano il nuovo token',
      () async {
    fakeHttp.setResponse(RegExp(r'/login/([^/]+)$'), {
      'accessToken': jwtWithExp(const Duration(minutes: -5)),
      'refreshToken': 'refresh_1',
      'expires_on': DateTime.now()
          .subtract(const Duration(minutes: 5))
          .millisecondsSinceEpoch,
    });
    fakeHttp.setResponse(RegExp(r'/login/([^/]+)/refreshToken$'), {
      'accessToken': jwtWithExp(const Duration(hours: 1)),
      'refreshToken': 'refresh_2',
      'expires_on':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    });

    await repository.sync(dbName: 'test');

    // Un solo refresh: dopo il rinnovo il token è valido per tutte le chiamate
    // della sync (pull + push).
    expect(refreshCalls(), 1);
  });

  test('scadenza letta dal claim exp quando il server non manda expires_on',
      () async {
    // Caso del server in modalità JWT: solo accessToken/refreshToken.
    fakeHttp.setResponse(RegExp(r'/login/([^/]+)$'), {
      'accessToken': jwtWithExp(const Duration(hours: 2)),
      'refreshToken': 'refresh_1',
    });

    await repository.sync(dbName: 'test');

    expect(refreshCalls(), 0);
  });

  test('JWT scaduto senza expires_on: refresh', () async {
    fakeHttp.setResponse(RegExp(r'/login/([^/]+)$'), {
      'accessToken': jwtWithExp(const Duration(minutes: -1)),
      'refreshToken': 'refresh_1',
    });
    fakeHttp.setResponse(RegExp(r'/login/([^/]+)/refreshToken$'), {
      'accessToken': jwtWithExp(const Duration(hours: 1)),
      'refreshToken': 'refresh_2',
    });

    await repository.sync(dbName: 'test');

    expect(refreshCalls(), 1);
  });
}
