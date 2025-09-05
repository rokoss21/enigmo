import 'dart:async';
import 'package:test/test.dart';
import 'package:enigmo_server/utils/logger.dart';

void main() {
  group('Logger', () {
    test('instance methods output prefixed messages', () {
      final logger = Logger();
      final messages = <String>[];
      runZoned(() {
        logger.info('hello');
        logger.debug('dbg');
        logger.error('err');
        logger.warning('warn');
      }, zoneSpecification: ZoneSpecification(print: (_, __, ___, String msg) {
        messages.add(msg);
      }));

      expect(messages, [
        'INFO: hello',
        'DEBUG: dbg',
        'ERROR: err',
        'WARNING: warn',
      ]);
    });

    test('static methods output prefixed messages', () {
      final messages = <String>[];
      runZoned(() {
        Logger.logInfo('hi');
        Logger.logDebug('dbg');
        Logger.logError('err');
        Logger.logWarning('warn');
      }, zoneSpecification: ZoneSpecification(print: (_, __, ___, String msg) {
        messages.add(msg);
      }));

      expect(messages, [
        'INFO: hi',
        'DEBUG: dbg',
        'ERROR: err',
        'WARNING: warn',
      ]);
    });
  });
}
