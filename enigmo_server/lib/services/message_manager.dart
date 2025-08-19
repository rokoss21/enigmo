import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:enigmo_server/models/message.dart';
import 'package:enigmo_server/models/user.dart';
import 'package:enigmo_server/services/user_manager.dart';
import 'package:enigmo_server/utils/logger.dart';

class MessageManager {
  final UserManager _userManager;
  final List<ServerMessage> _messages = [];
  final Map<String, List<ServerMessage>> _userMessages = {};
  final Map<String, List<ServerMessage>> _offlineMessages = {};
  final Map<String, List<ServerMessage>> _conversationCache = {};
  final Completer<void> _initCompleter = Completer<void>();
  final Random _random = Random();
  
  // Простая реализация мьютекса для критических секций
  bool _isLocked = false;
  final List<Completer<void>> _lockQueue = [];

  MessageManager(this._userManager) {
    _initCompleter.complete();
  }

  // Простая реализация мьютекса
  Future<void> _lock() async {
    if (_isLocked) {
      final completer = Completer<void>();
      _lockQueue.add(completer);
      await completer.future;
    }
    _isLocked = true;
  }

  void _unlock() {
    _isLocked = false;
    if (_lockQueue.isNotEmpty) {
      final completer = _lockQueue.removeAt(0);
      completer.complete();
    }
  }

  Future<ServerMessage> sendMessage({
    required String senderId,
    required String receiverId,
    required String encryptedContent,
    required String signature,
    MessageType type = MessageType.text,
    Map<String, dynamic>? metadata,
  }) async {
    await _lock();
    try {
      final message = ServerMessage(
        id: _generateMessageId(),
        senderId: senderId,
        receiverId: receiverId,
        encryptedContent: encryptedContent,
        signature: signature,
        type: type,
        timestamp: DateTime.now(),
        status: DeliveryStatus.sent,
        metadata: metadata,
      );

      // Сохраняем глобально и по пользователям
      _messages.add(message);
      _addToUserHistory(senderId, message);
      _addToUserHistory(receiverId, message);

      // Обновляем кеш диалога
      final key = _getCacheKey(senderId, receiverId);
      _conversationCache.putIfAbsent(key, () => []);
      _conversationCache[key]!.add(message);

      // Пытаемся доставить
      await _deliverMessage(message);
      print('DEBUG MessageManager.sendMessage: Отправка завершена ${message.id}');
      return message;
    } finally {
      _unlock();
    }
  }

  Future<void> _deliverMessage(ServerMessage message) async {
    print('DEBUG MessageManager._deliverMessage: Попытка доставки сообщения ${message.id}');
    
    final receiver = _userManager.getUser(message.receiverId);
    if (receiver == null) {
      print('DEBUG MessageManager._deliverMessage: Получатель ${message.receiverId} не найден');
      return;
    }

    final isOnline = _userManager.isUserOnline(message.receiverId);
    print('DEBUG MessageManager._deliverMessage: Получатель ${message.receiverId} в сети: $isOnline');

    if (isOnline) {
      try {
        final success = await _userManager.sendToUser(message.receiverId, {
          'type': 'new_message',
          'message': message.toJson(),
        });

        if (success) {
          print('DEBUG MessageManager._deliverMessage: Сообщение ${message.id} успешно доставлено');
          _updateMessageStatus(message.id, DeliveryStatus.delivered);
        } else {
          print('DEBUG MessageManager._deliverMessage: Ошибка доставки сообщения ${message.id}, пропускаем (эфемерный режим)');
        }
      } catch (e) {
        print('DEBUG MessageManager._deliverMessage: Ошибка при доставке сообщения ${message.id}: $e');
      }
    } else {
      print('DEBUG MessageManager._deliverMessage: Получатель оффлайн, сообщение сохранено для истории');
      _addToOfflineQueue(message.receiverId, message);
    }
  }

  void _addToUserHistory(String userId, ServerMessage message) {
    _userMessages.putIfAbsent(userId, () => []);
    _userMessages[userId]!.add(message);
  }

  void _addToOfflineQueue(String userId, ServerMessage message) {
    _offlineMessages.putIfAbsent(userId, () => []);
    _offlineMessages[userId]!.add(message);
  }

  Future<List<ServerMessage>> getMessageHistory(String userId1, String userId2, {int limit = 50, DateTime? before}) async {
    // Используем кеш беседы, если есть
    final key = _getCacheKey(userId1, userId2);
    List<ServerMessage> list;
    if (_conversationCache.containsKey(key)) {
      list = List.of(_conversationCache[key]!);
    } else {
      list = _messages.where((m) =>
          (m.senderId == userId1 && m.receiverId == userId2) ||
          (m.senderId == userId2 && m.receiverId == userId1)
        ).toList();
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _conversationCache[key] = List.of(list);
    }

    // Фильтрация по времени (сообщения строго до before)
    if (before != null) {
      list = list.where((m) => m.timestamp.isBefore(before)).toList();
    }

    // Сортируем по времени по возрастанию
    list.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Применяем лимит: берем последние limit элементов, сохраняя порядок
    if (list.length > limit) {
      list = list.sublist(list.length - limit);
    }
    return list;
  }
  
  String _getCacheKey(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  Future<List<ServerMessage>> getUserMessages(String userId) async {
    final list = _messages.where((m) => m.senderId == userId || m.receiverId == userId).toList();
    // Новые первыми
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  Future<bool> markMessageAsRead(String messageId, String userId) async {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) {
      return false;
    }
    final msg = _messages[idx];
    if (msg.receiverId != userId) {
      // Только получатель может пометить как прочитанное
      return false;
    }
    _messages[idx] = msg.copyWith(status: DeliveryStatus.read);
    _clearConversationCache(msg.senderId, msg.receiverId);
    return true;
  }

  Future<void> deliverOfflineMessages(String userId) async {
    // Эфемерный режим: оффлайн доставки отключены
    return;
  }

  void _clearConversationCache(String userId1, String userId2) {
    final keys = _conversationCache.keys.where((key) => 
        (key.contains(userId1) && key.contains(userId2))).toList();
    for (final key in keys) {
      _conversationCache.remove(key);
    }
  }

  String _generateMessageId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = _random.nextInt(999999).toString().padLeft(6, '0');
    return '${timestamp}_${randomSuffix}';
  }

  /// Получить статистику сообщений
  Map<String, dynamic> getMessageStats() {
    return {
      'total': _messages.length,
      'delivered': _messages.where((m) => m.status == DeliveryStatus.delivered).length,
      'read': _messages.where((m) => m.status == DeliveryStatus.read).length,
    };
  }

  void _updateMessageStatus(String id, DeliveryStatus status) {
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx != -1) {
      final m = _messages[idx].copyWith(status: status);
      _messages[idx] = m;
      _clearConversationCache(m.senderId, m.receiverId);
    }
  }
}