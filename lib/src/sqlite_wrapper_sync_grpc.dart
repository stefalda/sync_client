import 'package:sqlite_wrapper/grpc/sqlite_wrapper_grpc.dart';
import 'package:sync_client/src/sqlite_wrapper_sync_mixin.dart';
import 'package:sync_client/src/table_info.dart';

/// You can use this class to sync from a GRPC
/// SQLiteWrapper instance that uses a remote sqlite db
/// as a local one
// ignore_for_file: use_super_parameters
class SQLiteWrapperSyncGRPC extends SqliteWrapperGRPC
    with SQLiteWrapperSyncMixin {
  SQLiteWrapperSyncGRPC(
      {required Map<String, TableInfo> tableInfos,
      String host = 'localhost',
      int port = 50051,
      bool secure = false})
      : super.withHostAndPort(host: host, port: port, secure: secure) {
    this.tableInfos = tableInfos;
  }
}
