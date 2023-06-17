///
///   Used to force a password change using the pin provided via email
///
class PasswordChange {
  final String email;
  final String password;
  final String pin;

  PasswordChange(
      {required this.email, required this.password, required this.pin});

  Map<String, dynamic> toMap() {
    return {'email': email, 'password': password, 'pin': pin};
  }
}
