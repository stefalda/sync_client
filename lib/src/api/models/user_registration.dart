class UserRegistration {
  String? email;
  String? password;
  String? clientId;
  String? clientDescription;
  bool deleteRemoteData = false;

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'password': password,
      'clientId': clientId,
      'clientDescription': clientDescription,
      'deleteRemoteData': deleteRemoteData
    };
  }
}
