class SyncInfo {
  DateTime? lastSync;

  SyncInfo.fromJson(Map<String, dynamic> json) {
    lastSync = json['lastSync'] != null
        ? DateTime.fromMillisecondsSinceEpoch(json['lastSync'])
        : null;
  }
}
