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
  /// Un altro device dell'utente usa uno schema più recente: aggiornare l'app
  /// prima di sincronizzare (altrimenti si azzerano colonne sconosciute).
  schemaVersionMismatch,
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
