import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../utils/logger.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/user.dart';
import '../models/message.dart';
import 'user_manager.dart';
import 'message_manager.dart';
import 'auth_service.dart';


/// Обработчик WebSocket соединений
class WebSocketHandler {
  final Logger _logger = Logger();
  final UserManager _userManager;
  final MessageManager _messageManager;
  final AuthService _authService;
  
  WebSocketHandler(this._userManager, this._messageManager) : _authService = AuthService(_userManager);

  /// Создает обработчик WebSocket
  Handler get handler => webSocketHandler(_handleWebSocket);

  /// Обрабатывает новое WebSocket соединение
  void _handleWebSocket(WebSocketChannel webSocket) {
    String? userId;
    
    _logger.info('Новое WebSocket соединение');

    webSocket.stream.listen(
      (data) async {
        try {
          final message = jsonDecode(data as String) as Map<String, dynamic>;
          
          // Обновляем userId если пользователь аутентифицировался
          if (message['type'] == 'auth') {
            final tempUserId = message['userId'] as String?;
            final user = tempUserId != null ? await _userManager.authenticateUser(tempUserId) : null;
            if (user != null) {
              userId = tempUserId;
              _userManager.connectUser(userId!, webSocket);
              // Эфемерный режим: оффлайн-доставка отключена
            }
          }
          
          await _handleMessage(webSocket, message, userId);
        } catch (e, stackTrace) {
          _logger.error('Ошибка обработки сообщения: $e');
          _sendError(webSocket, 'Ошибка обработки сообщения: $e');
        }
      },
      onError: (error) {
        _logger.warning('Ошибка WebSocket: $error');
        if (userId != null) {
          _userManager.disconnectUser(userId!);
        }
      },
      onDone: () {
        _logger.info('WebSocket соединение закрыто');
        if (userId != null) {
          _userManager.disconnectUser(userId!);
        }
      },
    );
  }

  /// Обрабатывает входящее сообщение
  Future<void> _handleMessage(
    WebSocketChannel webSocket,
    Map<String, dynamic> message,
    String? currentUserId,
  ) async {
    final type = message['type'] as String?;
    
    switch (type) {
      case 'register':
        await _handleRegister(webSocket, message);
        break;
        
      case 'auth':
        await _handleAuth(webSocket, message);
        break;
        
      case 'send_message':
        if (currentUserId != null) {
          await _handleSendMessage(webSocket, message, currentUserId);
        } else {
          _sendError(webSocket, 'Необходима аутентификация');
        }
        break;
        
      case 'get_history':
        if (currentUserId != null) {
          await _handleGetHistory(webSocket, message, currentUserId);
        } else {
          _sendError(webSocket, 'Необходима аутентификация');
        }
        break;
        
      case 'mark_read':
        if (currentUserId != null) {
          await _handleMarkRead(webSocket, message, currentUserId);
        } else {
          _sendError(webSocket, 'Необходима аутентификация');
        }
        break;
        
      case 'get_users':
        if (currentUserId != null) {
          await _handleGetUsers(webSocket, message, currentUserId);
        } else {
          _sendError(webSocket, 'Необходима аутентификация');
        }
        break;
        
      case 'add_to_chat':
        if (currentUserId != null) {
          await _handleAddToChat(webSocket, message, currentUserId);
        } else {
          _sendError(webSocket, 'Необходима аутентификация');
        }
        break;
        
      case 'ping':
        _sendResponse(webSocket, 'pong', {'timestamp': DateTime.now().toIso8601String()});
        break;
        
      default:
        _sendError(webSocket, 'Неизвестный тип сообщения: $type');
    }
  }

  /// Обрабатывает регистрацию пользователя
  Future<void> _handleRegister(WebSocketChannel webSocket, Map<String, dynamic> message) async {
    try {
      final publicSigningKey = message['publicSigningKey'] as String?;
      final publicEncryptionKey = message['publicEncryptionKey'] as String?;
      final nickname = message['nickname'] as String?;
      
      if (publicSigningKey == null || publicEncryptionKey == null) {
        _sendError(webSocket, 'Отсутствуют обязательные поля');
        return;
      }

      // Генерируем userId на основе публичного ключа подписи
      final userId = _generateUserIdFromPublicKey(publicSigningKey);
      
      final user = await _userManager.registerUser(
        id: userId,
        publicSigningKey: publicSigningKey,
        publicEncryptionKey: publicEncryptionKey,
        nickname: nickname,
      );

      if (user != null) {
        _sendResponse(webSocket, 'register_success', {
          'userId': user.id,
          'user': user.toJson(),
        });
        
        _logger.info('Пользователь зарегистрирован: ${user.id}');
      } else {
        _sendError(webSocket, 'Ошибка регистрации: не удалось создать пользователя');
      }
    } catch (e) {
      _sendError(webSocket, 'Ошибка регистрации: $e');
    }
  }

