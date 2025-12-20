import 'package:flutter/foundation.dart';

void debugPrint(message) {
  if (kDebugMode) {
    print(message);
  }
}
