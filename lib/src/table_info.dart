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

  TableInfo({
    required this.keyField,
    this.binaryFields = const [],
    this.encryptedFields = const [],
    //  required this.externalKeys,
    this.aliasesFields = const {},
    this.includeBinaryField,
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