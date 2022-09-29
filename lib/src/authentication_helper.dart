// Return a valid token to make the call

import 'dart:convert';

import 'package:sqlite_wrapper/sqlite_wrapper.dart';
import 'package:sync_client/src/db/models/sync_details.dart';
import 'package:sync_client/src/http_helper.dart';

class AuthenticationHelper {
  final String dbName;
  final String serverUrl;
  final String realm;

  AuthenticationHelper(
      {required this.dbName, required this.serverUrl, required this.realm});

  /// Return a token to be used in authenticated calls
  Future<String?> getToken() async {
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
  Future<void> forceRefreshToken() async {
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
        body: jsonEncode({"clientid": syncDetails.clientid}),
        additionalHeaders: HttpHelper.simpleAuthenticationHeader(
            username: syncDetails.useremail,
            password: syncDetails.userpassword),
        method: 'POST');
    return await _updateSyncDetailsFromTokenData(syncDetails, tokenData);
  }

  /// Refresh the token and persist data to the DB
  Future<SyncDetails> _refreshToken(SyncDetails syncDetails) async {
    Map<String, dynamic> tokenData = await HttpHelper.call(
        "$serverUrl/login/$realm/refreshToken", {},
        body: jsonEncode({"refresh_token": syncDetails.refreshToken}),
        method: 'POST');
    return await _updateSyncDetailsFromTokenData(syncDetails, tokenData);
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
