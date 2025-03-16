import './sync_data.dart';

/// Class used to send data to the pull/push methods on the server
class ClientChanges {
  late String clientId;
  late int lastSync;
  late List<SyncData> changes;
  int isPartial = 0;

  static ClientChanges fromMap(Map jsonData) {
    return ClientChanges()
      ..clientId = jsonData['clientId']
      ..lastSync = jsonData['lastSync']
      ..isPartial = jsonData['isPartial']
      ..changes = jsonData['changes'].map((e) => SyncData.fromMap(e)).toList();
  }

  toMap({bool skipRowData = false}) {
    return {
      'clientId': clientId,
      'lastSync': lastSync,
      'isPartial': isPartial,
      'changes': changes.map((e) => e.toMap(skipRowData: skipRowData)).toList()
    };
  }
}
