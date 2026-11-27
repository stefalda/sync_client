// Return a valid token to make the call

import 'dart:convert';

import 'package:sync_client/src/debug_utils.dart';
import 'package:sync_client/sync_client.dart';

class AuthenticationHelper {
  final String serverUrl;
  final String realm;
  final SQLiteWrapperSyncMixin sqliteWrapperSync;
  final HttpHelper httpHelper;

  AuthenticationHelper(
      {required this.serverUrl,
      required this.realm,
      required this.sqliteWrapperSync,
      HttpHelper? customHttpHelper})
      : httpHelper = customHttpHelper ?? HttpHelper();

  /// Execute an authenticated call passing the token
  /// if the token is expired tries to renew it or
  /// if everything fails throws a UnauthorizedException
  Future<dynamic> authenticatedCall(String url, Map<String, String?>? params,
      {String? method = "GET",
      Object? body,
      lastCall = false,
      required String dbName,
      required SyncController syncController,
      isPushOrPull = false}) async {
    final token = await _getToken(dbName: dbName);
    if (token == null) {
      throw Exception('No valid token available');
    }
    try {
      return await httpHelper.call(url, params,
          body: body,
          method: method,
          isPushOrPull: isPushOrPull,
          syncController: syncController,
          additionalHeaders:
              HttpHelper.bearerAuthenticationHeader(token: token));
    } on UnauthorizedException {
      if (lastCall) {
        throw SyncException("Unauthorized exception",
            type: SyncExceptionType.reloginNeeded);
      }
      try {
        await _forceRefreshToken(dbName: dbName);
      } catch (ex) {
        // The refreshToken didn't work
        throw SyncException("Unauthorized exception",
            type: SyncExceptionType.reloginNeeded);
      }
      return await authenticatedCall(url, params,
          method: method,
          body: body,
          lastCall: true,
          dbName: dbName,
          syncController: syncController);
    } catch (ex) {
      rethrow;
    }
  }

  /// Return a token to be used in authenticated calls
  Future<String?> _getToken({required String dbName}) async {
    if (EncryptHelper.secretKey == null) {
      await sqliteWrapperSync.getSecretKey(dbName: dbName);
    }
    SyncDetails? detail = await _getTokenFromDB(dbName: dbName);
    if (detail == null) throw _missingConfiguration();
    if (detail.accessToken == null) {
      detail = await _registerForAToken(detail, dbName: dbName);
      return detail.accessToken;
    }
    // Rinnova solo se il token sta per scadere (margine di 1 minuto).
    // Prima la scadenza non veniva mai salvata e il token veniva rinnovato a
    // OGNI chiamata: con le sync paginate significava una richiesta in più per
    // ogni pagina (e il rate limit su /login è di 10 al minuto).
    // Se la scadenza è sconosciuta non si rinnova: si gestisce il 401.
    final expiration = detail.accessTokenExpiration;
    if (expiration != null &&
        DateTime.now()
            .toUtc()
            .isAfter(expiration.toUtc().subtract(const Duration(minutes: 1)))) {
      detail = await _refreshToken(detail, dbName: dbName);
    }
    return detail.accessToken;
  }

  /// Force a refresh token if the server as asked for it
  Future<void> _forceRefreshToken({required String dbName}) async {
    final detail = await _getTokenFromDB(dbName: dbName);
    if (detail == null) throw _missingConfiguration();
    await _refreshToken(detail, dbName: dbName);
  }

  /// Scadenza del token: `expires_on` (ms) se il server lo manda, altrimenti il
  /// claim `exp` del JWT (il server in modalità JWT restituisce solo i due
  /// token, senza scadenza esplicita). null = sconosciuta.
  DateTime? _expirationFromTokenData(Map<String, dynamic> tokenData) {
    final expiresOn = tokenData['expires_on'];
    if (expiresOn is num) {
      return DateTime.fromMillisecondsSinceEpoch(expiresOn.toInt(),
          isUtc: true);
    }
    final accessToken = tokenData['accessToken'] ?? tokenData['access_token'];
    final fromJwt = accessToken is String ? _expFromJwt(accessToken) : null;
    if (fromJwt != null) return fromJwt;
    final expiresIn = tokenData['expires_in'];
    if (expiresIn is num) {
      return DateTime.now().toUtc().add(Duration(seconds: expiresIn.toInt()));
    }
    return null;
  }

