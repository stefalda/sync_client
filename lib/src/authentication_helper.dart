// Return a valid token to make the call

import 'dart:convert';

import 'package:sqlite_wrapper/sqlite_wrapper.dart';
import 'package:sync_client/src/debug_utils.dart';
import 'package:sync_client/sync_client.dart';

class AuthenticationHelper {
  final String dbName;
  final String serverUrl;
  final String realm;

  AuthenticationHelper(
      {required this.dbName, required this.serverUrl, required this.realm});

  /// Execute an authenticated call passing the token
  /// if the token is expired tries to renew it or
  /// if everything fails throws a UnauthorizedException
  Future<dynamic> authenticatedCall(String url, Map<String, String?>? params,
      {String? method = "GET", Object? body, lastCall = false}) async {
    final token = await _getToken();
    try {
      return await HttpHelper.call(url, params,
          body: body,
          method: method,
          additionalHeaders:
              HttpHelper.bearerAuthenticationHeader(token: token!));
    } on UnauthorizedException {
      if (lastCall) {
        throw SyncException("Unauthorized exception",
            type: SyncExceptionType.reloginNeeded);
      }
      try {
        await _forceRefreshToken();
      } catch (ex) {
        // The refreshToken didn't work
        throw throw SyncException("Unauthorized exception",
            type: SyncExceptionType.reloginNeeded);
      }
      return await authenticatedCall(url, params,
          method: method, body: body, lastCall: true);
    } catch (ex) {
      rethrow;
    }
  }

  /// Return a token to be used in authenticated calls
  Future<String?> _getToken() async {
    SyncDetails detail = await _getTokenFromDB();
    if (detail.accessToken == null) {
      detail = await _registerForAToken(detail);
    }
    if (DateTime.now().isAfter(detail.accessTokenExpiration ?? DateTime(0))) {
      detail = await _refreshToken(detail);
    }
    return detail.accessToken;
  }

  /// Force a refresh token if the server as asked for it
  Future<void> _forceRefreshToken() async {
    SyncDetails detail = await _getTokenFromDB();
    await _refreshToken(detail);
  }

  Future<SyncDetails> _getTokenFromDB() async {
    const sql = "SELECT * FROM sync_details";
    return await SQLiteWrapper().query(sql,
        singleResult: true, dbName: dbName, fromMap: SyncDetails.fromDB);
  }

  // Make a call in SimpleAuthentication
  Future<SyncDetails> _registerForAToken(SyncDetails syncDetails) async {
    // Authorization: Basic username:password
    Map<String, dynamic> tokenData = await HttpHelper.call(
        "$serverUrl/login/$realm", {},
        body: jsonEncode({"clientId": syncDetails.clientid}),
        additionalHeaders: HttpHelper.simpleAuthenticationHeader(
            username: syncDetails.useremail,
            password: syncDetails.userpassword),
        method: 'POST');
    return await _updateSyncDetailsFromTokenData(syncDetails, tokenData);
  }

  /// Refresh the token and persist data to the DB
  Future<SyncDetails> _refreshToken(SyncDetails syncDetails) async {
    try {
      Map<String, dynamic> tokenData = await HttpHelper.call(
          "$serverUrl/login/$realm/refreshToken", {},
          body: jsonEncode({"refreshToken": syncDetails.refreshToken}),
          method: 'POST');
      return await _updateSyncDetailsFromTokenData(syncDetails, tokenData);
    } on UnauthorizedException {
      // Relogin using username and password
      debugPrint("Something went wrong with refreshToken try to relogin");
      return await _registerForAToken(syncDetails);
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
      SyncDetails syncDetails, Map<String, dynamic> tokenData) async {
    syncDetails.accessToken = tokenData['access_token'];
    syncDetails.refreshToken = tokenData['refresh_token'];
    syncDetails.accessTokenExpiration =
        DateTime.fromMillisecondsSinceEpoch(tokenData['expires_on']);
    await SQLiteWrapper().save(syncDetails.toMap(), SyncDetails.tableName,
        dbName: dbName, keys: ['clientid']);
    return syncDetails;
  }
}
