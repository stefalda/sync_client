enum SyncExceptionType {
  connectionException,
  syncConfigurationAlreadyPresent,
  syncConfigurationMissing,
  loginExceptionWrongCredentials,
  loginExceptionUserNotFound,
  registerExceptionAlreadyRegistered,
  alreadySyncing,
  wrongOrExpiredPin,
  reloginNeeded,
  generic
}

class SyncException implements Exception {
  final SyncExceptionType type;
  final String message;
  SyncException(this.message, {required this.type});
  @override
  toString() {
    return ("$type - $message");
  }
}
