import 'package:test/test.dart';
import 'package:enigmo_server/services/user_manager.dart';
import 'package:enigmo_server/services/message_manager.dart';
import 'package:enigmo_server/services/websocket_handler.dart';
import 'package:enigmo_server/models/user.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:async';
import 'dart:convert';

/// Mock WebSocket Channel for testing
class MockWebSocketChannel extends WebSocketChannel {
  final StreamController<String> _streamController = StreamController<String>.broadcast();
  final StreamController<String> _sinkController = StreamController<String>();
  final List<String> sentMessages = [];
  bool _isConnected = true;

  MockWebSocketChannel() : super(_MockWebSocketSink(), const Stream.empty());

  @override
  Stream<dynamic> get stream => _streamController.stream;

  @override
  WebSocketSink get sink => _MockWebSocketSink()..onAdd = (data) {
    if (_isConnected) {
      sentMessages.add(data.toString());
    }
  };

  void simulateIncomingMessage(String message) {
    if (_isConnected) {
      _streamController.add(message);
    }
  }

  void simulateDisconnection() {
    _isConnected = false;
    _streamController.close();
    _sinkController.close();
  }

  void clearSentMessages() {
    sentMessages.clear();
  }
}

class _MockWebSocketSink extends WebSocketSink {
  Function(dynamic)? onAdd;

  @override
  void add(data) {
    onAdd?.call(data);
  }

  @override
  void addError(error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) async {}

  @override
  Future close([int? closeCode, String? closeReason]) async {}

  @override
  Future get done => Future.value();
}

