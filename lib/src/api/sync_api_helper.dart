//import 'package:device_info_plus/device_info_plus.dart';

/*
import 'package:sqlite_wrapper_sample/database_helper.dart';
import 'package:sqlite_wrapper_sample/sync/api/models/client_changes.dart';
import 'package:sqlite_wrapper_sample/sync/api/models/sync_data.dart';
import 'package:sqlite_wrapper_sample/sync/api/models/sync_details.dart';
import 'package:sqlite_wrapper_sample/sync/api/models/sync_info.dart';
import 'package:sqlite_wrapper_sample/sync/api/models/user_registration.dart';
import 'package:sqlite_wrapper_sample/sync/sync_helper.dart';
import 'package:sqlite_wrapper_sample/sync/table_info.dart';
import 'package:uuid/uuid.dart';
*/
const defaultUrl = "localhost:8080";

/// Library to perform sync operations provided as a Singleton
///
/// Properties:
/// - serverUrl - the address of the Sync server (default to localhost:8080)
/// - tableInfos - a Map of tables used in the DB that should be synced
/// Methods:
/// - isConfigured - return a future bool that is true if the client has already been registered
/// - register(String email, String password,
//       {dbName = defaultDBName}) - register the client to the sync server
/// - sync ({dbName = defaultDBName) - perform a sync operation (PULL and PUSH)
///
/// setServerUrl(String url)
///
class SyncApiHelper {
  static final SyncApiHelper _singleton = SyncApiHelper._internal();

  String serverUrl = defaultUrl;

  factory SyncApiHelper() {
    return _singleton;
  }

  SyncApiHelper._internal();
}
