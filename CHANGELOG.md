## 1.5.5
- **Push spezzato anche per dimensione**: oltre al limite di 100 righe per richiesta, i push vengono divisi in base ai byte stimati (`kMaxBytesPerPush`, 8 MB). Con librerie ricche di immagini (cover libri, foto autori) i 100 righe fisse producevano body oltre il limite del server (10-50 MB) e il push falliva con `request entity too large`, lasciando la sincronizzazione a metà e la coda `sync_data` piena ogni volta.
- Nuove funzioni pubbliche `splitForPush` e `estimateSyncDataSize` (test: `test/repository/push_chunking_test.dart`).
- Una singola riga più grande del limite viene inviata da sola (non è spezzabile).
- **Push streaming**: in memoria restano solo i metadati delle modifiche in coda (`_getPendingChanges`), i `rowData` con i blob vengono letti dal DB a blocchi (`kRowsLoadedAtOnce`, 8 righe) appena prima di essere inviati. Prima l'intera libreria (blob + base64) veniva materializzata all'inizio della sync: con 90 MB di copertine il picco superava i 700 MB. Il pull ora manda solo metadati (come già faceva via `skipRowData`), quindi i blob delle righe scartate come `outdatedRowsGuid` non vengono nemmeno letti.
- Limiti per push configurabili nel costruttore (`maxRowsPerPush`, `maxBytesPerPush`), utili per test e per app che vogliono richieste più piccole.
- I `rowData` non vengono mai agganciati ai metadati della coda: il push lavora su copie, così dopo l'invio i blob sono liberabili (senza questo la memoria restava alta quanto prima).
- Test: `test/repository/streaming_push_test.dart` (blob a blocchi, lettura al momento del push, delete senza rowData, pull senza rowData, outdated non pushate).

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