  /// Обрабатывает аутентификацию пользователя
  Future<void> _handleAuth(WebSocketChannel webSocket, Map<String, dynamic> message) async {
    try {
      final userId = message['userId'] as String?;
      final signature = message['signature'] as String?;
      final timestamp = message['timestamp'] as String?;
      
      if (userId == null || signature == null || timestamp == null) {
        _sendError(webSocket, 'Отсутствуют обязательные поля для аутентификации');
        return;
      }

      final user = await _userManager.authenticateUser(userId);
      final success = user != null;

      if (success) {
        // Подключаем пользователя к WebSocket (регистрируем сам канал)
        _userManager.connectUser(userId, webSocket);
        
        _sendResponse(webSocket, 'auth_success', {
          'userId': userId,
          'success': true,
        });
        
        // Эфемерный режим: оффлайн-доставка отключена
        
        _logger.info('Пользователь аутентифицирован: $userId');
      } else {
        _sendError(webSocket, 'Ошибка аутентификации');
      }
    } catch (e) {
      _sendError(webSocket, 'Ошибка аутентификации: $e');
    }
  }

  /// Обрабатывает отправку сообщения
  Future<void> _handleSendMessage(
    WebSocketChannel webSocket,
    Map<String, dynamic> message,
    String senderId,
  ) async {
    try {
      final receiverId = message['receiverId'] as String?;
      final encryptedContent = message['encryptedContent'] as String?;
      final signature = message['signature'] as String?;
      final typeStr = message['messageType'] as String?;
      final metadata = message['metadata'] as Map<String, dynamic>?;
      
      if (receiverId == null || encryptedContent == null || signature == null) {
        _sendError(webSocket, 'Отсутствуют обязательные поля для отправки сообщения');
        return;
      }

      final messageType = _parseMessageType(typeStr);
      
      final sentMessage = await _messageManager.sendMessage(
        senderId: senderId,
        receiverId: receiverId,
        encryptedContent: encryptedContent,
        signature: signature,
        type: messageType,
        metadata: metadata,
      );

      _sendResponse(webSocket, 'message_sent', {
        'messageId': sentMessage.id,
        'message': sentMessage.toJson(),
      });
      
      _logger.info('Сообщение отправлено: ${sentMessage.id}');
    } catch (e) {
      _sendError(webSocket, 'Ошибка отправки сообщения: $e');
    }
  }

  /// Обрабатывает запрос истории сообщений
  Future<void> _handleGetHistory(
    WebSocketChannel webSocket,
    Map<String, dynamic> message,
    String userId,
  ) async {
    try {
      final otherUserId = message['otherUserId'] as String?;
      final limit = message['limit'] as int? ?? 50;
      final beforeStr = message['before'] as String?;
      
      if (otherUserId == null) {
        _sendError(webSocket, 'Отсутствует ID собеседника');
        return;
      }

      DateTime? before;
      if (beforeStr != null) {
        before = DateTime.tryParse(beforeStr);
      }

      final history = await _messageManager.getMessageHistory(
        userId,
        otherUserId,
        limit: limit,
        before: before,
      );

      _sendResponse(webSocket, 'message_history', {
        'messages': history.map((msg) => msg.toJson()).toList(),
        'otherUserId': otherUserId,
      });
      
      _logger.info('История сообщений отправлена: $userId <-> $otherUserId');
    } catch (e) {
      _sendError(webSocket, 'Ошибка получения истории: $e');
    }
  }

