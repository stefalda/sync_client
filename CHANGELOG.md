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