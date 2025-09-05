import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/user.dart';
import '../utils/logger.dart';

class UserManager {
  final Map<String, User> _users = {};
  final Map<String, WebSocketChannel> _userChannels = {};
  final Map<WebSocketChannel, String> _channelToUserId = {};
  static const Duration _tokenValidity = Duration(hours: 1);

  UserManager() {
    _initializeDefaultUsers();
  }

  void _initializeDefaultUsers() {
    final user1 = User(
      id: 'user1',
      nickname: 'Alice',
      publicSigningKey: 'signing_key_1',
      publicEncryptionKey: 'encryption_key_1',
      lastSeen: DateTime.now(),
    );

    final user2 = User(
      id: 'user2',
      nickname: 'Bob',
      publicSigningKey: 'signing_key_2',
      publicEncryptionKey: 'encryption_key_2',
      lastSeen: DateTime.now(),
    );

    _users[user1.id] = user1;
    _users[user2.id] = user2;

    print('DEBUG UserManager: Default users initialized');
  }

  Future<User?> registerUser({
    required String id,
    required String publicSigningKey,
    required String publicEncryptionKey,
    String? nickname,
  }) async {
    if (_users.containsKey(id)) {
      return null;
    }

    final user = User(
      id: id,
      nickname: nickname ?? id,
      publicSigningKey: publicSigningKey,
      publicEncryptionKey: publicEncryptionKey,
      lastSeen: DateTime.now(),
      isOnline: false,
    );

    _users[id] = user;
    print('INFO: User registered: $id');
    return user;
  }

  Future<User?> authenticateUser(String userId) async {
    final user = _users[userId];
    if (user != null) {
      _users[userId] = user.copyWith(
        isOnline: true,
        lastSeen: DateTime.now(),
      );
      print('INFO: User $userId authenticated');
      // Return the updated user instance with isOnline=true
      return _users[userId];
    }
    return null;
  }

  /// Gets a user by token (simplified implementation)
  User? getUserByToken(String token) {
    // Expected format: token_userId_timestamp_random(6 digits)
    if (!token.startsWith('token_')) {
      return null;
    }

    final parts = token.split('_');
    if (parts.length < 4) {
      return null;
    }

    // Join parts 1..length-2 to support userIds with underscores
    final userId = parts.sublist(1, parts.length - 2).join('_');
    final timestamp = int.tryParse(parts[parts.length - 2]);
    final randomPart = parts.last;

    if (timestamp == null) {
      return null;
    }

    if (randomPart.length != 6 || int.tryParse(randomPart) == null) {
      return null;
    }

    final age = DateTime.now().microsecondsSinceEpoch - timestamp;
    if (age > _tokenValidity.inMicroseconds) {
      return null;
    }

    return _users[userId];
  }

  void connectUser(String userId, WebSocketChannel channel) {
    print('DEBUG UserManager.connectUser: Connecting user $userId');
    
    _userChannels[userId] = channel;
    _channelToUserId[channel] = userId;
    
    if (_users.containsKey(userId)) {
      _users[userId] = _users[userId]!.copyWith(
        isOnline: true,
        lastSeen: DateTime.now(),
      );
      
      // Notify all users that the user connected
      _broadcastUserStatusUpdate(userId, true);
    }
    
    print('DEBUG UserManager.connectUser: User $userId connected, active connections: ${_userChannels.length}');
  }

  void disconnectUser(String userId) {
    print('DEBUG UserManager.disconnectUser: Disconnecting user $userId');
    
    final channel = _userChannels.remove(userId);
    if (channel != null) {
      _channelToUserId.remove(channel);
    }
    
    if (_users.containsKey(userId)) {
      _users[userId] = _users[userId]!.copyWith(
        isOnline: false,
        lastSeen: DateTime.now(),
      );
      
      // Notify all users that the user disconnected
      _broadcastUserStatusUpdate(userId, false);
    }
    
    print('DEBUG UserManager.disconnectUser: User $userId disconnected, active connections: ${_userChannels.length}');
  }

  void disconnectChannel(WebSocketChannel channel) {
    final userId = _channelToUserId[channel];
    if (userId != null) {
      disconnectUser(userId);
    }
  }

  User? getUser(String userId) {
    return _users[userId];
  }

  Future<List<User>> getAllUsers() async {
    return _users.values.toList();
  }

  List<User> getOnlineUsers() {
    return _users.values.where((user) => user.isOnline).toList();
  }

  bool isUserOnline(String userId) {
    return _userChannels.containsKey(userId);
  }

  String? getUserIdByChannel(WebSocketChannel channel) {
    return _channelToUserId[channel];
  }

  WebSocketChannel? getUserChannel(String userId) {
    return _userChannels[userId];
  }

  Future<bool> sendToUser(String userId, Map<String, dynamic> message) async {
    print('DEBUG UserManager.sendToUser: Attempting to send message to user $userId');
    print('DEBUG UserManager.sendToUser: Message: $message');
    
    final channel = _userChannels[userId];
    if (channel == null) {
      print('DEBUG UserManager.sendToUser: Channel for user $userId not found');
      return false;
    }

    try {
      final jsonMessage = jsonEncode(message);
      channel.sink.add(jsonMessage);
      print('DEBUG UserManager.sendToUser: Message successfully sent to user $userId');
      return true;
    } catch (e) {
      print('DEBUG UserManager.sendToUser: Error sending message to user $userId: $e');
      print('ERROR: Error sending message to user $userId: $e');
      
      // Remove the faulty connection
      disconnectUser(userId);
      return false;
    }
  }

  Map<String, dynamic> getStats() {
    return {
      'totalUsers': _users.length,
      'onlineUsers': _userChannels.length,
    };
  }

  /// User statistics for tests: total/online/offline
  Map<String, int> getUserStats() {
    final total = _users.length;
    final online = _userChannels.length;
    final offline = total - online;
    return {
      'total': total,
      'online': online,
      'offline': offline < 0 ? 0 : offline,
    };
  }

  /// Sends a user status update notification to all connected clients
  void _broadcastUserStatusUpdate(String userId, bool isOnline) {
    final statusMessage = {
      'type': 'user_status_update',
      'userId': userId,
      'isOnline': isOnline,
      'timestamp': DateTime.now().toIso8601String(),
    };

    print('DEBUG UserManager._broadcastUserStatusUpdate: Sending status update for $userId: ${isOnline ? "online" : "offline"}');

    // Send to all connected users
    for (final channel in _userChannels.values) {
      try {
        channel.sink.add(jsonEncode(statusMessage));
      } catch (e) {
        print('ERROR UserManager._broadcastUserStatusUpdate: Error sending status update: $e');
      }
    }
  }
}