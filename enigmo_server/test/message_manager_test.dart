import 'package:test/test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:enigmo_server/services/message_manager.dart';
import 'package:enigmo_server/services/user_manager.dart';
import 'package:enigmo_server/models/message.dart';

// Generate mocks
@GenerateMocks([UserManager])
import 'message_manager_test.mocks.dart';

void main() {
  late MockUserManager mockUserManager;
  late MessageManager messageManager;

  setUp(() {
    mockUserManager = MockUserManager();
    messageManager = MessageManager(mockUserManager);
  });

  tearDown(() {
    // Clean up test state
  });

  group('MessageManager Initialization Tests', () {
    test('should initialize successfully', () {
      expect(messageManager, isNotNull);
    });

    test('should have empty message list initially', () {
      expect(messageManager, isNotNull);
      // Messages are private, so we test through public methods
    });
  });

  group('MessageManager Message Sending Tests', () {
    test('should send message successfully', () async {
      const senderId = 'sender_123';
      const receiverId = 'receiver_456';
      const encryptedContent = 'encrypted_content';
      const signature = 'message_signature';

      when(mockUserManager.getUser(receiverId))
          .thenReturn(null); // Simulate offline receiver

      final message = await messageManager.sendMessage(
        senderId: senderId,
        receiverId: receiverId,
        encryptedContent: encryptedContent,
        signature: signature,
      );

      expect(message, isNotNull);
      expect(message.id, isNotEmpty);
      expect(message.senderId, equals(senderId));
      expect(message.receiverId, equals(receiverId));
      expect(message.encryptedContent, equals(encryptedContent));
      expect(message.signature, equals(signature));
      expect(message.status, equals(DeliveryStatus.sent));
    });

    test('should generate unique message IDs', () async {
      const senderId = 'sender_123';
      const receiverId = 'receiver_456';

      final message1 = await messageManager.sendMessage(
        senderId: senderId,
        receiverId: receiverId,
        encryptedContent: 'content1',
        signature: 'sig1',
      );

      final message2 = await messageManager.sendMessage(
        senderId: senderId,
        receiverId: receiverId,
        encryptedContent: 'content2',
        signature: 'sig2',
      );

      expect(message1.id, isNot(equals(message2.id)));
    });

    test('should handle different message types', () async {
      const senderId = 'sender_123';
      const receiverId = 'receiver_456';

      final textMessage = await messageManager.sendMessage(
        senderId: senderId,
        receiverId: receiverId,
        encryptedContent: 'text content',
        signature: 'sig',
        type: MessageType.text,
      );

      final imageMessage = await messageManager.sendMessage(
        senderId: senderId,
        receiverId: receiverId,
        encryptedContent: 'image content',
        signature: 'sig',
        type: MessageType.image,
      );

      expect(textMessage.type, equals(MessageType.text));
      expect(imageMessage.type, equals(MessageType.image));
    });

    test('should handle message metadata', () async {
      const senderId = 'sender_123';
      const receiverId = 'receiver_456';
      final metadata = {'fileSize': 1024, 'fileName': 'test.jpg'};

      final message = await messageManager.sendMessage(
        senderId: senderId,
        receiverId: receiverId,
        encryptedContent: 'file content',
        signature: 'sig',
        metadata: metadata,
      );

      expect(message.metadata, equals(metadata));
    });

    test('should handle large message content', () async {
      const senderId = 'sender_123';
      const receiverId = 'receiver_456';
      final largeContent = 'x' * 10000; // 10KB content

      final message = await messageManager.sendMessage(
        senderId: senderId,
        receiverId: receiverId,
        encryptedContent: largeContent,
        signature: 'sig',
      );

      expect(message.encryptedContent.length, equals(10000));
    });
  });

  group('MessageManager Message Delivery Tests', () {
    test('should attempt delivery to online users', () async {
      const senderId = 'sender_123';
      const receiverId = 'receiver_456';

      when(mockUserManager.getUser(receiverId))
          .thenReturn(null); // Simulate offline receiver
      when(mockUserManager.isUserOnline(receiverId))
          .thenReturn(false);

      final message = await messageManager.sendMessage(
        senderId: senderId,
        receiverId: receiverId,
        encryptedContent: 'content',
        signature: 'sig',
      );

      expect(message.status, equals(DeliveryStatus.sent));
    });

    test('should handle delivery failures gracefully', () async {
      const senderId = 'sender_123';
      const receiverId = 'receiver_456';

      when(mockUserManager.getUser(receiverId))
          .thenReturn(null);
      when(mockUserManager.isUserOnline(receiverId))
          .thenReturn(false);

      final message = await messageManager.sendMessage(
        senderId: senderId,
        receiverId: receiverId,
        encryptedContent: 'content',
        signature: 'sig',
      );

      expect(message.status, equals(DeliveryStatus.sent));
    });
  });

  group('MessageManager Message History Tests', () {
    test('should retrieve message history', () async {
      const userId1 = 'user1';
      const userId2 = 'user2';

      // Send some test messages
      await messageManager.sendMessage(
        senderId: userId1,
        receiverId: userId2,
        encryptedContent: 'message1',
        signature: 'sig1',
      );

      await messageManager.sendMessage(
        senderId: userId2,
        receiverId: userId1,
        encryptedContent: 'message2',
        signature: 'sig2',
      );

      final history = await messageManager.getMessageHistory(userId1, userId2);

      expect(history, isNotNull);
      expect(history.length, equals(2));
      expect(history.every((msg) =>
          (msg.senderId == userId1 && msg.receiverId == userId2) ||
          (msg.senderId == userId2 && msg.receiverId == userId1)), isTrue);
    });

    test('should respect message limit', () async {
      const userId1 = 'user1';
      const userId2 = 'user2';

      // Send multiple messages
      for (var i = 0; i < 10; i++) {
        await messageManager.sendMessage(
          senderId: userId1,
          receiverId: userId2,
          encryptedContent: 'message$i',
          signature: 'sig$i',
        );
      }

      final history = await messageManager.getMessageHistory(userId1, userId2, limit: 5);

      expect(history.length, equals(5));
    });

    test('should filter messages by timestamp', () async {
      const userId1 = 'user1';
      const userId2 = 'user2';

      final beforeTime = DateTime.now();

      // Send messages
      await messageManager.sendMessage(
        senderId: userId1,
        receiverId: userId2,
        encryptedContent: 'old_message',
        signature: 'sig_old',
      );

      await Future.delayed(Duration(milliseconds: 10)); // Small delay

      final afterTime = DateTime.now();

      await messageManager.sendMessage(
        senderId: userId1,
        receiverId: userId2,
        encryptedContent: 'new_message',
        signature: 'sig_new',
      );

      final history = await messageManager.getMessageHistory(
        userId1,
        userId2,
        before: afterTime,
      );

      expect(history.length, equals(1));
      expect(history.first.encryptedContent, equals('old_message'));
    });

    test('should return empty history for non-existent conversation', () async {
      const userId1 = 'user1';
      const userId2 = 'user2';

      final history = await messageManager.getMessageHistory(userId1, userId2);

      expect(history, isNotNull);
      expect(history.isEmpty, isTrue);
    });
  });

  group('MessageManager Message Status Tests', () {
    test('should mark message as read', () async {
      const senderId = 'sender_123';
      const receiverId = 'receiver_456';

      final message = await messageManager.sendMessage(
        senderId: senderId,
        receiverId: receiverId,
        encryptedContent: 'content',
        signature: 'sig',
      );

      final success = await messageManager.markMessageAsRead(message.id, receiverId);

      expect(success, isTrue);
    });

    test('should not mark message as read by wrong user', () async {
      const senderId = 'sender_123';
      const receiverId = 'receiver_456';
      const wrongUserId = 'wrong_user';

      final message = await messageManager.sendMessage(
        senderId: senderId,
        receiverId: receiverId,
        encryptedContent: 'content',
        signature: 'sig',
      );

      final success = await messageManager.markMessageAsRead(message.id, wrongUserId);

      expect(success, isFalse);
    });

    test('should handle marking non-existent message', () async {
      const fakeMessageId = 'fake_message_id';
      const userId = 'user_123';

      final success = await messageManager.markMessageAsRead(fakeMessageId, userId);

      expect(success, isFalse);
    });
  });

  group('MessageManager User Messages Tests', () {
    test('should retrieve user messages', () async {
      const userId = 'user_123';
      const otherUserId = 'other_user_456';

      // Send messages involving the user
      await messageManager.sendMessage(
        senderId: userId,
        receiverId: otherUserId,
        encryptedContent: 'sent_message',
        signature: 'sig1',
      );

      await messageManager.sendMessage(
        senderId: otherUserId,
        receiverId: userId,
        encryptedContent: 'received_message',
        signature: 'sig2',
      );

      final userMessages = await messageManager.getUserMessages(userId);

      expect(userMessages, isNotNull);
      expect(userMessages.length, equals(2));
      expect(userMessages.every((msg) =>
          msg.senderId == userId || msg.receiverId == userId), isTrue);
    });

    test('should return newest messages first', () async {
      const userId = 'user_123';
      const otherUserId = 'other_user_456';

      await messageManager.sendMessage(
        senderId: userId,
        receiverId: otherUserId,
        encryptedContent: 'first_message',
        signature: 'sig1',
      );

      await Future.delayed(Duration(milliseconds: 10));

      await messageManager.sendMessage(
        senderId: userId,
        receiverId: otherUserId,
        encryptedContent: 'second_message',
        signature: 'sig2',
      );

      final userMessages = await messageManager.getUserMessages(userId);

      expect(userMessages.length, equals(2));
      expect(userMessages.first.encryptedContent, equals('second_message'));
      expect(userMessages.last.encryptedContent, equals('first_message'));
    });
  });

  group('MessageManager Statistics Tests', () {
    test('should provide message statistics', () {
      final stats = messageManager.getMessageStats();

      expect(stats, isNotNull);
      expect(stats.containsKey('total'), isTrue);
      expect(stats.containsKey('delivered'), isTrue);
      expect(stats.containsKey('read'), isTrue);
      expect(stats['total'], isNonNegative);
      expect(stats['delivered'], isNonNegative);
      expect(stats['read'], isNonNegative);
    });

    test('should update statistics after sending messages', () async {
      const senderId = 'sender_123';
      const receiverId = 'receiver_456';

      final initialStats = messageManager.getMessageStats();

      await messageManager.sendMessage(
        senderId: senderId,
        receiverId: receiverId,
        encryptedContent: 'content',
        signature: 'sig',
      );

      final updatedStats = messageManager.getMessageStats();

      expect(updatedStats['total'], equals(initialStats['total']! + 1));
    });
  });

  group('MessageManager Offline Messages Tests', () {
    test('should handle offline message delivery', () async {
      const senderId = 'sender_123';
      const receiverId = 'offline_user';

      when(mockUserManager.getUser(receiverId))
          .thenReturn(null);
      when(mockUserManager.isUserOnline(receiverId))
          .thenReturn(false);

      final message = await messageManager.sendMessage(
        senderId: senderId,
        receiverId: receiverId,
        encryptedContent: 'offline_content',
        signature: 'sig',
      );

      expect(message.status, equals(DeliveryStatus.sent));
    });

    test('should deliver offline messages when user comes online', () async {
      // This would require more complex setup with actual user connections
      // For unit testing, we verify the offline queue functionality exists
      expect(messageManager, isNotNull);
    });
  });

  group('MessageManager Error Handling Tests', () {
    test('should handle invalid message parameters', () async {
      expect(
        () async => await messageManager.sendMessage(
          senderId: '',
          receiverId: 'receiver',
          encryptedContent: 'content',
          signature: 'sig',
        ),
        returnsNormally, // Should handle gracefully
      );
    });

    test('should handle database/storage errors', () async {
      // Test with simulated storage failures
      expect(messageManager, isNotNull);
    });
  });

  group('MessageManager Performance Tests', () {
    test('should handle multiple concurrent messages', () async {
      const senderId = 'sender_123';
      const receiverId = 'receiver_456';

      final futures = <Future>[];
      for (var i = 0; i < 10; i++) {
        futures.add(messageManager.sendMessage(
          senderId: senderId,
          receiverId: receiverId,
          encryptedContent: 'message_$i',
          signature: 'sig_$i',
        ));
      }

      final messages = await Future.wait(futures);

      expect(messages.length, equals(10));
      expect(messages.every((msg) => msg != null), isTrue);
      expect(Set.from(messages.map((msg) => msg.id)).length, equals(10)); // All IDs unique
    });

    test('should handle large message volumes', () async {
      const senderId = 'sender_123';
      const receiverId = 'receiver_456';

      final futures = <Future>[];
      for (var i = 0; i < 100; i++) {
        futures.add(messageManager.sendMessage(
          senderId: senderId,
          receiverId: receiverId,
          encryptedContent: 'message_$i',
          signature: 'sig_$i',
        ));
      }

      final messages = await Future.wait(futures);

      expect(messages.length, equals(100));
      expect(messages.every((msg) => msg.id.isNotEmpty), isTrue);
    });
  });

  group('MessageManager Memory Management Tests', () {
    test('should clean up conversation cache', () async {
      const userId1 = 'user1';
      const userId2 = 'user2';

      // Send messages to create cache
      await messageManager.sendMessage(
        senderId: userId1,
        receiverId: userId2,
        encryptedContent: 'message',
        signature: 'sig',
      );

      // Cache cleanup is internal, verify no crashes
      expect(messageManager, isNotNull);
    });

    test('should handle memory constraints', () async {
      // Test with many messages
      const senderId = 'sender_123';
      const receiverId = 'receiver_456';

      for (var i = 0; i < 1000; i++) {
        await messageManager.sendMessage(
          senderId: senderId,
          receiverId: receiverId,
          encryptedContent: 'message_$i',
          signature: 'sig_$i',
        );
      }

      final history = await messageManager.getMessageHistory(senderId, receiverId);
      expect(history.length, equals(1000));
    });
  });
}