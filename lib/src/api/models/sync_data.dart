/// Synchronization data - used by the REST API but to persist to the DB too
class SyncData {
  String? operation;
  String? rowguid;
  String? tablename;
  DateTime? clientdate;
  int? id;
  // Eventuali dati da inviare...
  Map<String, dynamic>? rowData;

  SyncData.fromDB(Map<dynamic, dynamic> row) {
    rowguid = row["rowguid"];
    operation = row["operation"];
    tablename = row["tablename"];
    clientdate = DateTime.fromMillisecondsSinceEpoch(row["clientdate"]);
    id = row["id"];
  }

  SyncData(
      {this.id,
      this.operation,
      this.rowguid,
      this.tablename,
      this.clientdate,
      this.rowData});

  SyncData.fromMap(Map<String, dynamic> json) {
    operation = json['operation'];
    rowguid = json['rowguid'];
    tablename = json['tablename'];
    clientdate = json['clientdate'] != null
        ? DateTime.fromMillisecondsSinceEpoch(json['clientdate'])
        : null;
    rowData = json['rowData'];
  }

  Map<String, dynamic> toMap({bool skipRowData = false}) {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['operation'] = operation;
    data['rowguid'] = rowguid;
    data['tablename'] = tablename;
    data['clientdate'] = clientdate?.millisecondsSinceEpoch;
    if (!skipRowData && rowData != null) {
      data['rowData'] = rowData;
    }
    return data;
  }
}
