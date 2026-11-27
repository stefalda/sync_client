## 1.6.1
- **Fix**: se la configurazione di sync sparisce **durante** una sync (logout, reset o cancellazione concorrente), il cleanup interno (`_cancelSync`) esplodeva con `TypeError: type 'Null' is not a subtype of type 'FutureOr<SyncDetails>'`, sostituendo l'errore vero. Ora `_getTokenFromDB` è null-safe e le chiamate autenticate falliscono con `SyncException(syncConfigurationMissing)`.
- Test: `test/repository/missing_config_test.dart`.

## 1.6.0
- **Push streaming**: in memoria restano solo i metadati delle modifiche in coda; i `rowData` con i blob vengono letti dal DB a blocchi (`kRowsLoadedAtOnce`, 8 righe) appena prima dell'invio. Prima l'intera libreria (blob + base64) veniva materializzata all'inizio della sync: con 90 MB di copertine il picco superava i 700 MB.
- **Push ripartibile**: le righe già inviate vengono tolte da `sync_data` subito dopo il push riuscito (`deletePushedRowsProgressively`). Un'interruzione (app in background, rete che cade) fa ripartire solo il residuo invece dell'intera libreria.
- **Pull paginato**: `_pull` chiede le pagine al server (`limit`, `maxBytes`, `cursor`) e importa ogni pagina subito. La memoria del client è legata alla pagina, non alla libreria. Con un server che non supporta la paginazione (risposta senza `hasMore`) si comporta come prima: una sola richiesta.
- Limiti configurabili nel costruttore: `maxRowsPerPush`, `maxBytesPerPush`, `maxRowsPerPull`, `maxBytesPerPull`.
- Le righe che il server dichiara `outdatedRowsGuid` non vengono nemmeno lette dal DB.
- **Token rinnovato solo alla scadenza**: `accessTokenExpiration` non veniva mai salvata (codice commentato), quindi `_getToken` faceva `_refreshToken` prima di **ogni** chiamata autenticata: il doppio delle richieste, e su `/login` (limite 10/min) un blocco con le sync paginate. Ora la scadenza si legge da `expires_on` o dal claim `exp` del JWT e il rinnovo avviene solo entro il minuto precedente la scadenza (se sconosciuta si gestisce il 401).
- Test: `streaming_push_test.dart` (6 casi), `pull_pagination_test.dart` (4 casi), `push_chunking_test.dart` (10 casi), `token_refresh_test.dart` (4 casi).

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