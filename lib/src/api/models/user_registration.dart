class UserRegistration {
  String? email;
  String? password;
  String? clientId;
  String? clientDescription;

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'password': password,
      'clientId': clientId,
      'clientDescription': clientDescription
    };
  }
}
