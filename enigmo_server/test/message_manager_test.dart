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

      // Регистрируем тестовых пользователей
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

    test('должен успешно отправить сообщение', () async {
      final message = await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Привет, как дела?',
        signature: 'test_signature',
        type: MessageType.text,
      );

      expect(message, isNotNull);
      expect(message.senderId, equals('sender_123'));
      expect(message.receiverId, equals('receiver_456'));
      expect(message.encryptedContent, equals('Привет, как дела?'));
      expect(message.signature, equals('test_signature'));
      expect(message.type, equals(MessageType.text));
      expect(message.status, equals(DeliveryStatus.sent));
      expect(message.id, isNotEmpty);
    });

    test('должен получить историю сообщений между пользователями', () async {
      // Отправляем несколько сообщений
      await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Сообщение 1',
        signature: 'sig1',
      );

      await messageManager.sendMessage(
        senderId: 'receiver_456',
        receiverId: 'sender_123',
        encryptedContent: 'Сообщение 2',
        signature: 'sig2',
      );

      await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Сообщение 3',
        signature: 'sig3',
      );

      // Получаем историю
      final history = await messageManager.getMessageHistory(
        'sender_123',
        'receiver_456',
        limit: 10,
      );

      expect(history.length, equals(3));
      expect(history[0].encryptedContent, equals('Сообщение 1'));
      expect(history[1].encryptedContent, equals('Сообщение 2'));
      expect(history[2].encryptedContent, equals('Сообщение 3'));
    });

    test('должен ограничить количество сообщений в истории', () async {
      // Отправляем 5 сообщений
      for (int i = 1; i <= 5; i++) {
        await messageManager.sendMessage(
          senderId: 'sender_123',
          receiverId: 'receiver_456',
          encryptedContent: 'Сообщение $i',
          signature: 'sig$i',
        );
      }

      // Получаем историю с лимитом 3
      final history = await messageManager.getMessageHistory(
        'sender_123',
        'receiver_456',
        limit: 3,
      );

      expect(history.length, equals(3));
      // Должны получить последние 3 сообщения
      expect(history[0].encryptedContent, equals('Сообщение 3'));
      expect(history[1].encryptedContent, equals('Сообщение 4'));
      expect(history[2].encryptedContent, equals('Сообщение 5'));
    });

    test('должен фильтровать историю по времени', () async {
      // Отправляем первое сообщение
      await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Старое сообщение',
        signature: 'sig1',
      );

      // Ждем немного и запоминаем время
      await Future.delayed(const Duration(milliseconds: 100));
      final cutoffTime = DateTime.now();
      await Future.delayed(const Duration(milliseconds: 100));

      // Отправляем второе сообщение после cutoffTime
      await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Новое сообщение',
        signature: 'sig2',
      );

      // Получаем историю до cutoffTime
      final history = await messageManager.getMessageHistory(
        'sender_123',
        'receiver_456',
        before: cutoffTime,
      );

      // Должно быть только одно сообщение (старое)
      expect(history.length, equals(1));
      expect(history[0].encryptedContent, equals('Старое сообщение'));
    });

    test('должен помечать сообщение как прочитанное', () async {
      // Отправляем сообщение
      final message = await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Тестовое сообщение',
        signature: 'test_sig',
      );

      // Помечаем как прочитанное
      final success = await messageManager.markMessageAsRead(
        message.id,
        'receiver_456',
      );

      expect(success, isTrue);
    });

    test('не должен позволить пометить сообщение как прочитанное не получателю', () async {
      // Отправляем сообщение
      final message = await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Тестовое сообщение',
        signature: 'test_sig',
      );

      // Пытаемся пометить как прочитанное от имени отправителя
      final success = await messageManager.markMessageAsRead(
        message.id,
        'sender_123',
      );

      expect(success, isFalse);
    });

    test('должен получить сообщения пользователя', () async {
      // Отправляем сообщения
      await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Исходящее сообщение',
        signature: 'sig1',
      );

      await messageManager.sendMessage(
        senderId: 'receiver_456',
        receiverId: 'sender_123',
        encryptedContent: 'Входящее сообщение',
        signature: 'sig2',
      );

      // Получаем сообщения пользователя sender_123
      final userMessages = await messageManager.getUserMessages('sender_123');

      expect(userMessages.length, equals(2));
      // Сообщения должны быть отсортированы по времени (новые первыми)
      expect(userMessages[0].encryptedContent, equals('Входящее сообщение'));
      expect(userMessages[1].encryptedContent, equals('Исходящее сообщение'));
    });

    test('должен получить статистику сообщений', () async {
      // Отправляем сообщение
      final message = await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Статистическое сообщение',
        signature: 'stat_sig',
      );

      // Помечаем как прочитанное
      await messageManager.markMessageAsRead(message.id, 'receiver_456');

      final stats = messageManager.getMessageStats();

      expect(stats, isA<Map<String, dynamic>>());
      expect(stats['total'], isA<int>());
      expect(stats['delivered'], isA<int>());
      expect(stats['read'], isA<int>());
      expect(stats['total'], greaterThanOrEqualTo(1));
      expect(stats['read'], greaterThanOrEqualTo(1));
    });

    test('должен обрабатывать различные типы сообщений', () async {
      // Тестируем разные типы сообщений
      final textMessage = await messageManager.sendMessage(
        senderId: 'sender_123',
        receiverId: 'receiver_456',
        encryptedContent: 'Текстовое сообщение',
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

    test('должен обрабатывать метаданные сообщений', () async {
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