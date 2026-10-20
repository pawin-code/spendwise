import 'package:flutter/foundation.dart';

/// Crash reporting seam. The shipped implementation keeps errors on the device
/// only. To add Firebase Crashlytics later, implement this interface (see
/// docs/PRIVACY_AND_SECURITY.md) and make sure no transaction data is attached.
abstract class CrashReporter {
  void recordError(Object error, StackTrace? stack);
}

class LocalCrashReporter implements CrashReporter {
  /// Only the error type and a trimmed stack are printed (debug builds). The
  /// message is deliberately not stored because it could contain user input.
  @override
  void recordError(Object error, StackTrace? stack) {
    if (kDebugMode) {
      debugPrint('Unhandled ${error.runtimeType}');
      debugPrintStack(stackTrace: stack, maxFrames: 8);
    }
  }
}
