import 'package:enigmo_server/anongram_server.dart';
import 'package:test/test.dart';

void main() {
  group('AnogramServer Tests', () {
    test('должен создать экземпляр сервера', () {
      final server = AnogramServer();
      expect(server, isNotNull);
      expect(server, isA<AnogramServer>());
    });
  });
}
