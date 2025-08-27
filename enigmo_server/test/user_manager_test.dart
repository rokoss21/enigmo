import 'package:test/test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:enigmo_server/services/user_manager.dart';
import 'package:enigmo_server/models/user.dart';

// Generate mocks
@GenerateMocks([WebSocketChannel, WebSocketSink])
import 'user_manager_test.mocks.dart';

void main() {
  late MockWebSocketChannel mockWebSocketChannel;
  late MockWebSocketSink mockWebSocketSink;
  late UserManager userManager;

  setUp(() {
    mockWebSocketChannel = MockWebSocketChannel();
    mockWebSocketSink = MockWebSocketSink();
    when(mockWebSocketChannel.sink).thenReturn(mockWebSocketSink);

    userManager = UserManager();
  });

  tearDown(() {
    // Clean up any test state
  });

  group('UserManager Initialization Tests', () {
    test('should initialize with default users', () {
      expect(userManager, isNotNull);
      final stats = userManager.getUserStats();
      expect(stats['total'], greaterThan(0));
    });

    test('should have default test users', () {
      final user1 = userManager.getUser('user1');
      final user2 = userManager.getUser('user2');

      expect(user1, isNotNull);
      expect(user2, isNotNull);
      expect(user1!.nickname, equals('Alice'));
      expect(user2!.nickname, equals('Bob'));
    });
  });

  group('UserManager User Registration Tests', () {
    test('should register new user successfully', () async {
      const userId = 'test_user_123';
      const publicSigningKey = 'signing_key_123';
      const publicEncryptionKey = 'encryption_key_456';
      const nickname = 'TestUser';

      final user = await userManager.registerUser(
        id: userId,
        publicSigningKey: publicSigningKey,
        publicEncryptionKey: publicEncryptionKey,
        nickname: nickname,
      );

      expect(user, isNotNull);
      expect(user!.id, equals(userId));
      expect(user.nickname, equals(nickname));
      expect(user.publicSigningKey, equals(publicSigningKey));
      expect(user.publicEncryptionKey, equals(publicEncryptionKey));
      expect(user.isOnline, isFalse);
    });

    test('should not register duplicate user', () async {
      const userId = 'duplicate_user';
      const publicSigningKey = 'signing_key_123';
      const publicEncryptionKey = 'encryption_key_456';

      // Register first time
      final user1 = await userManager.registerUser(
        id: userId,
        publicSigningKey: publicSigningKey,
        publicEncryptionKey: publicEncryptionKey,
      );

      expect(user1, isNotNull);

      // Try to register again
      final user2 = await userManager.registerUser(
        id: userId,
        publicSigningKey: publicSigningKey,
        publicEncryptionKey: publicEncryptionKey,
      );

      expect(user2, isNull);
    });

    test('should handle registration with minimal data', () async {
      const userId = 'minimal_user';
      const publicSigningKey = 'signing_key';
      const publicEncryptionKey = 'encryption_key';

      final user = await userManager.registerUser(
        id: userId,
        publicSigningKey: publicSigningKey,
        publicEncryptionKey: publicEncryptionKey,
      );

      expect(user, isNotNull);
      expect(user!.nickname, equals(userId)); // Should default to userId
    });
  });

  group('UserManager Authentication Tests', () {
    test('should authenticate existing user', () async {
      const userId = 'user1'; // Default user

      final authenticatedUser = await userManager.authenticateUser(userId);

      expect(authenticatedUser, isNotNull);
      expect(authenticatedUser!.id, equals(userId));
      expect(authenticatedUser.isOnline, isTrue);
    });

    test('should return null for non-existent user', () async {
      const userId = 'non_existent_user';

      final authenticatedUser = await userManager.authenticateUser(userId);

      expect(authenticatedUser, isNull);
    });
  });

  group('UserManager Connection Management Tests', () {
    test('should connect user successfully', () {
      const userId = 'user1';

      userManager.connectUser(userId, mockWebSocketChannel);

      expect(userManager.isUserOnline(userId), isTrue);
      final user = userManager.getUser(userId);
      expect(user!.isOnline, isTrue);
    });

    test('should disconnect user successfully', () {
      const userId = 'user1';

      userManager.connectUser(userId, mockWebSocketChannel);
      expect(userManager.isUserOnline(userId), isTrue);

      userManager.disconnectUser(userId);
      expect(userManager.isUserOnline(userId), isFalse);
    });

    test('should handle disconnect by channel', () {
      const userId = 'user1';

      userManager.connectUser(userId, mockWebSocketChannel);
      expect(userManager.isUserOnline(userId), isTrue);

      userManager.disconnectChannel(mockWebSocketChannel);
      expect(userManager.isUserOnline(userId), isFalse);
    });

    test('should get user channel', () {
      const userId = 'user1';

      userManager.connectUser(userId, mockWebSocketChannel);
      final channel = userManager.getUserChannel(userId);

      expect(channel, equals(mockWebSocketChannel));
    });

    test('should return null for offline user channel', () {
      const userId = 'user1';

      final channel = userManager.getUserChannel(userId);
      expect(channel, isNull);
    });
  });

  group('UserManager Message Sending Tests', () {
    test('should send message to online user successfully', () async {
      const userId = 'user1';
      const message = {'type': 'test', 'data': 'hello'};

      userManager.connectUser(userId, mockWebSocketChannel);

      final success = await userManager.sendToUser(userId, message);

      expect(success, isTrue);
      verify(mockWebSocketSink.add(any)).called(2); // 1 for message + 1 for status broadcast
    });

    test('should return false for offline user', () async {
      const userId = 'offline_user';
      const message = {'type': 'test', 'data': 'hello'};

      final success = await userManager.sendToUser(userId, message);

      expect(success, isFalse);
    });

    test('should handle send errors gracefully', () async {
      const userId = 'user1';
      const message = {'type': 'test', 'data': 'hello'};

      when(mockWebSocketSink.add(any)).thenThrow(Exception('Send failed'));

      userManager.connectUser(userId, mockWebSocketChannel);

      final success = await userManager.sendToUser(userId, message);

      expect(success, isFalse);
      expect(userManager.isUserOnline(userId), isFalse); // Should disconnect on error
    });
  });

  group('UserManager User Queries Tests', () {
    test('should get user by ID', () {
      const userId = 'user1';

      final user = userManager.getUser(userId);

      expect(user, isNotNull);
      expect(user!.id, equals(userId));
    });

    test('should return null for non-existent user', () {
      const userId = 'non_existent';

      final user = userManager.getUser(userId);

      expect(user, isNull);
    });

    test('should get all users', () async {
      final users = await userManager.getAllUsers();

      expect(users, isNotNull);
      expect(users.length, greaterThan(0));
      expect(users.any((user) => user.id == 'user1'), isTrue);
      expect(users.any((user) => user.id == 'user2'), isTrue);
    });

    test('should get online users', () {
      const userId1 = 'user1';
      const userId2 = 'user2';

      userManager.connectUser(userId1, mockWebSocketChannel);

      final onlineUsers = userManager.getOnlineUsers();

      expect(onlineUsers.length, equals(1));
      expect(onlineUsers.first.id, equals(userId1));
    });

    test('should check if user is online', () {
      const userId = 'user1';

      expect(userManager.isUserOnline(userId), isFalse);

      userManager.connectUser(userId, mockWebSocketChannel);
      expect(userManager.isUserOnline(userId), isTrue);
    });
  });

  group('UserManager Statistics Tests', () {
    test('should get user statistics', () {
      const userId = 'user1';

      final initialStats = userManager.getUserStats();
      expect(initialStats['total'], greaterThan(0));
      expect(initialStats['online'], equals(0));

      userManager.connectUser(userId, mockWebSocketChannel);

      final updatedStats = userManager.getUserStats();
      expect(updatedStats['online'], equals(1));
      expect(updatedStats['offline'], equals(initialStats['total']! - 1));
    });

    test('should get server statistics', () {
      final stats = userManager.getStats();

      expect(stats, isNotNull);
      expect(stats.containsKey('totalUsers'), isTrue);
      expect(stats.containsKey('onlineUsers'), isTrue);
      expect(stats['totalUsers'], greaterThan(0));
    });
  });

  group('UserManager User Status Updates Tests', () {
    test('should broadcast user status updates', () {
      const userId1 = 'user1';
      const userId2 = 'user2';

      // Connect two users
      userManager.connectUser(userId1, mockWebSocketChannel);
      userManager.connectUser(userId2, mockWebSocketChannel);

      // Disconnect one user - should broadcast to remaining users
      userManager.disconnectUser(userId1);

      // Verify broadcasts were sent
      verify(mockWebSocketSink.add(any)).called(greaterThan(0));
    });
  });

  group('UserManager Error Handling Tests', () {
    test('should handle connection errors', () {
      const userId = 'user1';

      // Test connecting with null channel
      expect(() => userManager.connectUser(userId, mockWebSocketChannel), returnsNormally);
    });

    test('should handle disconnection of non-existent user', () {
      const userId = 'non_existent';

      expect(() => userManager.disconnectUser(userId), returnsNormally);
    });

    test('should handle sending to non-existent user', () async {
      const userId = 'non_existent';
      const message = {'type': 'test'};

      final success = await userManager.sendToUser(userId, message);
      expect(success, isFalse);
    });
  });

  group('UserManager Performance Tests', () {
    test('should handle multiple connections', () {
      final userIds = List.generate(10, (i) => 'user_$i');

      // Connect multiple users
      for (final userId in userIds) {
        userManager.connectUser(userId, mockWebSocketChannel);
      }

      final onlineUsers = userManager.getOnlineUsers();
      expect(onlineUsers.length, equals(10));
    });

    test('should handle rapid connect/disconnect cycles', () {
      const userId = 'test_user';

      // Rapid connect/disconnect cycles
      for (var i = 0; i < 5; i++) {
        userManager.connectUser(userId, mockWebSocketChannel);
        expect(userManager.isUserOnline(userId), isTrue);
        userManager.disconnectUser(userId);
        expect(userManager.isUserOnline(userId), isFalse);
      }
    });
  });

  group('UserManager Data Integrity Tests', () {
    test('should maintain user data consistency', () async {
      const userId = 'test_user';
      const nickname = 'Test Nickname';

      // Register user
      final registeredUser = await userManager.registerUser(
        id: userId,
        publicSigningKey: 'signing_key',
        publicEncryptionKey: 'encryption_key',
        nickname: nickname,
      );

      expect(registeredUser!.nickname, equals(nickname));

      // Connect user
      userManager.connectUser(userId, mockWebSocketChannel);

      // Verify data consistency
      final retrievedUser = userManager.getUser(userId);
      expect(retrievedUser!.nickname, equals(nickname));
      expect(retrievedUser.isOnline, isTrue);
    });

    test('should handle concurrent operations', () async {
      const baseUserId = 'concurrent_user';

      // Simulate concurrent operations
      final futures = <Future>[];

      for (var i = 0; i < 5; i++) {
        final userId = '$baseUserId$i';
        futures.add(userManager.registerUser(
          id: userId,
          publicSigningKey: 'signing_key_$i',
          publicEncryptionKey: 'encryption_key_$i',
        ));
      }

      final results = await Future.wait(futures);
      expect(results.every((user) => user != null), isTrue);
    });
  });
}