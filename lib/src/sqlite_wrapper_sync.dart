import 'package:sqlite_wrapper/sqlite_wrapper.dart';
import 'package:sync_client/src/sqlite_wrapper_sync_mixin.dart';
import 'package:sync_client/src/table_info.dart';

enum SyncEnabled { unknown, enabled, disabled }

enum Operation { insert, delete, update }

// Use the class or the mixin...
class SQLiteWrapperSync extends SQLiteWrapperCore with SQLiteWrapperSyncMixin {
  SQLiteWrapperSync({required Map<String, TableInfo> tableInfos}) {
    this.tableInfos = tableInfos;
  }
}
