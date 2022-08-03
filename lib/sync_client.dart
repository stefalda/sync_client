/// Sync Client Library
///
/// Main classes are
/// - SQLiteWrapperSync - an extension to the SQLiteWrapperCore library some methods
///  to enable sync
///   see
/// - SyncRepository
/// - TableInfos
library sync_client;

export 'package:sqlite_wrapper/sqlite_wrapper_core.dart'
    show inMemoryDatabasePath, DatabaseInfo;

export 'src/db/models/sync_details.dart';
export 'src/sqlite_wrapper_sync.dart';
export 'src/sync_repository.dart';
export 'src/table_info.dart';
