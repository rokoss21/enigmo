import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/user.dart';
import '../utils/logger.dart';

class UserManager {
  final Map<String, User> _users = {};
  final Map<String, WebSocketChannel> _userChannels = {};
  final Map<WebSocketChannel, String> _channelToUserId = {};

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

    print('DEBUG UserManager: Инициализированы пользователи по умолчанию');
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
    print('INFO: Пользователь зарегистрирован: $id');
    return user;
  }

  Future<User?> authenticateUser(String userId) async {
    final user = _users[userId];
    if (user != null) {
      _users[userId] = user.copyWith(
        isOnline: true,
        lastSeen: DateTime.now(),
      );
      print('INFO: Пользователь $userId аутентифицирован');
      // Возвращаем обновлённый экземпляр пользователя с isOnline=true
      return _users[userId];
    }
    return null;
  }

  /// Получает пользователя по токену (упрощенная реализация)
  User? getUserByToken(String token) {
    // Простая реализация: извлекаем userId из токена
    if (token.startsWith('token_')) {
      final parts = token.split('_');
      if (parts.length >= 2) {
        final userId = parts[1];
        return _users[userId];
      }
    }
    return null;
  }

  void connectUser(String userId, WebSocketChannel channel) {
    print('DEBUG UserManager.connectUser: Подключение пользователя $userId');
    
    _userChannels[userId] = channel;
    _channelToUserId[channel] = userId;
    
    if (_users.containsKey(userId)) {
      _users[userId] = _users[userId]!.copyWith(
        isOnline: true,
        lastSeen: DateTime.now(),
      );
      
      // Уведомляем всех пользователей о том, что пользователь подключился
      _broadcastUserStatusUpdate(userId, true);
    }
    
    print('DEBUG UserManager.connectUser: Пользователь $userId подключен, активных подключений: ${_userChannels.length}');
  }

  void disconnectUser(String userId) {
    print('DEBUG UserManager.disconnectUser: Отключение пользователя $userId');
    
    final channel = _userChannels.remove(userId);
    if (channel != null) {
      _channelToUserId.remove(channel);
    }
    
    if (_users.containsKey(userId)) {
      _users[userId] = _users[userId]!.copyWith(
        isOnline: false,
        lastSeen: DateTime.now(),
      );
      
      // Уведомляем всех пользователей о том, что пользователь отключился
      _broadcastUserStatusUpdate(userId, false);
    }
    
    print('DEBUG UserManager.disconnectUser: Пользователь $userId отключен, активных подключений: ${_userChannels.length}');
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
    print('DEBUG UserManager.sendToUser: Попытка отправить сообщение пользователю $userId');
    print('DEBUG UserManager.sendToUser: Сообщение: $message');
    
    final channel = _userChannels[userId];
    if (channel == null) {
      print('DEBUG UserManager.sendToUser: Канал для пользователя $userId не найден');
      return false;
    }

    try {
      final jsonMessage = jsonEncode(message);
      channel.sink.add(jsonMessage);
      print('DEBUG UserManager.sendToUser: Сообщение успешно отправлено пользователю $userId');
      return true;
    } catch (e) {
      print('DEBUG UserManager.sendToUser: Ошибка отправки сообщения пользователю $userId: $e');
      print('ERROR: Ошибка отправки сообщения пользователю $userId: $e');
      
      // Удаляем неисправное соединение
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

  /// Статистика пользователей для тестов: total/online/offline
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

  /// Отправляет уведомление о смене статуса пользователя всем подключенным клиентам
  void _broadcastUserStatusUpdate(String userId, bool isOnline) {
    final statusMessage = {
      'type': 'user_status_update',
      'userId': userId,
      'isOnline': isOnline,
      'timestamp': DateTime.now().toIso8601String(),
    };

    print('DEBUG UserManager._broadcastUserStatusUpdate: Отправка обновления статуса для $userId: ${isOnline ? "онлайн" : "офлайн"}');

    // Отправляем всем подключенным пользователям
    for (final channel in _userChannels.values) {
      try {
        channel.sink.add(jsonEncode(statusMessage));
      } catch (e) {
        print('ERROR UserManager._broadcastUserStatusUpdate: Ошибка отправки обновления статуса: $e');
      }
    }
  }
}