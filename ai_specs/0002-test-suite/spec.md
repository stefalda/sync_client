---
type: Spec
title: Test Suite for sync_client library
---

## Problem

The sync_client library has minimal test coverage: only three EncryptHelper unit tests exist. All functional verification is done manually via the example Flutter app or via a sequential integration test in example/test/ that requires a running Docker stack. There are no unit tests for model serialization (SyncData, ClientChanges, etc.), no DB-in-memory tests for the core sync mixin logic (logOperation state machine), and no isolated repository tests with a controlled HTTP layer.

## Proposed Outcome

A structured three-level test suite that covers:

1. **Pure unit tests** for data models and stateless helpers.
2. **DB-in-memory tests** for `SQLiteWrapperSyncMixin` logic (operation logging, conflict resolution, sync config checks).
3. **Isolated repository tests** for `SyncRepository` with a `FakeHttpHelper` that simulates all server endpoints.
4. **Docker-based integration tests** for end-to-end sync flows against a real sync_server instance.

CI runs unit+DB tests on every push/PR and integration tests separately with Docker.

## User Stories

1. As a developer maintaining the library, I want unit tests for every data model (SyncData, ClientChanges, UserRegistration, PasswordChange, SyncInfo, SyncDetails) so that serialization regressions are caught immediately.
2. As a developer maintaining the library, I want tests for EncryptHelper covering encryption, decryption, PIN conversion, secret key generation, and password encryption/decryption so that crypto changes don't break existing data.
3. As a developer maintaining the library, I want tests for SyncException and SyncProgress constructors so that error handling code is regression-safe.
4. As a developer maintaining the library, I want DB-in-memory tests for the SQLiteWrapperSyncMixin logOperation state machine covering all operation transitions (I→U collation, I→D removal, U→D demotion, sync-not-configured skip, isSyncing skip) so that the change-tracking core is correct.
5. As a developer maintaining the library, I want repository tests with a FakeHttpHelper that simulates every server endpoint (register, login, refreshToken, pull, push, unregister, forgottenPassword, changePassword, cancelSync) including error paths (connection refused, unauthorized, 403, 404) so that the sync orchestration logic is testable without a real server.
6. As a developer maintaining the library, I want Docker-based integration tests that run against a real sync_server instance and verify multi-client sync scenarios (insert→sync→verify, delete→sync→verify, concurrent modification→last-write-wins, delete-one-client-modify-other→restore) so that the full network path is validated.
7. As a developer, I want the CI pipeline to run unit+DB tests on every push/PR and integration tests separately with Docker setup so that fast feedback is not blocked by slow integration tests.

## Requirements

### R1: Pure model unit tests

1. `SyncData` — fromDB, fromMap, toMap (with and without skipRowData) produce correct field mappings. [L1]
2. `ClientChanges` — toMap(skipRowData: true) omits rowData from nested SyncData; toMap(skipRowData: false) includes it. [L1]
3. `UserRegistration` — toMap includes all fields (name, email, password, clientId, clientDescription, newRegistration, deleteRemoteData, language). [L1]
4. `PasswordChange` — toMap includes email, password, pin. [L1]
5. `SyncInfo` — fromJson parses lastSync correctly; null lastSync is handled. [L1]
6. `SyncDetails` (api) — fromJson parses outdatedRowsGuid and data list; missing data field yields empty list. [L1]
7. `SyncDetails` (db) — fromDB applies EncryptHelper.decryptPassword to userpassword; toMap applies EncryptHelper.encryptPassword; null accessTokenExpiration is handled. [L1]

### R2: EncryptHelper tests [L10]

1. Existing three tests (convertPinToSecretKey, encrypt/decrypt round-trip, decrypt known value) moved from sync_client_test.dart to encrypt_helper_test.dart.
2. New tests: `encryptPassword` wraps with `{AES}` prefix; `decryptPassword` strips prefix and decrypts; legacy plaintext password (no prefix) passes through unchanged; round-trip password encrypt/decrypt.
3. New test: `generateSecretKey` returns a 32-character hex string without dashes.