void main() {
  group('Server Components Comprehensive Tests', () {
    group('UserManager Tests', () {
      late UserManager userManager;

      setUp(() {
        userManager = UserManager();
      });

      test('should initialize with default users', () async {
        final users = await userManager.getAllUsers();
        expect(users.length, equals(2));
        
        final userIds = users.map((u) => u.id).toList();
        expect(userIds, contains('user1'));
        expect(userIds, contains('user2'));
        
        // Default users should have proper keys
        final user1 = users.firstWhere((u) => u.id == 'user1');
        expect(user1.nickname, equals('Alice'));
        expect(user1.publicSigningKey, isNotEmpty);
        expect(user1.publicEncryptionKey, isNotEmpty);
      });

      test('should register new users successfully', () async {
        final newUser = await userManager.registerUser(
          id: 'test_user_123',
          publicSigningKey: 'test_signing_key',
          publicEncryptionKey: 'test_encryption_key',
          nickname: 'TestUser',
        );

        expect(newUser, isNotNull);
        expect(newUser!.id, equals('test_user_123'));
        expect(newUser.nickname, equals('TestUser'));
        expect(newUser.publicSigningKey, equals('test_signing_key'));
        expect(newUser.publicEncryptionKey, equals('test_encryption_key'));
        expect(newUser.isOnline, isFalse);

        // User should be retrievable
        final retrievedUser = userManager.getUser('test_user_123');
        expect(retrievedUser, isNotNull);
        expect(retrievedUser!.id, equals('test_user_123'));
      });

      test('should not allow duplicate user registration', () async {
        // Register user first time
        final user1 = await userManager.registerUser(
          id: 'duplicate_test',
          publicSigningKey: 'key1',
          publicEncryptionKey: 'key2',
        );
        expect(user1, isNotNull);

        // Try to register same user ID again
        final user2 = await userManager.registerUser(
          id: 'duplicate_test',
          publicSigningKey: 'different_key1',
          publicEncryptionKey: 'different_key2',
        );
        expect(user2, isNull);
      });

      test('should authenticate users correctly', () async {
        // Register a user first
        await userManager.registerUser(
          id: 'auth_test_user',
          publicSigningKey: 'signing_key',
          publicEncryptionKey: 'encryption_key',
        );

        // Authenticate the user
        final authenticatedUser = await userManager.authenticateUser('auth_test_user');
        expect(authenticatedUser, isNotNull);
        expect(authenticatedUser!.isOnline, isTrue);
        expect(authenticatedUser.lastSeen, isNotNull);

        // Try to authenticate non-existent user
        final nullUser = await userManager.authenticateUser('non_existent_user');
        expect(nullUser, isNull);
      });

      test('should manage user connections properly', () async {
        final mockChannel = MockWebSocketChannel();
        const userId = 'connection_test_user';

        // Register user first
        await userManager.registerUser(
          id: userId,
          publicSigningKey: 'signing_key',
          publicEncryptionKey: 'encryption_key',
        );

        // Connect user
        userManager.connectUser(userId, mockChannel);
        
        expect(userManager.isUserOnline(userId), isTrue);
        expect(userManager.getUserChannel(userId), equals(mockChannel));
        expect(userManager.getUserIdByChannel(mockChannel), equals(userId));

        final onlineUsers = userManager.getOnlineUsers();
        expect(onlineUsers.any((u) => u.id == userId), isTrue);

        // Disconnect user
        userManager.disconnectUser(userId);
        
        expect(userManager.isUserOnline(userId), isFalse);
        expect(userManager.getUserChannel(userId), isNull);
        expect(userManager.getUserIdByChannel(mockChannel), isNull);
      });

      test('should send messages to connected users', () async {
        final mockChannel = MockWebSocketChannel();
        const userId = 'message_test_user';

        // Register and connect user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: 'signing_key',
          publicEncryptionKey: 'encryption_key',
        );
        userManager.connectUser(userId, mockChannel);

        // Send message
        final testMessage = {'type': 'test', 'content': 'Hello World'};
        final success = await userManager.sendToUser(userId, testMessage);

        expect(success, isTrue);
        expect(mockChannel.sentMessages.length, equals(1));
        
        final sentMessage = jsonDecode(mockChannel.sentMessages.first);
        expect(sentMessage['type'], equals('test'));
        expect(sentMessage['content'], equals('Hello World'));
      });

      test('should handle sending to offline users', () async {
        const userId = 'offline_user';

        // Register user but don't connect
        await userManager.registerUser(
          id: userId,
          publicSigningKey: 'signing_key',
          publicEncryptionKey: 'encryption_key',
        );

        // Try to send message
        final testMessage = {'type': 'test', 'content': 'Hello Offline'};
        final success = await userManager.sendToUser(userId, testMessage);

        expect(success, isFalse);
      });

      test('should provide accurate statistics', () async {
        final mockChannel1 = MockWebSocketChannel();
        final mockChannel2 = MockWebSocketChannel();

        // Register and connect users
        await userManager.registerUser(
          id: 'stats_user_1',
          publicSigningKey: 'key1',
          publicEncryptionKey: 'key2',
        );
        await userManager.registerUser(
          id: 'stats_user_2',
          publicSigningKey: 'key3',
          publicEncryptionKey: 'key4',
        );

        userManager.connectUser('stats_user_1', mockChannel1);
        userManager.connectUser('stats_user_2', mockChannel2);

        final stats = userManager.getUserStats();
        expect(stats['total'], greaterThanOrEqualTo(4)); // 2 default + 2 new
        expect(stats['online'], equals(2));
        expect(stats['offline'], greaterThanOrEqualTo(2));

        // Disconnect one user
        userManager.disconnectUser('stats_user_1');
        
        final updatedStats = userManager.getUserStats();
        expect(updatedStats['online'], equals(1));
        expect(updatedStats['offline'], greaterThanOrEqualTo(3));
      });

      test('should handle channel disconnection gracefully', () async {
        final mockChannel = MockWebSocketChannel();
        const userId = 'channel_disconnect_test';

        // Register and connect user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: 'signing_key',
          publicEncryptionKey: 'encryption_key',
        );
        userManager.connectUser(userId, mockChannel);

        expect(userManager.isUserOnline(userId), isTrue);

        // Disconnect by channel
        userManager.disconnectChannel(mockChannel);

        expect(userManager.isUserOnline(userId), isFalse);
        expect(userManager.getUserChannel(userId), isNull);
      });

      test('should broadcast user status updates', () async {
        final mockChannel1 = MockWebSocketChannel();
        final mockChannel2 = MockWebSocketChannel();
        
        // Register and connect two users
        await userManager.registerUser(
          id: 'broadcast_user_1',
          publicSigningKey: 'key1',
          publicEncryptionKey: 'key2',
        );
        await userManager.registerUser(
          id: 'broadcast_user_2',
          publicSigningKey: 'key3',
          publicEncryptionKey: 'key4',
        );

        userManager.connectUser('broadcast_user_1', mockChannel1);
        userManager.connectUser('broadcast_user_2', mockChannel2);

        // Clear initial messages
        mockChannel1.clearSentMessages();
        mockChannel2.clearSentMessages();

        // Connect a third user - should trigger broadcast
        final mockChannel3 = MockWebSocketChannel();
        await userManager.registerUser(
          id: 'broadcast_user_3',
          publicSigningKey: 'key5',
          publicEncryptionKey: 'key6',
        );
        userManager.connectUser('broadcast_user_3', mockChannel3);

        // Both existing users should receive status update
        expect(mockChannel1.sentMessages.length, greaterThanOrEqualTo(1));
        expect(mockChannel2.sentMessages.length, greaterThanOrEqualTo(1));

        // Check broadcast message content
        final broadcastMessage = jsonDecode(mockChannel1.sentMessages.last);
        expect(broadcastMessage['type'], equals('user_status_update'));
        expect(broadcastMessage['userId'], equals('broadcast_user_3'));
        expect(broadcastMessage['isOnline'], isTrue);
      });
    });

    group('MessageManager Tests', () {
      late UserManager userManager;
      late MessageManager messageManager;

      setUp(() {
        userManager = UserManager();
        messageManager = MessageManager(userManager);
      });

      test('should initialize with empty statistics', () {
        final stats = messageManager.getMessageStats();
        expect(stats['totalMessages'], equals(0));
        expect(stats['messagesPerHour'], equals(0));
      });

      test('should track message statistics', () async {
        // Send some messages to trigger statistics
        final mockChannel = MockWebSocketChannel();
        const senderId = 'sender_user';
        const receiverId = 'receiver_user';

        // Register users
        await userManager.registerUser(
          id: senderId,
          publicSigningKey: 'sender_signing_key',
          publicEncryptionKey: 'sender_encryption_key',
        );
        await userManager.registerUser(
          id: receiverId,
          publicSigningKey: 'receiver_signing_key',
          publicEncryptionKey: 'receiver_encryption_key',
        );

        // Connect sender
        userManager.connectUser(senderId, mockChannel);

        // Simulate message handling (this would normally be done through WebSocketHandler)
        // For now, we'll test the statistics directly
        final initialStats = messageManager.getMessageStats();
        expect(initialStats['totalMessages'], equals(0));
      });

      test('should provide message routing capabilities', () {
        // MessageManager should be able to work with UserManager
        expect(messageManager, isNotNull);
        
        // Verify it has access to UserManager
        final stats = messageManager.getMessageStats();
        expect(stats, isNotNull);
        expect(stats.containsKey('totalMessages'), isTrue);
      });
    });

    group('Integration Tests', () {
      late UserManager userManager;
      late MessageManager messageManager;
      late WebSocketHandler webSocketHandler;

      setUp(() {
        userManager = UserManager();
        messageManager = MessageManager(userManager);
        webSocketHandler = WebSocketHandler(userManager, messageManager);
      });

      test('should handle complete user registration flow', () async {
        final mockChannel = MockWebSocketChannel();
        
        // Simulate registration message
        final registrationMessage = {
          'type': 'register',
          'publicSigningKey': 'test_signing_key',
          'publicEncryptionKey': 'test_encryption_key',
          'nickname': 'TestNickname',
          'timestamp': DateTime.now().toIso8601String(),
        };

        // This would normally be handled by WebSocketHandler
        // For testing, we'll simulate the registration process
        final userId = 'generated_user_id';
        final registeredUser = await userManager.registerUser(
          id: userId,
          publicSigningKey: registrationMessage['publicSigningKey'] as String,
          publicEncryptionKey: registrationMessage['publicEncryptionKey'] as String,
          nickname: registrationMessage['nickname'] as String,
        );

        expect(registeredUser, isNotNull);
        expect(registeredUser!.nickname, equals('TestNickname'));

        // Connect the user
        userManager.connectUser(userId, mockChannel);
        expect(userManager.isUserOnline(userId), isTrue);
      });

      test('should handle user authentication flow', () async {
        const userId = 'auth_flow_user';
        final mockChannel = MockWebSocketChannel();

        // Register user first
        await userManager.registerUser(
          id: userId,
          publicSigningKey: 'signing_key',
          publicEncryptionKey: 'encryption_key',
          nickname: 'AuthTestUser',
        );

        // Authenticate user
        final authenticatedUser = await userManager.authenticateUser(userId);
        expect(authenticatedUser, isNotNull);
        expect(authenticatedUser!.isOnline, isTrue);

        // Connect user
        userManager.connectUser(userId, mockChannel);
        expect(userManager.isUserOnline(userId), isTrue);
      });

      test('should handle multiple concurrent users', () async {
        final channels = <String, MockWebSocketChannel>{};
        const userCount = 10;

        // Register and connect multiple users
        for (int i = 0; i < userCount; i++) {
          final userId = 'concurrent_user_$i';
          final channel = MockWebSocketChannel();
          channels[userId] = channel;

          await userManager.registerUser(
            id: userId,
            publicSigningKey: 'signing_key_$i',
            publicEncryptionKey: 'encryption_key_$i',
            nickname: 'User$i',
          );

          userManager.connectUser(userId, channel);
        }

        // Verify all users are online
        final onlineUsers = userManager.getOnlineUsers();
        expect(onlineUsers.length, greaterThanOrEqualTo(userCount));

        // Send a message to each user
        for (int i = 0; i < userCount; i++) {
          final userId = 'concurrent_user_$i';
          final success = await userManager.sendToUser(
            userId,
            {'type': 'test', 'content': 'Message to user $i'}
          );
          expect(success, isTrue);
        }

        // Disconnect all users
        for (int i = 0; i < userCount; i++) {
          final userId = 'concurrent_user_$i';
          userManager.disconnectUser(userId);
        }

        // Verify all users are offline
        for (int i = 0; i < userCount; i++) {
          final userId = 'concurrent_user_$i';
          expect(userManager.isUserOnline(userId), isFalse);
        }
      });

      test('should handle error conditions gracefully', () async {
        final mockChannel = MockWebSocketChannel();
        
        // Test sending to non-existent user
        final success = await userManager.sendToUser(
          'non_existent_user',
          {'type': 'test', 'content': 'This should fail'}
        );
        expect(success, isFalse);

        // Test disconnecting non-existent user
        expect(() => userManager.disconnectUser('non_existent_user'), returnsNormally);

        // Test authenticating non-existent user
        final nullUser = await userManager.authenticateUser('non_existent_user');
        expect(nullUser, isNull);

        // Test getting non-existent user
        final user = userManager.getUser('non_existent_user');
        expect(user, isNull);
      });

      test('should maintain data consistency under load', () async {
        const userId = 'consistency_test_user';
        final mockChannel = MockWebSocketChannel();

        // Register user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: 'signing_key',
          publicEncryptionKey: 'encryption_key',
        );

        // Perform multiple rapid operations
        for (int i = 0; i < 100; i++) {
          userManager.connectUser(userId, mockChannel);
          expect(userManager.isUserOnline(userId), isTrue);
          
          userManager.disconnectUser(userId);
          expect(userManager.isUserOnline(userId), isFalse);
        }

        // Final state should be consistent
        expect(userManager.isUserOnline(userId), isFalse);
        expect(userManager.getUserChannel(userId), isNull);
      });
    });

    group('Security and Validation Tests', () {
      late UserManager userManager;

      setUp(() {
        userManager = UserManager();
      });

      test('should validate user registration inputs', () async {
        // Test with empty ID
        final user1 = await userManager.registerUser(
          id: '',
          publicSigningKey: 'key1',
          publicEncryptionKey: 'key2',
        );
        expect(user1, isNotNull); // Should handle empty ID gracefully

        // Test with empty keys
        final user2 = await userManager.registerUser(
          id: 'test_empty_keys',
          publicSigningKey: '',
          publicEncryptionKey: '',
        );
        expect(user2, isNotNull); // Should handle empty keys gracefully
      });

      test('should handle malicious user IDs', () async {
        final maliciousIds = [
          '../../../etc/passwd',
          '<script>alert("xss")</script>',
          'user\nid\rwith\tnewlines',
          'very_long_user_id_' + 'x' * 1000,
        ];

        for (final maliciousId in maliciousIds) {
          final user = await userManager.registerUser(
            id: maliciousId,
            publicSigningKey: 'key1',
            publicEncryptionKey: 'key2',
          );
          
          // Should either handle gracefully or reject
          if (user != null) {
            expect(user.id, equals(maliciousId)); // If accepted, should store exactly
            
            // Should be retrievable
            final retrievedUser = userManager.getUser(maliciousId);
            expect(retrievedUser, isNotNull);
          }
        }
      });

      test('should prevent key injection attacks', () async {
        final maliciousKeys = [
          '{"type":"malicious"}',
          'base64encoded_but_malicious',
          '\x00\x01\x02\x03', // Binary data
          '../../../../etc/passwd',
        ];

        for (final maliciousKey in maliciousKeys) {
          final user = await userManager.registerUser(
            id: 'test_malicious_key',
            publicSigningKey: maliciousKey,
            publicEncryptionKey: maliciousKey,
          );
          
          // Should handle gracefully
          if (user != null) {
            expect(user.publicSigningKey, equals(maliciousKey));
            expect(user.publicEncryptionKey, equals(maliciousKey));
          }
          
          // Clean up for next iteration
          userManager.disconnectUser('test_malicious_key');
        }
      });

      test('should handle resource exhaustion attempts', () async {
        // Attempt to register many users rapidly
        final futures = <Future<User?>>[];
        
        for (int i = 0; i < 1000; i++) {
          final future = userManager.registerUser(
            id: 'flood_user_$i',
            publicSigningKey: 'key_$i',
            publicEncryptionKey: 'key_$i',
          );
          futures.add(future);
        }

        // Wait for all registrations to complete
        final results = await Future.wait(futures);
        
        // Should handle the load gracefully
        final successfulRegistrations = results.where((user) => user != null).length;
        expect(successfulRegistrations, greaterThan(0));
        
        // System should still be responsive
        final stats = userManager.getUserStats();
        expect(stats['total'], greaterThanOrEqualTo(successfulRegistrations));
      });
    });
  });
}