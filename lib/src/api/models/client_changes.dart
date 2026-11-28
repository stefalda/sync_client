import './sync_data.dart';

/// Class used to send data to the pull/push methods on the server
class ClientChanges {
  late String clientId;
  late int lastSync;
  late List<SyncData> changes;
  int isPartial = 0;

  /// Paginazione del pull (null = comportamento storico, tutto in una risposta).
  int? limit;
  int? maxBytes;
  int? cursor;

  /// Versione dello schema DB del client (l'app passa `kDBVersion`).
  int? schemaVersion;

  static ClientChanges fromMap(Map jsonData) {
    return ClientChanges()
      ..clientId = jsonData['clientId']
      ..lastSync = jsonData['lastSync']
      ..isPartial = jsonData['isPartial']
      ..changes = (jsonData['changes'] as List)
          .map((e) => SyncData.fromMap(e))
          .toList()
          .cast<SyncData>();
  }

  Map<String, Object> toMap({bool skipRowData = false}) {
    final map = <String, Object>{
      'clientId': clientId,
      'lastSync': lastSync,
      'isPartial': isPartial,
      'changes': changes.map((e) => e.toMap(skipRowData: skipRowData)).toList()
    };
    // Inviati solo se valorizzati: un server vecchio ignora i campi che non
    // conosce e continua a rispondere con tutto.
    if (limit != null) map['limit'] = limit!;
    if (maxBytes != null) map['maxBytes'] = maxBytes!;
    if (cursor != null) map['cursor'] = cursor!;
    if (schemaVersion != null) map['schemaVersion'] = schemaVersion!;
    return map;
  }
}
