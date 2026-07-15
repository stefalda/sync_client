---
type: Interview Ledger
parent: spec.md
---

## Records

### L1

Status: current

Question: Che tipo di test vuoi aggiungere?

Recommended Answer:
- Unit tests for pure models (SyncData, ClientChanges, etc.)
- DB-in-memory tests for mixin logic (logOperation, shouldSync)
- Integration tests for full sync flow with Docker

Answer: Tutti e tre.

Decision: Add three test levels: pure unit, DB-in-memory, and Docker-based integration.

### L2

Status: current

Question: Come vuoi mockare le chiamate HTTP per i test del repository?

Recommended Answer: Iniettare un `HttpHelper` finto via parametro opzionale nel costruttore di `SyncRepository`, senza aggiungere `inject_x` come dipendenza della libreria.

Answer: ok

Decision: SyncRepository accepts an optional `HttpHelper` parameter in its constructor, defaulting to the current singleton. Tests pass a `FakeHttpHelper`.

Negative Requirements:
- Do NOT add `inject_x` as a library dependency.

### L3

Status: current

Question: Struttura dei file sotto test/?

Recommended Answer:
```
test/
  helpers/
    fake_http_helper.dart
    test_db.dart
  models/
    sync_data_test.dart
    client_changes_test.dart
    user_registration_test.dart
    password_change_test.dart
    sync_info_test.dart
    sync_details_api_test.dart
  encrypt_helper_test.dart
  sync_exception_test.dart
  sync_progress_test.dart
  table_info_test.dart
  db/
    sync_data_db_test.dart
    sync_details_db_test.dart
    sqlite_wrapper_sync_mixin_test.dart
  repository/
    sync_repository_test.dart
  integration/
    docker/
      docker-compose.yml
      config.json
      database_postgres_script.sql
    sync_api_test.dart
```

Answer: va bene l'albero

Decision: Use the recommended tree structure under test/.

### L4

Status: current

Question: Scenari di logOperation da coprire?

Recommended Answer:
- Insert → row with operation 'I'
- Insert → Update → row remains 'I' (date unchanged)
- Update → Update → single 'U' row
- Insert → Delete → no trace
- Update → Delete → becomes 'D'
- Operation on table not in tableInfos → skipped
- isSyncing = true → skipped
- Sync not configured → skipped

Answer: ok

Decision: Cover all recommended logOperation state transitions.

### L5

Status: current

Question: Dove mettere FakeHttpHelper?

Recommended Answer: In `test/helpers/fake_http_helper.dart`, shared across repository and integration tests.

Answer: Si

Decision: FakeHttpHelper lives in test/helpers/fake_http_helper.dart, shared.

### L6

Status: current

Question: Factory per DB in memoria nei test?

Recommended Answer: In `test/helpers/test_db.dart`, factory function/class that opens `SQLiteWrapperSync` on `:memory:` and initialises sync tables. Used in setUp per test.

Answer: Si

Decision: test/helpers/test_db.dart provides a fresh DB instance per test.

### L7

Status: current

Question: Dove vanno i test di integrazione Docker?

Recommended Answer: In `test/integration/sync_api_test.dart` con docker-compose e file di supporto in `test/integration/docker/`.

Answer: ok A (self-contained in test/integration/docker/)

Decision: Integration tests in test/integration/, Docker files self-contained in test/integration/docker/.

### L8

Status: current

Question: Come gestire l'isolamento tra test di integrazione?

Recommended Answer: Ogni test usa un realm univoco (es. `INT_TEST_{uuid}`). I dati sono isolati per namespace senza pulizia server esplicita.

Answer: (selected "Realm unico per test")

Decision: Integration tests use a unique realm per test (UUID-based). No server-side cleanup needed.

### L9

Status: current

Question: CI workflow da modificare?

Recommended Answer: Sì, modificare `.github/workflows/dart.yml` per avere due job: `test-unit` (--exclude-tags integration, nessun Docker) e `test-integration` (--tags integration, docker compose up prima).

Answer: Includere nel Spec

Decision: Update dart.yml with two jobs and docker compose for integration tests.

### L10

Status: current

Question: Cosa fare del file esistente test/sync_client_test.dart?

Recommended Answer: Rinominarlo in test/encrypt_helper_test.dart ed espanderlo lì.

Answer: Si

Decision: Rename sync_client_test.dart → encrypt_helper_test.dart.

Reason: Avoids duplicate EncryptHelper tests across files.

### L11

Status: current

Question: Test separati per AuthenticationHelper?

Recommended Answer: Coperto dai test di SyncRepository. L'AuthenticationHelper viene esercitato indirettamente quando il repository fa pull/push.

Answer: Coperto da SyncRepository

Decision: AuthenticationHelper is not tested in isolation; its behavior is covered via SyncRepository tests.

### L12

Status: current

Question: FakeHttpHelper deve gestire tutti gli endpoint?

Recommended Answer: Sì, tutti: register, login, refreshToken, pull, push, unregister, forgottenPassword, changePassword, cancelSync. Con risposte prefissate per URL pattern.

Answer: tutti

Decision: FakeHttpHelper handles all HTTP endpoints used by SyncRepository and AuthenticationHelper.

### L13

Status: current

Question: Usare inject_x per iniezione?

Recommended Answer: No, usare parametro opzionale del costruttore. inject_x non è dipendenza della libreria.

Answer: ok

Decision: Constructor injection only, no inject_x dependency added.
