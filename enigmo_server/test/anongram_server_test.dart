import 'package:enigmo_server/anongram_server.dart';
import 'package:test/test.dart';

void main() {
  group('AnogramServer Tests', () {
    test('should create a server instance', () {
      final server = AnogramServer();
      expect(server, isNotNull);
      expect(server, isA<AnogramServer>());
    });
  });
}
