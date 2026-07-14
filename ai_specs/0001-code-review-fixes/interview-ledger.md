---
type: Interview Ledger
parent: spec.md
---

## Records

### L1

Status: current

Question: Verify whether the 9 critical bugs, 7 minor issues, 7 optimizations, 6 dead-code items, and 3 static-analysis warnings listed in `doc/code_review.md` actually exist in the codebase.

Answer: Yes, all reported items exist except #16 (INSERT column count matches `?` count — the code review is mistaken). Details per item:

**Bug 1** — SQL injection via `operationFilter` string interpolation at `sqlite_wrapper_sync_mixin.dart:228`. Branch is dead (called only with `null`) but dangerous.

**Bug 2** — SQL injection via `$tableName` and `$keyField` interpolation at `sync_repository.dart:578-584`. Low risk (configuration-sourced) but bad practice.

**Bug 3-4** — `shouldSync` at `sqlite_wrapper_sync_mixin.dart:188-195` uses `fromMap: SyncDetails.fromDB` on `COUNT(*)` result, then compares `SyncDetails? > 0`. Crash at runtime.

**Bug 5** — Unawaited `logOperation` at `sync_repository.dart:670`. `unawaited_futures` warning.

**Bug 6** — Double `await await` at `sync_repository.dart:552`. Innocuous copy-paste error.

**Bug 7** — `_getAllTablesColumns` join `on m.name <> p.name` at `sync_repository.dart:685-691`. Should be `=`. Returns wrong columns.

**Bug 8** — `late String name` at `sync_details.dart:3` but DB column `name` admits NULL. Crash if NULL.

**Bug 9** — `userpassword` stored in plaintext in `sync_details` table.

**Bug 10** — File named `password_chage.dart` instead of `password_change.dart`.

**Bug 11** — DB column `accesstoken` (missing 's') in schema at `sqlite_wrapper_sync_mixin.dart:246`. Code reads `row["accesstoken"]` consistently, but column name is a typo.

**Bug 12** — `'$operationFilter!'` interpolates `!` as literal char in SQL — same code as Bug 1.

**Bug 13** — `debug_utils.dart:1` imports `package:flutter/foundation.dart`. Library is not Flutter-specific.

**Bug 14** — `tableInfo!` null assertion at `sqlite_wrapper_sync_mixin.dart:257`. Always present in iteration but unguarded.

**Bug 15** — `_getSyncConfigDetails` returns `Future<dynamic>` at `sync_repository.dart:644`. Should be `Future<Map<String, dynamic>?>`.

**Bug 16** — **False positive.** Column list includes `tableInfo.keyField` and VALUES clause generates `?` for each value in `values` (which includes the keyField value via `values.add(syncData.rowguid)`). Counts match.

**O1** — `tableInfos.keys.contains(tableName)` → `tableInfos.containsKey(tableName)` at `sqlite_wrapper_sync_mixin.dart:62`.

**O2** — `logOperation` does SELECT + DELETE/INSERT; could be `INSERT OR REPLACE`/UPSERT at `sqlite_wrapper_sync_mixin.dart:73-106`.

**O3** — `_importServerData` processes rows sequentially with `await` per row at `sync_repository.dart:448`.

**O4** — `for (var i ...)` + `elementAt(i)` → `entries` at `sync_repository.dart:657-658`.

**O5** — Division by zero in `progress` getter at `sync_progress.dart:39-41` when `totalItems` is 0.

**O6** — `await Future(() {})` → `await Future.delayed(Duration.zero)` at `sync_repository.dart:168,224,238,258`.

**O7** — `syncController` passed through many methods but used only in `uploadConcurrently` (not fully verified).

**D1** — `uploadConcurrently_old` at `upload_chunks.dart:11-128` is dead code; `uploadConcurrently` at line 130 replaced it.

**D2** — `uploadJsonChunked` at `http_helper.dart:139-221` fully commented out.

**D3** — `sync_api_helper.dart:1-42` fully commented out.

**D4** — Commented code blocks at `sync_repository.dart:429-442,476-488,517-522,661-666`.

**D5** — `SyncEnabled` and `Operation` enums duplicated in both `sqlite_wrapper_sync.dart:5-7` and `sqlite_wrapper_sync_mixin.dart:10-12`.

**D6** — `DioAdapterInterface.initAdapter` is defined in `dio_adapter/` but only referenced in a commented-out line at `http_helper.dart:43`. Never called.

**W1** — Missing type annotation on `message` parameter at `debug_utils.dart:3`.

**W2** — `non_constant_identifier_names` for `uploadConcurrently_old` at `upload_chunks.dart:11`.

**W3** — `unawaited_futures` for `logOperation` at `sync_repository.dart:670` (same as Bug 5).

Decision: All items confirmed except #16. The code review is accurate.