  /// Legge il claim `exp` (secondi) dal payload di un JWT.
  DateTime? _expFromJwt(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final decoded = jsonDecode(payload);
      if (decoded is Map && decoded['exp'] is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          (decoded['exp'] as num).toInt() * 1000,
          isUtc: true,
        );
      }
    } catch (e) {
      debugPrint("Impossibile leggere la scadenza del token: $e");
    }
    return null;
  }

  /// Legge la configurazione di sync dal DB. `null` se non esiste più (logout,
  /// reset o cancellazione durante una sync in corso): prima il cast implicito
  /// faceva esplodere il cleanup con un TypeError.
  Future<SyncDetails?> _getTokenFromDB({required String dbName}) async {
    const sql = "SELECT * FROM sync_details";
    final row = await sqliteWrapperSync.query(sql,
        singleResult: true, dbName: dbName);
    if (row == null) return null;
    return SyncDetails.fromDB(row as Map);
  }

  /// Errore pulito quando la configurazione non c'è più.
  SyncException _missingConfiguration() => SyncException(
        "Sync is not configured anymore",
        type: SyncExceptionType.syncConfigurationMissing,
      );

  // Make a call in SimpleAuthentication
  Future<SyncDetails> _registerForAToken(SyncDetails syncDetails,
      {required String dbName}) async {
    // Authorization: Basic username:password
    try {
      Map<String, dynamic> tokenData = await httpHelper.call(
        "$serverUrl/login/$realm",
        {},
        body: jsonEncode({"clientId": syncDetails.clientid}),
        additionalHeaders: HttpHelper.simpleAuthenticationHeader(
            username: syncDetails.useremail,
            password: syncDetails.userpassword),
        method: 'POST',
      );
      return await _updateSyncDetailsFromTokenData(syncDetails, tokenData,
          dbName: dbName);
    } catch (ex) {
      if (ex is UnauthorizedException) {
        throw SyncException("Unauthorized exception",
            type: SyncExceptionType.reloginNeeded);
      }
      rethrow;
    }
  }

  /// Refresh the token and persist data to the DB
  Future<SyncDetails> _refreshToken(SyncDetails syncDetails,
      {required String dbName}) async {
    try {
      Map<String, dynamic> tokenData = await httpHelper.call(
          "$serverUrl/login/$realm/refreshToken", {},
          body: jsonEncode({"refreshToken": syncDetails.refreshToken}),
          method: 'POST');
      return await _updateSyncDetailsFromTokenData(syncDetails, tokenData,
          dbName: dbName);
    } on UnauthorizedException {
      // Relogin using username and password
      debugPrint("Something went wrong with refreshToken try to relogin");
      return await _registerForAToken(syncDetails, dbName: dbName);
    }
  }

  /// Update the DB data about the token
  /// with the token info from the API
  ///  {
  ///   "token_type": "Bearer",
  ///    "access_token": accessToken,
  ///    "expires_in": expiresIn,
  ///    "expires_on": expiresOn.millisecondsSinceEpoch,
  ///    "refresh_token": refreshToken
  ///   }
  Future<SyncDetails> _updateSyncDetailsFromTokenData(
      SyncDetails syncDetails, Map<String, dynamic> tokenData,
      {required String dbName}) async {
    try {
      // BEARER Authentication returns access_tocken and refresh_token
      // JWT Authentication returns accessToken and refreshToken
      syncDetails.accessToken =
          tokenData['accessToken'] ?? tokenData['access_token'];
      syncDetails.refreshToken =
          tokenData['refreshToken'] ?? tokenData['refresh_token'];
      syncDetails.accessTokenExpiration = _expirationFromTokenData(tokenData);
      await sqliteWrapperSync.save(syncDetails.toMap(), SyncDetails.tableName,
          dbName: dbName, keys: ['clientid']);
      return syncDetails;
    } catch (ex) {
      debugPrint("Error updatingSyncDeatils: $ex");
      rethrow;
    }
  }
}
