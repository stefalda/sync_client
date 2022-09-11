class UserRegistration {
  String? email;
  String? password;
  String? clientId;
  String? clientDescription;
  bool newRegistration = false;
  bool deleteRemoteData = false;

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'password': password,
      'clientId': clientId,
      'clientDescription': clientDescription,
      'newRegistration': newRegistration,
      'deleteRemoteData': deleteRemoteData
    };
  }
}