### R3: SyncException and SyncProgress tests [L1]

1. SyncException stores type and message; toString returns `"$type - $message"`.
2. SyncProgress with null processedItems/totalItems returns null progress; with valid values returns ratio; each SyncStatus value is constructible.

### R4: SQLiteWrapperSyncMixin logOperation tests [L4]

Using a fresh `SQLiteWrapperSync` instance on `:memory:` with sync tables initialized [L6]:

1. **I insert**: logOperation(table, Operation.insert, guid) writes a row with operation='I' in sync_data.
2. **I→U collation**: Insert then Update → only one sync_data row exists with operation='I' (original clientdate preserved).
3. **U→U consolidation**: Update then Update → only one sync_data row exists with operation='U' (date updated).
4. **I→D removal**: Insert then Delete → no sync_data rows for that guid remain.
5. **U→D demotion**: Update then Delete → sync_data row has operation='D'.
6. **D on non-tracked table**: logOperation on table not in tableInfos → no row written.
7. **isSyncing = true**: set isSyncing = true → logOperation skips writing.
8. **Sync not configured**: no row in sync_details → logOperation skips writing.
9. **shouldSync**: returns true when sync_data has rows, false when empty.
10. **insertInitialSyncData**: inserts initial 'I' rows for existing data in tracked tables.

### R5: Repository tests with FakeHttpHelper [L2][L5][L12]

Using `SyncRepository` with `FakeHttpHelper` and a fresh in-memory DB [L6]:

1. **Register new user**: `register(newRegistration: true)` → calls POST /register/{realm}, stores sync_details, returns without error.
2. **Register existing client**: `register(newRegistration: false)` → calls server, updates details.
3. **Register duplicate email**: fake returns email-already-exists → SyncException with type registerExceptionAlreadyRegistered.
4. **Full sync cycle**: register → insert data → sync() → calls pull then push → updates lastSync → deletes processed sync_data rows.
5. **Pull with remote data**: sync with data on server → importServerData inserts new rows locally.
6. **Pull with conflict**: server marks some local rows as outdated → those rows are excluded from push.
7. **Push partial ( >100 rows)**: sync with 150 pending changes → pushes in batches of 100.
8. **Sync not configured error**: sync() without register → SyncException with type syncConfigurationMissing.
9. **Connection refused**: fake throws ConnectionException → SyncException with type connectionException.
10. **Unauthorized → token refresh → retry**: first call returns 401, refresh succeeds → retry works.
11. **Unauthorized → refresh fails**: first call returns 401, refresh also returns 401 → SyncException with type reloginNeeded.
12. **Unregister**: calls POST /unregister/{realm}, resets sync_data/sync_details/sync_encryption tables.
13. **Unregister with deleteRemoteData**: flag passed in request body as true.
14. **Forgotten password**: calls POST /password/{realm}/forgotten with email.
15. **Change password success**: calls POST /password/{realm}/change, updates userpassword in sync_details.
16. **Change password expired PIN**: server returns 403 → SyncException with type wrongOrExpiredPin.
17. **isConfigured**: returns true after register, false before.
18. **getSyncDetails**: returns populated SyncDetails after register, null before.
19. **deleteSyncDetails**: removes sync_details and sync_encryption rows.

### R6: Integration tests with Docker [L7][L8]

Using Docker compose in `test/integration/docker/` with unique realm per test [L8]:

1. **Register + first sync**: register two clients, each syncs → both see all data.
2. **Insert → sync → verify**: client inserts rows, syncs → other client sees them.
3. **Delete → sync → verify**: client deletes row, syncs → other client sees deletion.
4. **Modify → sync → verify**: client modifies title, syncs → other client sees new title.
5. **Concurrent modification**: both clients modify same row, last to sync wins (last-write-wins).
6. **Delete on A, modify on B → sync → restore**: B modifies a row that A deleted, B syncs first then A syncs → row restored with B's changes.

### R7: CI pipeline [L9][L13]

1. **test-unit job**: runs on ubuntu-latest, flutter setup, `dart pub get`, `flutter test --exclude-tags integration`.
2. **test-integration job**: runs on ubuntu-latest, flutter setup, docker compose up in test/integration/docker/, wait for health, `flutter test --tags integration`, docker compose down.

