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

    test('should successfully register a new user', () async {
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

    test('should not register a user with an existing ID', () async {
      // Register the first user
      await userManager.registerUser(
        id: 'duplicate_user',
        publicSigningKey: 'key1',
        publicEncryptionKey: 'key2',
        nickname: 'User 1',
      );

      // Try to register a user with the same ID
      final duplicateUser = await userManager.registerUser(
        id: 'duplicate_user',
        publicSigningKey: 'key3',
        publicEncryptionKey: 'key4',
        nickname: 'User 2',
      );

      expect(duplicateUser, isNull);
    });

    test('should successfully authenticate an existing user', () async {
      // Register a user
      await userManager.registerUser(
        id: 'auth_test_user',
        publicSigningKey: 'test_key',
        publicEncryptionKey: 'test_key',
        nickname: 'Auth User',
      );

      // Authenticate the user
      final authenticatedUser = await userManager.authenticateUser('auth_test_user');

      expect(authenticatedUser, isNotNull);
      expect(authenticatedUser!.id, equals('auth_test_user'));
      expect(authenticatedUser.isOnline, isTrue);
    });

    test('should not authenticate a non-existent user', () async {
      final authenticatedUser = await userManager.authenticateUser('nonexistent_user');
      expect(authenticatedUser, isNull);
    });

    test('should get a user by ID', () async {
      // Register a user
      await userManager.registerUser(
        id: 'get_user_test',
        publicSigningKey: 'test_key',
        publicEncryptionKey: 'test_key',
        nickname: 'Get User Test',
      );

      // Get the user
      final user = userManager.getUser('get_user_test');
      expect(user, isNotNull);
      expect(user!.id, equals('get_user_test'));

      // Try to get a non-existent user
      final nonexistentUser = userManager.getUser('nonexistent');
      expect(nonexistentUser, isNull);
    });

    test('should get a list of all users', () async {
      // Register multiple users
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

    test('should get user statistics', () async {
      // Register a user
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

    test('should check a user online status', () async {
      // Register a user
      await userManager.registerUser(
        id: 'online_test_user',
        publicSigningKey: 'key',
        publicEncryptionKey: 'key',
        nickname: 'Online Test',
      );

      // The user should be offline after registration
      expect(userManager.isUserOnline('online_test_user'), isFalse);

      // Authenticate the user (marks them online)
      await userManager.authenticateUser('online_test_user');
      
      // The user is still offline until WebSocket is connected
      expect(userManager.isUserOnline('online_test_user'), isFalse);
    });

    test('should get a list of online users', () async {
      // Register and authenticate a user
      await userManager.registerUser(
        id: 'online_user_1',
        publicSigningKey: 'key1',
        publicEncryptionKey: 'key1',
        nickname: 'Online User 1',
      );
      
      await userManager.authenticateUser('online_user_1');

      final onlineUsers = userManager.getOnlineUsers();
      expect(onlineUsers, isA<List<User>>());
      
      // Verify the authenticated user is marked as online
      final onlineUser = onlineUsers.firstWhere(
        (u) => u.id == 'online_user_1',
        orElse: () => throw StateError('User not found'),
      );
      expect(onlineUser.isOnline, isTrue);
    });

    test('should disconnect a user', () async {
      // Register and authenticate a user
      await userManager.registerUser(
        id: 'disconnect_user',
        publicSigningKey: 'key',
        publicEncryptionKey: 'key',
        nickname: 'Disconnect User',
      );
      
      await userManager.authenticateUser('disconnect_user');

      // Disconnect the user
      userManager.disconnectUser('disconnect_user');

      // Verify the user is offline
      expect(userManager.isUserOnline('disconnect_user'), isFalse);
      
      final user = userManager.getUser('disconnect_user');
      expect(user!.isOnline, isFalse);
    });
  });
}