import 'package:sqlite_wrapper/grpc/sqlite_wrapper_grpc.dart';
import 'package:sync_client/src/sqlite_wrapper_sync_mixin.dart';
import 'package:sync_client/src/table_info.dart';

/// You can use this class to sync from a GRPC
/// SQLiteWrapper instance that uses a remote sqlite db
/// as a local one
///
class SQLiteWrapperSyncGRPC extends SqliteWrapperGRPC
    with SQLiteWrapperSyncMixin {
  SQLiteWrapperSyncGRPC({required Map<String, TableInfo> tableInfos}) {
    this.tableInfos = tableInfos;
  }
}
