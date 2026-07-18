class TableInfo {
  /// The table key field
  final String keyField;

  /// Binary Fields should be encoded as base64
  final List<String> binaryFields;

  /// Encrypted Fields should be encoded as base64
  final List<String> encryptedFields;

  /// Boolesn Fields are transcoded from integers
  // final List<String> booleanFields;

  /// A list of external keys mapped on different tables
  // final List<ExternalKey> externalKeys;

  /// A Map of aliases that should be transcoded on the server side (@deprecated?)
  Map<String, String> aliasesFields;

  /// Optional per-row callback to decide whether a binary field should be encoded
  /// and included in the sync payload.
  ///
  /// Receives the field name and the full row data map.
  /// Return `true` to include the field (default behavior when the callback is null),
  /// return `false` to exclude the field from the row data before base64 encoding.
  ///
  /// When this callback is null (default), every binary field is encoded as before —
  /// backward compatible.
  final bool Function(String fieldName, Map<String, dynamic> rowData)?
      includeBinaryField;

  /// Optional SQL WHERE clause (without the WHERE keyword) to filter which rows
  /// are eligible for sync logging.
  ///
  /// When present, queries that select rows for sync tracking
  /// (`_logPreviouslyInsertedData`, `_insertInitialSyncData`) append
  /// `WHERE $rowFilter` to exclude non-matching rows.
  ///
  /// Example: `"custom = 1"` — only rows with custom = 1 are tracked.
  ///
  /// When null (default), all rows are eligible — backward compatible.
  final String? rowFilter;

  TableInfo({
    required this.keyField,
    this.binaryFields = const [],
    this.encryptedFields = const [],
    //  required this.externalKeys,
    this.aliasesFields = const {},
    this.includeBinaryField,
    this.rowFilter,
    // this.booleanFields = const []
  });
}
/*
class ExternalKey {
  final String fieldName;
  final String externalFieldTable;
  final String externalFieldKey;
  final String externalKey;

  ExternalKey(
      {required this.fieldName,
      required this.externalFieldTable,
      required this.externalFieldKey,
      this.externalKey = "rowguid"});
}
*/