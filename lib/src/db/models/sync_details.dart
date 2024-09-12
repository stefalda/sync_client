class SyncDetails {
  static const tableName = "sync_details";
  late String name;
  late String clientid;
  late String useremail;
  late String userpassword;
  late DateTime lastsync;
  String? accessToken;
  String? refreshToken;
  DateTime? accessTokenExpiration;

  SyncDetails.fromDB(Map<dynamic, dynamic> row) {
    name = row["name"];
    clientid = row["clientid"];
    useremail = row["useremail"];
    userpassword = row["userpassword"];
    lastsync =
        DateTime.fromMillisecondsSinceEpoch(row["lastsync"] ?? 0, isUtc: true);
    accessToken = row["accesstoken"];
    refreshToken = row["refreshtoken"];
    accessTokenExpiration = row["accesstokenexpiration"] != null
        ? DateTime.fromMillisecondsSinceEpoch(row["accesstokenexpiration"],
            isUtc: true)
        : null;
  }

  SyncDetails(
      {required this.clientid,
      required this.name,
      required this.useremail,
      required this.userpassword,
      required this.lastsync,
      this.accessToken,
      this.refreshToken,
      this.accessTokenExpiration});

  SyncDetails.fromMap(Map<String, dynamic> json) {
    clientid = json['clientid'];
    name = json['name'];
    useremail = json['useremail'];
    userpassword = json['userpassword'];
    lastsync = json['lastsync'] != null
        ? DateTime.fromMillisecondsSinceEpoch(json['lastsync'], isUtc: true)
        : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    accessToken = json['accesstoken'];
    refreshToken = json['refreshtoken'];
    accessTokenExpiration = json['accesstokenexpiration'] != null
        ? DateTime.fromMillisecondsSinceEpoch(json['accesstokenexpiration'],
            isUtc: true)
        : null;
  }

  Map<String, dynamic> toMap() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['clientid'] = clientid;
    data['name'] = name;
    data['useremail'] = useremail;
    data['userpassword'] = userpassword;
    data['lastsync'] = lastsync.millisecondsSinceEpoch;
    data['accesstoken'] = accessToken;
    data['refreshtoken'] = refreshToken;
    data['accesstokenexpiration'] =
        accessTokenExpiration?.millisecondsSinceEpoch;
    return data;
  }
}
