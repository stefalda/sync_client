class SyncDetails {
  static const tableName = "sync_details";

  late String clientid;
  late String useremail;
  late String userpassword;
  late DateTime lastsync;

  SyncDetails.fromDB(Map<dynamic, dynamic> row) {
    clientid = row["clientid"];
    useremail = row["useremail"];
    userpassword = row["userpassword"];
    lastsync = DateTime.fromMillisecondsSinceEpoch(row["lastsync"] ?? 0);
  }

  SyncDetails(
      {required this.clientid,
      required this.useremail,
      required this.userpassword,
      required this.lastsync});

  SyncDetails.fromMap(Map<String, dynamic> json) {
    clientid = json['clientid'];
    useremail = json['useremail'];
    userpassword = json['userpassword'];
    lastsync = json['lastsync'] != null
        ? DateTime.fromMillisecondsSinceEpoch(json['lastsync'])
        : DateTime.fromMillisecondsSinceEpoch(0);
  }

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['clientid'] = clientid;
    data['useremail'] = useremail;
    data['userpassword'] = userpassword;
    data['lastsync'] = lastsync.millisecondsSinceEpoch;
    return data;
  }
}
