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

/// Define a sync exception
class SyncException implements Exception {
  final SyncExceptionType type;
  final String message;
  SyncException(this.message, {required this.type});
  @override
  toString() {
    return ("$type - $message");
  }
}
