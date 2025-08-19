/// Simple logger for the server
class Logger {
  // Instance methods
  void info(String message) {
    print('INFO: $message');
  }

  void debug(String message) {
    print('DEBUG: $message');
  }

  void error(String message) {
    print('ERROR: $message');
  }

  void warning(String message) {
    print('WARNING: $message');
  }

  // Static methods for backward compatibility
  static void logInfo(String message) {
    print('INFO: $message');
  }

  static void logDebug(String message) {
    print('DEBUG: $message');
  }

  static void logError(String message) {
    print('ERROR: $message');
  }

  static void logWarning(String message) {
    print('WARNING: $message');
  }
}