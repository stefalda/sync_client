void debugPrint(Object? message) {
  const bool debug = bool.fromEnvironment('debug');
  if (debug) {
    print(message);
  }
}
