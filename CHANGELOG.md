## 1.6.3
- **Schema version handshake**: `SyncRepository(schemaVersion: ...)` is sent with every pull; if another device of the same user reports a newer schema, the sync fails with `SyncExceptionType.schemaVersionMismatch` instead of applying rows with unknown columns (which `_addNullFields` would silently null). A server without the field behaves as before.
- Test: `test/repository/schema_version_test.dart`.

## 1.6.2
- **Rate limit retry**: a 429 from `/push` or `/pull` is retried up to 3 times with increasing backoff (`rateLimitBaseDelay`, default 30s). Previously a large library (8 MB chunks, more than 30 requests per minute) aborted mid-sync.
- Test: 429 + retry case in `streaming_push_test.dart`.

## 1.6.1
- **Fix**: if the sync configuration disappears **during** a sync (logout, reset or concurrent deletion), the internal cleanup (`_cancelSync`) crashed with `TypeError: type 'Null' is not a subtype of type 'FutureOr<SyncDetails>'`, hiding the real error. `_getTokenFromDB` is now null-safe and authenticated calls fail with `SyncException(syncConfigurationMissing)`.
- Test: `test/repository/missing_config_test.dart`.

## 1.6.0
- **Streaming push**: only change metadata is kept in memory; `rowData` with blobs are read from the DB in batches (`kRowsLoadedAtOnce`, 8 rows) right before being sent. Previously the whole library (blobs + base64) was materialized at the start of the sync: with 90 MB of covers the peak exceeded 700 MB.
- **Resumable push**: rows already sent are removed from `sync_data` right after a successful push (`deletePushedRowsProgressively`). An interruption (app backgrounded, network drop) resumes from the remaining rows instead of the whole library.
- **Paginated pull**: `_pull` requests pages (`limit`, `maxBytes`, `cursor`) and imports each page immediately. Client memory is bound to the page, not to the library. With a server without pagination support (no `hasMore` in the response) it behaves as before: a single request.
- Constructor limits: `maxRowsPerPush`, `maxBytesPerPush`, `maxRowsPerPull`, `maxBytesPerPull`.
- Rows reported in `outdatedRowsGuid` are not even read from the DB.
- **Token refreshed only on expiry**: `accessTokenExpiration` was never stored (commented-out code), so `_getToken` called `_refreshToken` before **every** authenticated call: double the requests, and `/login` (10/min limit) throttled paginated syncs. The expiry is now read from `expires_on` or from the JWT `exp` claim, and the refresh happens only within one minute of expiry (unknown expiry → rely on 401).
- Tests: `streaming_push_test.dart` (6), `pull_pagination_test.dart` (4), `push_chunking_test.dart` (10), `token_refresh_test.dart` (4).

## 1.5.4
- Updated sqlite_wrapper dependency to 0.7.0

## 1.5.3
- Updated sqlite_wrapper dependency to 0.6.1 (fixes web build with `GrpcOrGrpcWebClientChannel` type)

## 1.5.2
- Upgraded sqlite_wrapper version to 0.6.0

## 1.5.1
- Upgraded sqlite_wrapper version

## 1.5.0
- Added `rowFilter` to `TableInfo` — an optional SQL WHERE clause to restrict which rows are eligible for sync logging (e.g., `"custom = 1"`). Both `_logPreviouslyInsertedData` and `insertInitialSyncData` apply the filter, so non-matching rows never enter the sync queue.
- Updated README with `rowFilter` documentation.

## 1.4.6
- Upgraded dependencies

## 1.4.5
- Changed gzip compression for the web version

## 1.4.4
- Added support for refreshToken in gRPC authentication

## 1.4.3
- Added `includeBinaryField` callback to `TableInfo` for per-row conditional binary field encoding

## 1.4.2
- Added support for new sqlite_wrapper 0.4.2
- Reviewed example

## 1.4.0
- Aligned with new sqlite_wrapper 0.4.0

## 1.3.5-beta
- Added local password encryption
- Code reviewed
- Removed direct sqlite3 dependency

## 1.3.4-beta
- Upgraded dependencies

## 1.3.3-beta
- Fixes TOKEN authentication (at the moment returning a different json from JWT)
- Fixes synching when row data are missing (it now continues instead of breaking)

## 1.3.2-beta
- Upgraded dependency and docker server files

## 1.3.1-beta
- Changed some logging

## 1.3.0-beta
- Added support for gRPC managed sqlite remote instance

## 1.2.3
- Added sync progress

## 1.2.2
- Removed timeout from http calls

## 1.2.1
- Forced all dates to be UTC

## 1.2.0
- Reviewed code for multiplatform imports

## 1.1.0
- Added web support

## 1.0.4
- Bug fixes and first working version

## 1.0.0
- Initial version.