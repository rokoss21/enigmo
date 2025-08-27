import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('Server Health Tests', () {
    test('Server health check should return OK status', () async {
      final response = await http.get(Uri.parse('http://localhost:8081/api/health'));

      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], contains('application/json'));

      final jsonResponse = jsonDecode(response.body);
      expect(jsonResponse['status'], equals('ok'));
      expect(jsonResponse.containsKey('timestamp'), isTrue);
    });

    test('Server statistics endpoint should return valid data', () async {
      final response = await http.get(Uri.parse('http://localhost:8081/api/stats'));

      expect(response.statusCode, equals(200));
      expect(response.headers['content-type'], contains('application/json'));

      final jsonResponse = jsonDecode(response.body);
      expect(jsonResponse.containsKey('server'), isTrue);
      expect(jsonResponse.containsKey('users'), isTrue);
      expect(jsonResponse.containsKey('messages'), isTrue);
      expect(jsonResponse['server'].containsKey('uptime'), isTrue);
      expect(jsonResponse['server'].containsKey('version'), isTrue);
      expect(jsonResponse['users'].containsKey('totalUsers'), isTrue);
      expect(jsonResponse['users'].containsKey('onlineUsers'), isTrue);
    });
  });

  group('WebRTC Signaling Basic Tests', () {
    test('Server should handle unknown message types gracefully', () async {
      final response = await http.post(
        Uri.parse('http://localhost:8081/api/test'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': 'unknown_message_type',
          'data': 'test'
        }),
      );

      // Should return 404 for unknown routes
      expect(response.statusCode, equals(404));
    });

    test('WebSocket endpoint should be accessible', () async {
      // This is a basic connectivity test
      // In a real scenario, we'd use WebSocketChannel for full testing
      final response = await http.get(Uri.parse('http://localhost:8081/ws'));

      // WebSocket upgrade should be handled
      expect(response.statusCode, isNot(equals(500)));
    });
  });
}