  /// Обрабатывает пометку сообщения как прочитанного
  Future<void> _handleMarkRead(
    WebSocketChannel webSocket,
    Map<String, dynamic> message,
    String userId,
  ) async {
    try {
      final messageId = message['messageId'] as String?;
      
      if (messageId == null) {
        _sendError(webSocket, 'Отсутствует ID сообщения');
        return;
      }

      final success = await _messageManager.markMessageAsRead(messageId, userId);

      _sendResponse(webSocket, 'message_marked_read', {
        'messageId': messageId,
        'success': success,
      });
      
      if (success) {
        _logger.info('Сообщение помечено как прочитанное: $messageId');
      }
    } catch (e) {
      _sendError(webSocket, 'Ошибка пометки сообщения: $e');
    }
  }

  /// Обрабатывает запрос списка пользователей
  Future<void> _handleGetUsers(
    WebSocketChannel webSocket,
    Map<String, dynamic> message,
    String userId,
  ) async {
    try {
      final onlineUsers = _userManager.getOnlineUsers();
      
      final users = onlineUsers
          .where((user) => user.id != userId) // Исключаем текущего пользователя
          .map((user) => user.toJson())
          .toList();
      
      _sendResponse(webSocket, 'users_list', {
        'users': users,
      });
      
      _logger.info('Список пользователей отправлен: $userId');
    } catch (e) {
      _sendError(webSocket, 'Ошибка получения списка пользователей: $e');
    }
  }

  /// Отправляет ответ клиенту
  void _sendResponse(WebSocketChannel webSocket, String type, Map<String, dynamic> data) {
    final response = {
      'type': type,
      'timestamp': DateTime.now().toIso8601String(),
      ...data,
    };
    
    try {
      webSocket.sink.add(jsonEncode(response));
    } catch (e) {
      _logger.warning('Ошибка отправки ответа: $e');
    }
  }

  /// Обрабатывает добавление пользователя в чат
  Future<void> _handleAddToChat(WebSocketChannel webSocket, Map<String, dynamic> message, String currentUserId) async {
    try {
      final targetUserId = message['target_user_id'] as String?;
      
      if (targetUserId == null) {
        _sendError(webSocket, 'Не указан ID пользователя для добавления в чат');
        return;
      }
      
      if (targetUserId == currentUserId) {
        _sendError(webSocket, 'Нельзя добавить себя в чат');
        return;
      }
      
      // Проверяем, существует ли целевой пользователь
      final targetUser = _userManager.getUser(targetUserId);
      if (targetUser == null) {
        _sendError(webSocket, 'Пользователь не найден');
        return;
      }
      
      // Отправляем уведомление целевому пользователю о добавлении в чат
      if (_userManager.isUserOnline(targetUserId)) {
        await _userManager.sendToUser(targetUserId, {
          'type': 'chat_added',
          'user_id': currentUserId,
          'nickname': _userManager.getUser(currentUserId)?.nickname ?? currentUserId,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
      
      // Отправляем информацию о целевом пользователе инициатору
      final initiatorInfo = {
        'id': targetUserId,
        'nickname': targetUser.nickname ?? targetUserId,
        'isOnline': _userManager.isUserOnline(targetUserId),
        'lastSeen': targetUser.lastSeen?.toIso8601String() ?? DateTime.now().toIso8601String(),
      };
      
      // Подтверждаем инициатору, что пользователь добавлен
      _sendResponse(webSocket, 'add_to_chat_success', {
        'target_user': initiatorInfo,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
    } catch (e) {
      print('Ошибка при добавлении пользователя в чат: $e');
      _sendError(webSocket, 'Ошибка при добавлении пользователя в чат');
    }
  }

  /// Отправляет ошибку клиенту
  void _sendError(WebSocketChannel webSocket, String error) {
    _sendResponse(webSocket, 'error', {'message': error});
  }

  /// Парсит тип сообщения из строки
  MessageType _parseMessageType(String? typeStr) {
    switch (typeStr?.toLowerCase()) {
      case 'text':
        return MessageType.text;
      case 'image':
        return MessageType.image;
      case 'file':
        return MessageType.file;
      default:
        return MessageType.text;
    }
  }
  
  /// Генерирует userId на основе публичного ключа подписи
  String _generateUserIdFromPublicKey(String publicKey) {
    // Используем первые 16 символов хеша публичного ключа как userId
    final bytes = utf8.encode(publicKey);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16).toUpperCase();
  }
}