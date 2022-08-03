import './sync_data.dart';

/// Class used to send data to the pull/push methods on the server
class ClientChanges {
  late String clientId;
  late int lastSync;
  late List<SyncData> changes;

  static ClientChanges fromMap(Map jsonData) {
    return ClientChanges()
      ..clientId = jsonData['clientId']
      ..lastSync = jsonData['lastSync']
      ..changes = jsonData['changes'].map((e) => SyncData.fromMap(e)).toList();
  }

  toMap({bool skipRowData = false}) {
    return {
      'clientId': clientId,
      'lastSync': lastSync,
      'changes': changes.map((e) => e.toMap(skipRowData: skipRowData)).toList()
    };
  }
}
