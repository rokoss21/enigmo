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

    group('Полный цикл регистрации и аутентификации', () {
      test('должен зарегистрировать пользователя и успешно аутентифицировать', () async {
        // Создаем тестовые ключи
        final ed25519 = Ed25519();
        final keyPair = await ed25519.newKeyPair();
        final publicKey = await keyPair.extractPublicKey();
        final publicKeyString = base64Encode(publicKey.bytes);

        // Регистрируем пользователя
        final user = await userManager.registerUser(
          id: 'integration_user_1',
          publicSigningKey: publicKeyString,
          publicEncryptionKey: 'test_encryption_key',
          nickname: 'Integration User',
        );

        expect(user, isNotNull);
        expect(user!.id, equals('integration_user_1'));

        // Создаем подпись для аутентификации
        final timestamp = DateTime.now().toIso8601String();
        final dataBytes = utf8.encode(timestamp);
        final signature = await ed25519.sign(dataBytes, keyPair: keyPair);
        final signatureString = base64Encode(signature.bytes);

        // Аутентифицируем пользователя
        final isAuthenticated = await authService.authenticateUser(
          'integration_user_1',
          signatureString,
          timestamp,
        );

        expect(isAuthenticated, isTrue);

        // Проверяем, что пользователь помечен как аутентифицированный
        final authenticatedUser = await userManager.authenticateUser('integration_user_1');
        expect(authenticatedUser, isNotNull);
        expect(authenticatedUser!.isOnline, isTrue);
      });
    });

    group('Полный цикл обмена сообщениями', () {
      test('должен отправить сообщение между двумя пользователями', () async {
        // Регистрируем двух пользователей
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

        // Отправляем сообщение
        final message = await messageManager.sendMessage(
          senderId: 'sender_integration',
          receiverId: 'receiver_integration',
          encryptedContent: 'Интеграционное тестовое сообщение',
          signature: 'test_signature',
          type: MessageType.text,
        );

        expect(message, isNotNull);
        expect(message.senderId, equals('sender_integration'));
        expect(message.receiverId, equals('receiver_integration'));
        expect(message.encryptedContent, equals('Интеграционное тестовое сообщение'));

        // Получаем историю сообщений
        final history = await messageManager.getMessageHistory(
          'sender_integration',
          'receiver_integration',
        );

        expect(history.length, equals(1));
        expect(history[0].id, equals(message.id));
        expect(history[0].encryptedContent, equals('Интеграционное тестовое сообщение'));
      });

      test('должен обработать двустороннюю переписку', () async {
        // Регистрируем пользователей
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

        // User A отправляет сообщение User B
        final message1 = await messageManager.sendMessage(
          senderId: 'user_a',
          receiverId: 'user_b',
          encryptedContent: 'Привет от A',
          signature: 'sig_a1',
        );

        // User B отвечает User A
        final message2 = await messageManager.sendMessage(
          senderId: 'user_b',
          receiverId: 'user_a',
          encryptedContent: 'Привет от B',
          signature: 'sig_b1',
        );

        // User A отправляет еще одно сообщение
        final message3 = await messageManager.sendMessage(
          senderId: 'user_a',
          receiverId: 'user_b',
          encryptedContent: 'Как дела?',
          signature: 'sig_a2',
        );

        // Получаем историю для User A
        final historyA = await messageManager.getMessageHistory('user_a', 'user_b');
        expect(historyA.length, equals(3));
        expect(historyA[0].encryptedContent, equals('Привет от A'));
        expect(historyA[1].encryptedContent, equals('Привет от B'));
        expect(historyA[2].encryptedContent, equals('Как дела?'));

        // Получаем историю для User B (должна быть такой же)
        final historyB = await messageManager.getMessageHistory('user_b', 'user_a');
        expect(historyB.length, equals(3));
        expect(historyB[0].encryptedContent, equals('Привет от A'));
        expect(historyB[1].encryptedContent, equals('Привет от B'));
        expect(historyB[2].encryptedContent, equals('Как дела?'));
      });
    });

    group('Статус прочтения сообщений', () {
      test('должен обработать полный цикл статуса сообщения', () async {
        // Регистрируем пользователей
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

        // Отправляем сообщение
        final message = await messageManager.sendMessage(
          senderId: 'status_sender',
          receiverId: 'status_receiver',
          encryptedContent: 'Сообщение для проверки статуса',
          signature: 'status_sig',
        );

        // Проверяем начальный статус
        expect(message.status, equals(DeliveryStatus.sent));

        // Помечаем как прочитанное получателем
        final readSuccess = await messageManager.markMessageAsRead(
          message.id,
          'status_receiver',
        );

        expect(readSuccess, isTrue);

        // Проверяем статистику
        final stats = messageManager.getMessageStats();
        expect(stats['total'], greaterThanOrEqualTo(1));
        expect(stats['read'], greaterThanOrEqualTo(1));
      });
    });

    group('Управление пользователями онлайн', () {
      test('должен корректно отслеживать статус пользователей', () async {
        // Регистрируем пользователя
        await userManager.registerUser(
          id: 'online_test_user',
          publicSigningKey: 'online_key',
          publicEncryptionKey: 'online_enc_key',
          nickname: 'Online Test User',
        );

        // Проверяем начальный статус
        expect(userManager.isUserOnline('online_test_user'), isFalse);

        // Аутентифицируем пользователя
        await userManager.authenticateUser('online_test_user');

        // Пользователь все еще офлайн, пока не подключен WebSocket
        expect(userManager.isUserOnline('online_test_user'), isFalse);

        // Получаем список онлайн пользователей
        final onlineUsers = userManager.getOnlineUsers();
        final onlineUser = onlineUsers.firstWhere(
          (u) => u.id == 'online_test_user',
          orElse: () => throw StateError('User not found'),
        );
        expect(onlineUser.isOnline, isTrue);

        // Отключаем пользователя
        userManager.disconnectUser('online_test_user');
        expect(userManager.isUserOnline('online_test_user'), isFalse);
      });
    });

    group('Статистика системы', () {
      test('должен предоставить корректную статистику', () async {
        // Регистрируем несколько пользователей
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

        // Отправляем сообщения
        await messageManager.sendMessage(
          senderId: 'stats_user_1',
          receiverId: 'stats_user_2',
          encryptedContent: 'Статистическое сообщение 1',
          signature: 'stats_sig_1',
        );

        final message2 = await messageManager.sendMessage(
          senderId: 'stats_user_2',
          receiverId: 'stats_user_1',
          encryptedContent: 'Статистическое сообщение 2',
          signature: 'stats_sig_2',
        );

        // Помечаем одно сообщение как прочитанное
        await messageManager.markMessageAsRead(message2.id, 'stats_user_1');

        // Получаем статистику пользователей
        final userStats = userManager.getUserStats();
        expect(userStats['total'], greaterThanOrEqualTo(2));
        expect(userStats['online'], isA<int>());
        expect(userStats['offline'], isA<int>());

        // Получаем статистику сообщений
        final messageStats = messageManager.getMessageStats();
        expect(messageStats['total'], greaterThanOrEqualTo(2));
        expect(messageStats['delivered'], isA<int>());
        expect(messageStats['read'], greaterThanOrEqualTo(1));
      });
    });

    group('Обработка ошибок', () {
      test('должен корректно обработать попытку аутентификации несуществующего пользователя', () async {
        final isAuthenticated = await authService.authenticateUser(
          'nonexistent_user',
          'fake_signature',
          DateTime.now().toIso8601String(),
        );

        expect(isAuthenticated, isFalse);
      });

      test('должен корректно обработать отправку сообщения несуществующему пользователю', () async {
        // Регистрируем только отправителя
        await userManager.registerUser(
          id: 'sender_only',
          publicSigningKey: 'sender_key',
          publicEncryptionKey: 'sender_enc',
          nickname: 'Sender Only',
        );

        // Пытаемся отправить сообщение несуществующему получателю
        final message = await messageManager.sendMessage(
          senderId: 'sender_only',
          receiverId: 'nonexistent_receiver',
          encryptedContent: 'Сообщение в никуда',
          signature: 'nowhere_sig',
        );

        // Сообщение должно быть создано, но не доставлено
        expect(message, isNotNull);
        expect(message.receiverId, equals('nonexistent_receiver'));
        expect(message.status, equals(DeliveryStatus.sent));
      });

      test('должен корректно обработать попытку пометить несуществующее сообщение как прочитанное', () async {
        final success = await messageManager.markMessageAsRead(
          'nonexistent_message_id',
          'any_user_id',
        );

        expect(success, isFalse);
      });
    });
  });
}