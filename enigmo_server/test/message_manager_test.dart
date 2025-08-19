import 'package:test/test.dart';
import 'package:enigmo_server/services/message_manager.dart';
import 'package:enigmo_server/services/user_manager.dart';
import 'package:enigmo_server/models/message.dart';

void main() {
  group('MessageManager Tests', () {
    late MessageManager messageManager;
    late UserManager userManager;

    setUp(() async {
      userManager = UserManager();
      messageManager = MessageManager(userManager);

      // Register test users
      await userManager.registerUser(
        id: 'sender_123',
        publicSigningKey: 'sender_key',
        publicEncryptionKey: 'sender_enc_key',
        nickname: 'Sender User',
      );

      await userManager.registerUser(
        id: 'receiver_456',
        publicSigningKey: 'receiver_key',
        publicEncryptionKey: 'receiver_enc_key',
        nickname: 'Receiver User',
      );
    });

    test('should successfully send a message', () async {
      final message = await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Hello, how are you?',
        signature: 'test_signature',
        type: MessageType.text,
      );

      expect(message, isNotNull);
      expect(message.senderId, equals('sender_123'));
      expect(message.receiverId, equals('receiver_456'));
      expect(message.encryptedContent, equals('Hello, how are you?'));
      expect(message.signature, equals('test_signature'));
      expect(message.type, equals(MessageType.text));
      expect(message.status, equals(DeliveryStatus.sent));
      expect(message.id, isNotEmpty);
    });

    test('should get message history between users', () async {
      // Send multiple messages
      await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Message 1',
        signature: 'sig1',
      );

      await messageManager.sendMessage(
        senderId: 'receiver_456',
        receiverId: 'sender_123',
        encryptedContent: 'Message 2',
        signature: 'sig2',
      );

      await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Message 3',
        signature: 'sig3',
      );

      // Get history
      final history = await messageManager.getMessageHistory(
        'sender_123',
        'receiver_456',
        limit: 10,
      );

      expect(history.length, equals(3));
      expect(history[0].encryptedContent, equals('Message 1'));
      expect(history[1].encryptedContent, equals('Message 2'));
      expect(history[2].encryptedContent, equals('Message 3'));
    });

    test('should limit the number of messages in history', () async {
      // Send 5 messages
      for (int i = 1; i <= 5; i++) {
        await messageManager.sendMessage(
          senderId: 'sender_123',
          receiverId: 'receiver_456',
          encryptedContent: 'Message $i',
          signature: 'sig$i',
        );
      }

      // Get history with a limit of 3
      final history = await messageManager.getMessageHistory(
        'sender_123',
        'receiver_456',
        limit: 3,
      );

      expect(history.length, equals(3));
      // Should get the last 3 messages
      expect(history[0].encryptedContent, equals('Message 3'));
      expect(history[1].encryptedContent, equals('Message 4'));
      expect(history[2].encryptedContent, equals('Message 5'));
    });

    test('should filter history by time', () async {
      // Send the first message
      await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Old message',
        signature: 'sig1',
      );

      // Wait a bit and remember the time
      await Future.delayed(const Duration(milliseconds: 100));
      final cutoffTime = DateTime.now();
      await Future.delayed(const Duration(milliseconds: 100));

      // Send the second message after cutoffTime
      await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'New message',
        signature: 'sig2',
      );

      // Get history before cutoffTime
      final history = await messageManager.getMessageHistory(
        'sender_123',
        'receiver_456',
        before: cutoffTime,
      );

      // There should be only one message (the old one)
      expect(history.length, equals(1));
      expect(history[0].encryptedContent, equals('Old message'));
    });

    test('should mark a message as read', () async {
      // Send a message
      final message = await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Test message',
        signature: 'test_sig',
      );

      // Mark as read
      final success = await messageManager.markMessageAsRead(
        message.id,
        'receiver_456',
      );

      expect(success, isTrue);
    });

    test('should not allow marking as read by non-receiver', () async {
      // Send a message
      final message = await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Test message',
        signature: 'test_sig',
      );

      // Try to mark as read on behalf of the sender
      final success = await messageManager.markMessageAsRead(
        message.id,
        'sender_123',
      );

      expect(success, isFalse);
    });

    test('should get user messages', () async {
      // Send messages
      await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Outgoing message',
        signature: 'sig1',
      );

      await messageManager.sendMessage(
        senderId: 'receiver_456',
        receiverId: 'sender_123',
        encryptedContent: 'Incoming message',
        signature: 'sig2',
      );

      // Get messages for user sender_123
      final userMessages = await messageManager.getUserMessages('sender_123');

      expect(userMessages.length, equals(2));
      // Messages should be sorted by time (newest first)
      expect(userMessages[0].encryptedContent, equals('Incoming message'));
      expect(userMessages[1].encryptedContent, equals('Outgoing message'));
    });

    test('should get message statistics', () async {
      // Send a message
      final message = await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Statistical message',
        signature: 'stat_sig',
      );

      // Mark as read
      await messageManager.markMessageAsRead(message.id, 'receiver_456');

      final stats = messageManager.getMessageStats();

      expect(stats, isA<Map<String, dynamic>>());
      expect(stats['total'], isA<int>());
      expect(stats['delivered'], isA<int>());
      expect(stats['read'], isA<int>());
      expect(stats['total'], greaterThanOrEqualTo(1));
      expect(stats['read'], greaterThanOrEqualTo(1));
    });

    test('should handle different message types', () async {
      // Test different message types
      final textMessage = await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Text message',
        signature: 'sig1',
        type: MessageType.text,
      );

      final imageMessage = await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'base64_image_data',
        signature: 'sig2',
        type: MessageType.image,
      );

      final fileMessage = await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'file_data',
        signature: 'sig3',
        type: MessageType.file,
      );

      expect(textMessage.type, equals(MessageType.text));
      expect(imageMessage.type, equals(MessageType.image));
      expect(fileMessage.type, equals(MessageType.file));
    });

    test('should handle message metadata', () async {
      final metadata = {
        'fileName': 'document.pdf',
        'fileSize': 1024,
        'mimeType': 'application/pdf',
      };

      final message = await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'file_content',
        signature: 'meta_sig',
        type: MessageType.file,
        metadata: metadata,
      );

      expect(message.metadata, isNotNull);
      expect(message.metadata!['fileName'], equals('document.pdf'));
      expect(message.metadata!['fileSize'], equals(1024));
      expect(message.metadata!['mimeType'], equals('application/pdf'));
    });
  });
}