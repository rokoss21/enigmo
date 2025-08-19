import 'package:test/test.dart';
import 'package:enigmo_server/services/user_manager.dart';
import 'package:enigmo_server/models/user.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:io';

void main() {
  group('UserManager Tests', () {
    late UserManager userManager;

    setUp(() {
      userManager = UserManager();
    });

    test('должен успешно зарегистрировать нового пользователя', () async {
      final user = await userManager.registerUser(
        id: 'test_user_1',
        publicSigningKey: 'test_signing_key',
        publicEncryptionKey: 'test_encryption_key',
        nickname: 'Test User',
      );

      expect(user, isNotNull);
      expect(user!.id, equals('test_user_1'));
      expect(user.nickname, equals('Test User'));
      expect(user.publicSigningKey, equals('test_signing_key'));
      expect(user.publicEncryptionKey, equals('test_encryption_key'));
      expect(user.isOnline, isFalse);
    });

    test('не должен регистрировать пользователя с существующим ID', () async {
      // Регистрируем первого пользователя
      await userManager.registerUser(
        id: 'duplicate_user',
        publicSigningKey: 'key1',
        publicEncryptionKey: 'key2',
        nickname: 'User 1',
      );

      // Пытаемся зарегистрировать пользователя с тем же ID
      final duplicateUser = await userManager.registerUser(
        id: 'duplicate_user',
        publicSigningKey: 'key3',
        publicEncryptionKey: 'key4',
        nickname: 'User 2',
      );

      expect(duplicateUser, isNull);
    });

    test('должен успешно аутентифицировать существующего пользователя', () async {
      // Регистрируем пользователя
      await userManager.registerUser(
        id: 'auth_test_user',
        publicSigningKey: 'test_key',
        publicEncryptionKey: 'test_key',
        nickname: 'Auth User',
      );

      // Аутентифицируем пользователя
      final authenticatedUser = await userManager.authenticateUser('auth_test_user');

      expect(authenticatedUser, isNotNull);
      expect(authenticatedUser!.id, equals('auth_test_user'));
      expect(authenticatedUser.isOnline, isTrue);
    });

    test('не должен аутентифицировать несуществующего пользователя', () async {
      final authenticatedUser = await userManager.authenticateUser('nonexistent_user');
      expect(authenticatedUser, isNull);
    });

    test('должен получить пользователя по ID', () async {
      // Регистрируем пользователя
      await userManager.registerUser(
        id: 'get_user_test',
        publicSigningKey: 'test_key',
        publicEncryptionKey: 'test_key',
        nickname: 'Get User Test',
      );

      // Получаем пользователя
      final user = userManager.getUser('get_user_test');
      expect(user, isNotNull);
      expect(user!.id, equals('get_user_test'));

      // Пытаемся получить несуществующего пользователя
      final nonexistentUser = userManager.getUser('nonexistent');
      expect(nonexistentUser, isNull);
    });

    test('должен получить список всех пользователей', () async {
      // Регистрируем несколько пользователей
      await userManager.registerUser(
        id: 'user1',
        publicSigningKey: 'key1',
        publicEncryptionKey: 'key1',
        nickname: 'User 1',
      );
      
      await userManager.registerUser(
        id: 'user2',
        publicSigningKey: 'key2',
        publicEncryptionKey: 'key2',
        nickname: 'User 2',
      );

      final allUsers = await userManager.getAllUsers();
      expect(allUsers.length, greaterThanOrEqualTo(2));
      
      final userIds = allUsers.map((u) => u.id).toList();
      expect(userIds, contains('user1'));
      expect(userIds, contains('user2'));
    });

    test('должен получить статистику пользователей', () async {
      // Регистрируем пользователя
      await userManager.registerUser(
        id: 'stats_user',
        publicSigningKey: 'key',
        publicEncryptionKey: 'key',
        nickname: 'Stats User',
      );

      final stats = userManager.getUserStats();
      expect(stats, isA<Map<String, dynamic>>());
      expect(stats['total'], isA<int>());
      expect(stats['online'], isA<int>());
      expect(stats['offline'], isA<int>());
      expect(stats['total'], greaterThanOrEqualTo(1));
    });

    test('должен проверить статус онлайн пользователя', () async {
      // Регистрируем пользователя
      await userManager.registerUser(
        id: 'online_test_user',
        publicSigningKey: 'key',
        publicEncryptionKey: 'key',
        nickname: 'Online Test',
      );

      // Пользователь должен быть офлайн после регистрации
      expect(userManager.isUserOnline('online_test_user'), isFalse);

      // Аутентифицируем пользователя (делает его онлайн)
      await userManager.authenticateUser('online_test_user');
      
      // Пользователь все еще офлайн, пока не подключен WebSocket
      expect(userManager.isUserOnline('online_test_user'), isFalse);
    });

    test('должен получить список онлайн пользователей', () async {
      // Регистрируем и аутентифицируем пользователя
      await userManager.registerUser(
        id: 'online_user_1',
        publicSigningKey: 'key1',
        publicEncryptionKey: 'key1',
        nickname: 'Online User 1',
      );
      
      await userManager.authenticateUser('online_user_1');

      final onlineUsers = userManager.getOnlineUsers();
      expect(onlineUsers, isA<List<User>>());
      
      // Проверяем, что аутентифицированный пользователь помечен как онлайн
      final onlineUser = onlineUsers.firstWhere(
        (u) => u.id == 'online_user_1',
        orElse: () => throw StateError('User not found'),
      );
      expect(onlineUser.isOnline, isTrue);
    });

    test('должен отключить пользователя', () async {
      // Регистрируем и аутентифицируем пользователя
      await userManager.registerUser(
        id: 'disconnect_user',
        publicSigningKey: 'key',
        publicEncryptionKey: 'key',
        nickname: 'Disconnect User',
      );
      
      await userManager.authenticateUser('disconnect_user');

      // Отключаем пользователя
      userManager.disconnectUser('disconnect_user');

      // Проверяем, что пользователь офлайн
      expect(userManager.isUserOnline('disconnect_user'), isFalse);
      
      final user = userManager.getUser('disconnect_user');
      expect(user!.isOnline, isFalse);
    });
  });
}