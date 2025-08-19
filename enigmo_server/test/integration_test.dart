import 'package:test/test.dart';
import 'package:enigmo_server/services/user_manager.dart';
import 'package:enigmo_server/services/message_manager.dart';
import 'package:enigmo_server/services/auth_service.dart';
import 'package:enigmo_server/services/websocket_handler.dart';
import 'package:enigmo_server/models/user.dart';
import 'package:enigmo_server/models/message.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';

void main() {
  group('Integration Tests', () {
    late UserManager userManager;
    late MessageManager messageManager;
    late AuthService authService;
    late WebSocketHandler webSocketHandler;

    setUp(() {
      userManager = UserManager();
      messageManager = MessageManager(userManager);
      authService = AuthService(userManager);
      webSocketHandler = WebSocketHandler(userManager, messageManager);
    });

    group('Full registration and authentication flow', () {
      test('should register a user and authenticate successfully', () async {
        // Create test keys
        final ed25519 = Ed25519();
        final keyPair = await ed25519.newKeyPair();
        final publicKey = await keyPair.extractPublicKey();
        final publicKeyString = base64Encode(publicKey.bytes);

        // Register user
        final user = await userManager.registerUser(
          id: 'integration_user_1',
          publicSigningKey: publicKeyString,
          publicEncryptionKey: 'test_encryption_key',
          nickname: 'Integration User',
        );

        expect(user, isNotNull);
        expect(user!.id, equals('integration_user_1'));

        // Create signature for authentication
        final timestamp = DateTime.now().toIso8601String();
        final dataBytes = utf8.encode(timestamp);
        final signature = await ed25519.sign(dataBytes, keyPair: keyPair);
        final signatureString = base64Encode(signature.bytes);

        // Authenticate user
        final isAuthenticated = await authService.authenticateUser(
          'integration_user_1',
          signatureString,
          timestamp,
        );

        expect(isAuthenticated, isTrue);

        // Verify the user is marked as authenticated
        final authenticatedUser = await userManager.authenticateUser('integration_user_1');
        expect(authenticatedUser, isNotNull);
        expect(authenticatedUser!.isOnline, isTrue);
      });
    });

    group('Full messaging flow', () {
      test('should send a message between two users', () async {
        // Register two users
        await userManager.registerUser(
          id: 'sender_integration',
          publicSigningKey: 'sender_key',
          publicEncryptionKey: 'sender_enc_key',
          nickname: 'Sender',
        );

        await userManager.registerUser(
          id: 'receiver_integration',
          publicSigningKey: 'receiver_key',
          publicEncryptionKey: 'receiver_enc_key',
          nickname: 'Receiver',
        );

        // Send a message
        final message = await messageManager.sendMessage(
          senderId: 'sender_integration',
          receiverId: 'receiver_integration',
          encryptedContent: 'Integration test message',
          signature: 'test_signature',
          type: MessageType.text,
        );

        expect(message, isNotNull);
        expect(message.senderId, equals('sender_integration'));
        expect(message.receiverId, equals('receiver_integration'));
        expect(message.encryptedContent, equals('Integration test message'));

        // Get message history
        final history = await messageManager.getMessageHistory(
          'sender_integration',
          'receiver_integration',
        );

        expect(history.length, equals(1));
        expect(history[0].id, equals(message.id));
        expect(history[0].encryptedContent, equals('Integration test message'));
      });

      test('should process bidirectional conversation', () async {
        // Register users
        await userManager.registerUser(
          id: 'user_a',
          publicSigningKey: 'key_a',
          publicEncryptionKey: 'enc_key_a',
          nickname: 'User A',
        );

        await userManager.registerUser(
          id: 'user_b',
          publicSigningKey: 'key_b',
          publicEncryptionKey: 'enc_key_b',
          nickname: 'User B',
        );

        // User A sends a message to User B
        final message1 = await messageManager.sendMessage(
          senderId: 'user_a',
          receiverId: 'user_b',
          encryptedContent: 'Hello from A',
          signature: 'sig_a1',
        );

        // User B replies to User A
        final message2 = await messageManager.sendMessage(
          senderId: 'user_b',
          receiverId: 'user_a',
          encryptedContent: 'Hello from B',
          signature: 'sig_b1',
        );

        // User A sends another message
        final message3 = await messageManager.sendMessage(
          senderId: 'user_a',
          receiverId: 'user_b',
          encryptedContent: 'How are you?',
          signature: 'sig_a2',
        );

        // Get history for User A
        final historyA = await messageManager.getMessageHistory('user_a', 'user_b');
        expect(historyA.length, equals(3));
        expect(historyA[0].encryptedContent, equals('Hello from A'));
        expect(historyA[1].encryptedContent, equals('Hello from B'));
        expect(historyA[2].encryptedContent, equals('How are you?'));

        // Get history for User B (should be the same)
        final historyB = await messageManager.getMessageHistory('user_b', 'user_a');
        expect(historyB.length, equals(3));
        expect(historyB[0].encryptedContent, equals('Hello from A'));
        expect(historyB[1].encryptedContent, equals('Hello from B'));
        expect(historyB[2].encryptedContent, equals('How are you?'));
      });
    });

    group('Message read status', () {
      test('should handle full message status lifecycle', () async {
        // Register users
        await userManager.registerUser(
          id: 'status_sender',
          publicSigningKey: 'status_sender_key',
          publicEncryptionKey: 'status_sender_enc',
          nickname: 'Status Sender',
        );

        await userManager.registerUser(
          id: 'status_receiver',
          publicSigningKey: 'status_receiver_key',
          publicEncryptionKey: 'status_receiver_enc',
          nickname: 'Status Receiver',
        );

        // Send a message
        final message = await messageManager.sendMessage(
          senderId: 'status_sender',
          receiverId: 'status_receiver',
          encryptedContent: 'Message for status check',
          signature: 'status_sig',
        );

        // Check initial status
        expect(message.status, equals(DeliveryStatus.sent));

        // Mark as read by the receiver
        final readSuccess = await messageManager.markMessageAsRead(
          message.id,
          'status_receiver',
        );

        expect(readSuccess, isTrue);

        // Check statistics
        final stats = messageManager.getMessageStats();
        expect(stats['total'], greaterThanOrEqualTo(1));
        expect(stats['read'], greaterThanOrEqualTo(1));
      });
    });

    group('Online user management', () {
      test('should correctly track user status', () async {
        // Register a user
        await userManager.registerUser(
          id: 'online_test_user',
          publicSigningKey: 'online_key',
          publicEncryptionKey: 'online_enc_key',
          nickname: 'Online Test User',
        );

        // Check initial status
        expect(userManager.isUserOnline('online_test_user'), isFalse);

        // Authenticate the user
        await userManager.authenticateUser('online_test_user');

        // The user is still offline until WebSocket is connected
        expect(userManager.isUserOnline('online_test_user'), isFalse);

        // Get the list of online users
        final onlineUsers = userManager.getOnlineUsers();
        final onlineUser = onlineUsers.firstWhere(
          (u) => u.id == 'online_test_user',
          orElse: () => throw StateError('User not found'),
        );
        expect(onlineUser.isOnline, isTrue);

        // Disconnect the user
        userManager.disconnectUser('online_test_user');
        expect(userManager.isUserOnline('online_test_user'), isFalse);
      });
    });

    group('System statistics', () {
      test('should provide correct statistics', () async {
        // Register multiple users
        await userManager.registerUser(
          id: 'stats_user_1',
          publicSigningKey: 'stats_key_1',
          publicEncryptionKey: 'stats_enc_1',
          nickname: 'Stats User 1',
        );

        await userManager.registerUser(
          id: 'stats_user_2',
          publicSigningKey: 'stats_key_2',
          publicEncryptionKey: 'stats_enc_2',
          nickname: 'Stats User 2',
        );

        // Send messages
        await messageManager.sendMessage(
          senderId: 'stats_user_1',
          receiverId: 'stats_user_2',
          encryptedContent: 'Statistical message 1',
          signature: 'stats_sig_1',
        );

        final message2 = await messageManager.sendMessage(
          senderId: 'stats_user_2',
          receiverId: 'stats_user_1',
          encryptedContent: 'Statistical message 2',
          signature: 'stats_sig_2',
        );

        // Mark one message as read
        await messageManager.markMessageAsRead(message2.id, 'stats_user_1');

        // Get user statistics
        final userStats = userManager.getUserStats();
        expect(userStats['total'], greaterThanOrEqualTo(2));
        expect(userStats['online'], isA<int>());
        expect(userStats['offline'], isA<int>());

        // Get message statistics
        final messageStats = messageManager.getMessageStats();
        expect(messageStats['total'], greaterThanOrEqualTo(2));
        expect(messageStats['delivered'], isA<int>());
        expect(messageStats['read'], greaterThanOrEqualTo(1));
      });
    });

    group('Error handling', () {
      test('should handle authentication attempt for non-existent user', () async {
        final isAuthenticated = await authService.authenticateUser(
          'nonexistent_user',
          'fake_signature',
          DateTime.now().toIso8601String(),
        );

        expect(isAuthenticated, isFalse);
      });

      test('should handle sending a message to a non-existent user', () async {
        // Register only the sender
        await userManager.registerUser(
          id: 'sender_only',
          publicSigningKey: 'sender_key',
          publicEncryptionKey: 'sender_enc',
          nickname: 'Sender Only',
        );

        // Try to send a message to a non-existent receiver
        final message = await messageManager.sendMessage(
          senderId: 'sender_only',
          receiverId: 'nonexistent_receiver',
          encryptedContent: 'Message to nowhere',
          signature: 'nowhere_sig',
        );

        // The message should be created but not delivered
        expect(message, isNotNull);
        expect(message.receiverId, equals('nonexistent_receiver'));
        expect(message.status, equals(DeliveryStatus.sent));
      });

      test('should handle attempt to mark a non-existent message as read', () async {
        final success = await messageManager.markMessageAsRead(
          'nonexistent_message_id',
          'any_user_id',
        );

        expect(success, isFalse);
      });
    });
  });
}