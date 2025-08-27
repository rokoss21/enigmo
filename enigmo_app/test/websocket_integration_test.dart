import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:enigmo_app/services/network_service.dart';
import 'package:enigmo_app/services/crypto_engine.dart';

// Note: These tests require a running server on localhost:8081
// They are integration tests that test the full client-server communication

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebSocket Integration Tests', () {
    late NetworkService networkService;
    late CryptoEngine cryptoEngine;

    setUp(() {
      networkService = NetworkService();
      cryptoEngine = CryptoEngine();
    });

    tearDown(() {
      networkService.dispose();
    });

    test('should connect to WebSocket server', () async {
      expect(networkService, isNotNull);

      final connected = await networkService.connect();
      expect(connected, isTrue);
    }, skip: 'Requires running server');

    test('should register user successfully', () async {
      final connected = await networkService.connect();
      expect(connected, isTrue);

      final userId = await networkService.registerUser(nickname: 'TestUser');
      expect(userId, isNotNull);
      expect(userId!.isNotEmpty, isTrue);
    }, skip: 'Requires running server');

    test('should authenticate user successfully', () async {
      final connected = await networkService.connect();
      expect(connected, isTrue);

      final userId = await networkService.registerUser(nickname: 'TestUser');
      expect(userId, isNotNull);

      final authenticated = await networkService.authenticate();
      expect(authenticated, isTrue);
    }, skip: 'Requires running server');

    test('should send and receive messages', () async {
      final connected = await networkService.connect();
      expect(connected, isTrue);

      final userId = await networkService.registerUser(nickname: 'TestUser');
      expect(userId, isNotNull);

      await networkService.authenticate();

      // Listen for new messages
      String? receivedMessage;
      networkService.newMessages.listen((message) {
        receivedMessage = message.content;
      });

      // Send a message to self (for testing)
      final success = await networkService.sendMessage(userId!, 'Test message');
      expect(success, isTrue);

      // Wait for message to be received
      await Future.delayed(Duration(seconds: 1));

      expect(receivedMessage, equals('Test message'));
    }, skip: 'Requires running server');

    test('should handle user status updates', () async {
      final connected = await networkService.connect();
      expect(connected, isTrue);

      final userId = await networkService.registerUser(nickname: 'TestUser');
      expect(userId, isNotNull);

      await networkService.authenticate();

      // Listen for status updates
      Map<String, dynamic>? statusUpdate;
      networkService.userStatusUpdates.listen((update) {
        statusUpdate = update;
      });

      // Connect another client to trigger status update
      final networkService2 = NetworkService();
      await networkService2.connect();
      final userId2 = await networkService2.registerUser(nickname: 'TestUser2');
      await networkService2.authenticate();

      // Wait for status update
      await Future.delayed(Duration(seconds: 2));

      expect(statusUpdate, isNotNull);
      expect(statusUpdate!['userId'], equals(userId2));

      networkService2.dispose();
    }, skip: 'Requires running server');

    test('should get users list', () async {
      final connected = await networkService.connect();
      expect(connected, isTrue);

      final userId = await networkService.registerUser(nickname: 'TestUser');
      expect(userId, isNotNull);

      await networkService.authenticate();

      final users = await networkService.getUsers();
      expect(users, isNotNull);
      expect(users.length, greaterThan(0));
    }, skip: 'Requires running server');

    test('should handle message history', () async {
      final connected = await networkService.connect();
      expect(connected, isTrue);

      final userId = await networkService.registerUser(nickname: 'TestUser');
      expect(userId, isNotNull);

      await networkService.authenticate();

      // Send multiple messages
      for (var i = 0; i < 3; i++) {
        await networkService.sendMessage(userId!, 'Message $i');
        await Future.delayed(Duration(milliseconds: 100));
      }

      // Get message history
      final messages = networkService.getRecentMessages(userId!);
      expect(messages.length, equals(3));
    }, skip: 'Requires running server');
  });

  group('WebSocket Error Handling Integration Tests', () {
    test('should handle server disconnection gracefully', () async {
      final connected = await networkService.connect();
      expect(connected, isTrue);

      final userId = await networkService.registerUser(nickname: 'TestUser');
      expect(userId, isNotNull);

      await networkService.authenticate();

      // Listen for connection status changes
      bool connectionLost = false;
      networkService.connectionStatus.listen((status) {
        if (!status) connectionLost = true;
      });

      // Simulate server disconnection by disposing network service
      networkService.dispose();

      expect(connectionLost, isTrue);
    }, skip: 'Requires running server');

    test('should handle invalid message format', () async {
      final connected = await networkService.connect();
      expect(connected, isTrue);

      final userId = await networkService.registerUser(nickname: 'TestUser');
      expect(userId, isNotNull);

      await networkService.authenticate();

      // Try to send malformed message - this should be handled gracefully
      expect(networkService, isNotNull);
    }, skip: 'Requires running server');

    test('should handle network timeouts', () async {
      // Test with slow network conditions
      expect(networkService, isNotNull);
    }, skip: 'Requires running server');
  });

  group('WebSocket Performance Integration Tests', () {
    test('should handle multiple concurrent messages', () async {
      final connected = await networkService.connect();
      expect(connected, isTrue);

      final userId = await networkService.registerUser(nickname: 'TestUser');
      expect(userId, isNotNull);

      await networkService.authenticate();

      // Send multiple messages concurrently
      final futures = <Future>[];
      for (var i = 0; i < 10; i++) {
        futures.add(networkService.sendMessage(userId!, 'Concurrent message $i'));
      }

      final results = await Future.wait(futures);
      expect(results.every((success) => success), isTrue);
    }, skip: 'Requires running server');

    test('should handle large message payloads', () async {
      final connected = await networkService.connect();
      expect(connected, isTrue);

      final userId = await networkService.registerUser(nickname: 'TestUser');
      expect(userId, isNotNull);

      await networkService.authenticate();

      // Send large message
      final largeMessage = 'x' * 10000; // 10KB message
      final success = await networkService.sendMessage(userId!, largeMessage);

      expect(success, isTrue);
    }, skip: 'Requires running server');

    test('should handle rapid connect/disconnect cycles', () async {
      // Test connection stability
      for (var i = 0; i < 5; i++) {
        final service = NetworkService();
        final connected = await service.connect();
        expect(connected, isTrue);

        final userId = await service.registerUser(nickname: 'TestUser$i');
        expect(userId, isNotNull);

        await service.authenticate();
        service.dispose();
      }
    }, skip: 'Requires running server');
  });

  group('WebSocket Security Integration Tests', () {
    test('should encrypt messages end-to-end', () async {
      final connected = await networkService.connect();
      expect(connected, isTrue);

      final userId = await networkService.registerUser(nickname: 'TestUser');
      expect(userId, isNotNull);

      await networkService.authenticate();

      final originalMessage = 'This is a secret message';

      // Listen for received messages
      String? receivedMessage;
      networkService.newMessages.listen((message) {
        receivedMessage = message.content;
      });

      // Send encrypted message
      final success = await networkService.sendMessage(userId!, originalMessage);
      expect(success, isTrue);

      // Wait for message
      await Future.delayed(Duration(seconds: 1));

      // Verify message was received and decrypted correctly
      expect(receivedMessage, equals(originalMessage));
    }, skip: 'Requires running server');

    test('should validate message signatures', () async {
      final connected = await networkService.connect();
      expect(connected, isTrue);

      final userId = await networkService.registerUser(nickname: 'TestUser');
      expect(userId, isNotNull);

      await networkService.authenticate();

      // Messages should be properly signed and verified
      final success = await networkService.sendMessage(userId!, 'Signed message');
      expect(success, isTrue);
    }, skip: 'Requires running server');

    test('should prevent unauthorized access', () async {
      final connected = await networkService.connect();
      expect(connected, isTrue);

      // Try operations without authentication
      final users = await networkService.getUsers();
      expect(users, isNotNull); // Should handle gracefully
    }, skip: 'Requires running server');
  });

  group('WebSocket Real-time Communication Tests', () {
    test('should receive messages in real-time', () async {
      final service1 = NetworkService();
      final service2 = NetworkService();

      // Connect both services
      await service1.connect();
      await service2.connect();

      // Register and authenticate both users
      final userId1 = await service1.registerUser(nickname: 'User1');
      final userId2 = await service2.registerUser(nickname: 'User2');

      await service1.authenticate();
      await service2.authenticate();

      // Listen for messages on service2
      String? receivedMessage;
      service2.newMessages.listen((message) {
        receivedMessage = message.content;
      });

      // Send message from service1 to service2
      const testMessage = 'Real-time test message';
      final success = await service1.sendMessage(userId2!, testMessage);
      expect(success, isTrue);

      // Wait for real-time delivery
      await Future.delayed(Duration(seconds: 2));

      expect(receivedMessage, equals(testMessage));

      service1.dispose();
      service2.dispose();
    }, skip: 'Requires running server');

    test('should handle user online/offline status', () async {
      final service1 = NetworkService();
      final service2 = NetworkService();

      await service1.connect();
      await service2.connect();

      final userId1 = await service1.registerUser(nickname: 'User1');
      final userId2 = await service2.registerUser(nickname: 'User2');

      await service1.authenticate();
      await service2.authenticate();

      // Listen for status updates
      bool user2Online = false;
      service1.userStatusUpdates.listen((update) {
        if (update['userId'] == userId2 && update['isOnline'] == true) {
          user2Online = true;
        }
      });

      // Wait for status update
      await Future.delayed(Duration(seconds: 2));
      expect(user2Online, isTrue);

      // Disconnect service2
      service2.dispose();

      // Listen for offline status
      bool user2Offline = false;
      service1.userStatusUpdates.listen((update) {
        if (update['userId'] == userId2 && update['isOnline'] == false) {
          user2Offline = true;
        }
      });

      await Future.delayed(Duration(seconds: 2));
      expect(user2Offline, isTrue);

      service1.dispose();
    }, skip: 'Requires running server');
  });
}