## Technical Decisions

### TD1: Test framework and runner

Use `package:test` (already in dev_dependencies) with `flutter test`. Tags `@Tag('integration')` distinguish Docker tests. [L1]

### TD2: HttpHelper injection seam

Add an optional `HttpHelper? httpHelper` parameter to the `SyncRepository` constructor. When omitted, the existing singleton `httpHelper` is used. [L2]

```dart
class SyncRepository {
  final HttpHelper httpHelper;
  // ...
  SyncRepository({
    required this.sqliteWrapperSync,
    required this.serverUrl,
    required this.realm,
    HttpHelper? httpHelper,
  }) : httpHelper = httpHelper ?? httpHelperSingleton, // or the singleton
       authenticationHelper = AuthenticationHelper(...);
}
```

No `inject_x` dependency added. [L13]

### TD3: Test helpers

- `test/helpers/fake_http_helper.dart`: Extends/implementing `HttpHelper.call()`. Matches URL patterns with regex/contains and returns canned JSON responses. Tracks calls for assertion (e.g., count of push calls, URLs invoked). [L5][L12]
- `test/helpers/test_db.dart`: Creates a `SQLiteWrapperSync` with a known `tableInfos` config (e.g., `{"todos": TableInfo(keyField: "rowguid")}`), opens on `:memory:`, calls `initSyncTables`. Disposed after each test. [L6]

### TD4: Integration test isolation

Each integration test constructs a unique realm name using a UUID prefix (e.g., `INT_TEST_${uuid.v4().substring(0, 8)}`). Server state is scoped per realm, so tests do not interfere. [L8]

### TD5: CI workflow changes

Split the single `build` job in `.github/workflows/dart.yml` into two named jobs `test-unit` and `test-integration`. The integration job adds a `services` block for Postgres and the sync server image, or uses `docker compose` directly. [L9]

## Testing Strategy

### Test Seams

1. **HttpHelper injection** (TD2): The new optional constructor parameter on `SyncRepository` is the seam that lets repository tests inject `FakeHttpHelper`.
2. **In-memory DB** (TD3): `test/helpers/test_db.dart` provides the seam for mixin and repository tests by replacing file-based SQLite with `:memory:`.
3. **Realm namespacing** (TD4): Integration tests use unique realm strings to isolate server state.

### Test levels and their dependencies

| Level | Directory | Runner | Depends on | Tags |
|---|---|---|---|---|
| Pure unit | `test/models/`, `test/encrypt_helper_test.dart`, `test/sync_exception_test.dart`, `test/sync_progress_test.dart`, `test/table_info_test.dart` | flutter test (--exclude-tags integration) | Nothing | none |
| DB-in-memory | `test/db/` | flutter test (--exclude-tags integration) | test/helpers/test_db.dart | none |
| Repository (fake HTTP) | `test/repository/` | flutter test (--exclude-tags integration) | test/helpers/test_db.dart, test/helpers/fake_http_helper.dart | none |
| Integration (real server) | `test/integration/` | flutter test --tags integration | Docker (sync_server + Postgres) | @Tag('integration') |

## Out of Scope

- Tests for `SQLiteWrapperSyncGRPC` (requires gRPC server).
- Tests for `UploadChunks` and chunked upload logic.
- Tests for `HttpHelper` in isolation (covered indirectly via repository tests with FakeHttpHelper that exercises HttpHelper interface shape).
- Tests for `AuthenticationHelper` in isolation (covered via repository tests). [L11]
- Performance, load, or stress tests.
- Web-specific test setup.
- Windows/Linux/macOS platform-specific tests beyond what CI on ubuntu-latest covers.

## Blocking Questions

None.

## Open Questions

None.

## Follow-Ups

1. When the sync_server API changes (new endpoints, changed response shapes), update `FakeHttpHelper` and integration test expectations accordingly.
2. Consider adding `SQLiteWrapperSyncGRPC` integration tests when a gRPC test harness is available in CI.
