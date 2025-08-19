/// Простой логгер для сервера
class Logger {
  // Экземплярные методы
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

  // Статические методы для обратной совместимости
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