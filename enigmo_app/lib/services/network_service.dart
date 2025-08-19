import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/html.dart' if (dart.library.io) 'package:web_socket_channel/io.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/message.dart';
import '../models/chat.dart';
import 'key_manager.dart';
import 'crypto_engine.dart';

/// Сервис для работы с сетью и Bootstrap сервером
class NetworkService {
  static final NetworkService _instance = NetworkService._internal();

  factory NetworkService() {
    return _instance;
  }

  // Внутренний помощник отправки на сервер (без дублирования локального сообщения при флаше очереди)
  Future<bool> _sendToServer(String receiverId, String content, MessageType type, {required DateTime timestamp, bool emitLocal = false}) async {
    try {
      String encryptedContent = content;
      String signature;

      final hasKeys = await _ensureRecipientKeys(receiverId);
      if (hasKeys) {
        final encKeyB64 = _publicEncKeys[receiverId]!;
        final recipientEncKey = await KeyManager.publicKeyFromString(encKeyB64, isEncryption: true);
        final encrypted = await CryptoEngine.encryptMessage(content, recipientEncKey);
        encryptedContent = jsonEncode(encrypted.toJson());
        signature = encrypted.signature;
      } else {
        signature = await CryptoEngine.signData(encryptedContent);
      }

      final wire = {
        'type': 'send_message',
        'receiverId': receiverId,
        'encryptedContent': encryptedContent,
        'messageType': type.toString().split('.').last,
        'signature': signature,
        'timestamp': timestamp.toIso8601String(),
      };

      print('DEBUG _sendToServer: Отправка сообщения: $wire');

      if (emitLocal) {
        try {
          final localMsg = Message(
            id: 'local-${timestamp.millisecondsSinceEpoch}',
            senderId: _userId!,
            receiverId: receiverId,
            content: content,
            timestamp: timestamp,
            type: type,
            status: MessageStatus.sending,
            isEncrypted: false,
          );
          _storeInMemory(localMsg);
          _newMessageController.add(localMsg);
        } catch (e) {
          print('DEBUG _sendToServer: не удалось создать локальное сообщение: $e');
        }
      }

      _channel!.sink.add(jsonEncode(wire));
      return true;
    } catch (e) {
      print('DEBUG _sendToServer: Ошибка при отправке: $e');
      return false;
    }
  }

  // Гарантирует, что у нас есть публичные ключи получателя в кеше
  Future<bool> _ensureRecipientKeys(String userId) async {
    if (_publicEncKeys.containsKey(userId) && _publicSignKeys.containsKey(userId)) {
      return true;
    }
    try {
      // Запрашиваем список пользователей и ждём ответ
      await getUsers();
      final response = await _waitForResponse('users_list');
      if (response != null) {
        final users = (response['users'] as List).cast<Map<String, dynamic>>();
        _cacheUsersKeys(users);
        return _publicEncKeys.containsKey(userId) && _publicSignKeys.containsKey(userId);
      }
    } catch (_) {}
    return false;
  }

  NetworkService._internal();
  static const String _defaultServerUrl = 'ws://localhost:8080/ws';
  
  WebSocketChannel? _channel;
  // Единый broadcast-поток для всех подписчиков
  Stream<dynamic>? _broadcastStream;
  StreamController<Map<String, dynamic>>? _messageController;
  String? _userId;
  bool _isConnected = false;
  
  // Heartbeat и авто-переподключение
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  DateTime? _lastPongAt;
  Duration _pingInterval = const Duration(seconds: 20);
  Duration _pongTimeout = const Duration(seconds: 10);
  bool _manualDisconnect = false;
  bool _isReconnecting = false;
  int _reconnectAttempt = 0;
  final int _maxReconnectDelaySeconds = 30;
  bool _ephemeralInitDone = false; // выполняем очистку ключей один раз за запуск
  
  // KeyManager и CryptoEngine используются как статические классы
  
  // Стримы для различных типов сообщений
  final StreamController<Message> _newMessageController = StreamController.broadcast();
  final StreamController<List<Message>> _messageHistoryController = StreamController.broadcast();
  final StreamController<List<Chat>> _chatsController = StreamController.broadcast();
  final StreamController<bool> _connectionController = StreamController.broadcast();
  final StreamController<String> _newChatController = StreamController.broadcast();
  final StreamController<List<Map<String, dynamic>>> _usersController = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _userStatusController = StreamController.broadcast();
  // Кеш публичных ключей пользователей
  final Map<String, String> _publicEncKeys = {}; // userId -> base64 X25519
  final Map<String, String> _publicSignKeys = {}; // userId -> base64 Ed25519
  // Отслеживание онлайна и локальная очередь сообщений для эфемерного режима
  final Set<String> _onlineUsers = <String>{};
  final Map<String, List<_PendingMessage>> _pendingByReceiver = {};
  // Локальный буфер сообщений по собеседнику (только на время сессии)
  final Map<String, List<Message>> _inMemoryByPeer = {};

  // Локальная структура для отложенных сообщений
  // ignore: unused_element
  static _PendingMessage _pm(String receiverId, String content, MessageType type, DateTime timestamp) =>
      _PendingMessage(receiverId: receiverId, content: content, type: type, timestamp: timestamp);
  
  Stream<Message> get newMessages => _newMessageController.stream;
  Stream<List<Message>> get messageHistory => _messageHistoryController.stream;
  Stream<List<Chat>> get chats => _chatsController.stream;
  Stream<bool> get connectionStatus => _connectionController.stream;
  Stream<String> get newChatNotifications => _newChatController.stream;
  Stream<List<Map<String, dynamic>>> get users => _usersController.stream;
  Stream<Map<String, dynamic>> get userStatusUpdates => _userStatusController.stream;
  
  bool get isConnected => _isConnected;
  String? get userId => _userId;

  // Возвращает копию последних сообщений с конкретным собеседником
  List<Message> getRecentMessages(String otherUserId) {
    final list = _inMemoryByPeer[otherUserId];
    if (list == null) return const [];
    return List<Message>.from(list);
  }

  // Очищает все локальные данные по собеседнику (сообщения/очередь/онлайн-флаг)
  void clearPeerSession(String otherUserId) {
    try {
      _inMemoryByPeer.remove(otherUserId);
      _pendingByReceiver.remove(otherUserId);
      _onlineUsers.remove(otherUserId);
      print('DEBUG NetworkService.clearPeerSession: очищены данные для $otherUserId');
    } catch (e) {
      print('DEBUG NetworkService.clearPeerSession: ошибка: $e');
    }
  }

  // Полный сброс текущей сессии: удаление ключей/ID, очистка локальных кешей и переподключение
  Future<bool> resetSession() async {
    try {
      print('DEBUG NetworkService.resetSession: старт');
      // Отключаемся и очищаем локальные структуры
      disconnect();
      _inMemoryByPeer.clear();
      _pendingByReceiver.clear();
      _onlineUsers.clear();
      _publicEncKeys.clear();
      _publicSignKeys.clear();
      _userId = null;
      // Удаляем ключи и userId в хранилище
      await KeyManager.deleteUserKeys();
      // Разрешаем connect() снова выполнить эпемерную очистку на всякий случай
      _ephemeralInitDone = false;

      // Новое подключение и регистрация/аутентификация
      final connected = await connect();
      if (!connected) return false;
      final registeredId = await registerUser();
      if (registeredId == null) return false;
      final authed = await authenticate();
      return authed;
    } catch (e) {
      print('DEBUG NetworkService.resetSession: ошибка: $e');
      return false;
    }
  }

  // Кладёт ключи пользователей в локальный кеш
  void _cacheUsersKeys(List<Map<String, dynamic>> users) {
    try {
      for (final u in users) {
        final id = (u['userId'] ?? u['id']) as String?;
        if (id == null) continue;
        final enc = (u['publicEncryptionKey'] ?? u['encryptionKey']) as String?;
        final sign = (u['publicSigningKey'] ?? u['signingKey']) as String?;
        if (enc != null && enc.isNotEmpty) {
          _publicEncKeys[id] = enc;
        }
        if (sign != null && sign.isNotEmpty) {
          _publicSignKeys[id] = sign;
        }

        // Также обновляем локальный набор онлайна по users_list
        bool isOnline = false;
        final onlineRaw = u['isOnline'];
        if (onlineRaw is bool) {
          isOnline = onlineRaw;
        } else if (onlineRaw is String) {
          final lower = onlineRaw.toLowerCase();
          isOnline = lower == 'true' || lower == 'online' || lower == '1';
        } else if (onlineRaw is num) {
          isOnline = onlineRaw != 0;
        }

        if (id != _userId) {
          if (isOnline) {
            if (_onlineUsers.add(id)) {
              // Если пользователь только что помечен как онлайн — флашим отложенные
              final pending = _pendingByReceiver.remove(id);
              if (pending != null && pending.isNotEmpty) {
                print('DEBUG _cacheUsersKeys: Флаш отложенных сообщений для $id: ${pending.length}');
                () async {
                  for (final p in pending) {
                    try { await _sendToServer(p.receiverId, p.content, p.type, timestamp: p.timestamp, emitLocal: false); } catch (_) {}
                  }
                }();
              }
            }
          } else {
            _onlineUsers.remove(id);
          }
        }
      }
      print('DEBUG _cacheUsersKeys: закешировано encKeys=${_publicEncKeys.length}, signKeys=${_publicSignKeys.length}');
    } catch (e) {
      print('DEBUG _cacheUsersKeys: ошибка кеширования ключей: $e');
    }
  }

  String _resolveServerUrl() {
    if (kIsWeb) {
      // На вебе используем хост страницы. Если это 0.0.0.0 или пусто, подставляем localhost
      var host = Uri.base.host;
      if (host.isEmpty || host == '0.0.0.0') {
        host = 'localhost';
      }
      final scheme = Uri.base.scheme == 'https' ? 'wss' : 'ws';
      return '$scheme://$host:8080/ws';
    } else {
      // На мобильных/desktop оставляем localhost по умолчанию
      return _defaultServerUrl;
    }
  }

  /// Подключается к Bootstrap серверу
  Future<bool> connect({String? serverUrl, bool ephemeralIdentity = true}) async {
    try {
      // Эфемерный режим: при первом подключении очищаем ключи/ID, чтобы каждый запуск был новым пользователем
      if (ephemeralIdentity && !_ephemeralInitDone) {
        try {
          print('DEBUG NetworkService.connect: Эфемерный режим — очистка ключей/ID на старте приложения');
          await KeyManager.deleteUserKeys();
        } catch (e) {
          print('DEBUG NetworkService.connect: Ошибка очистки ключей: $e');
        } finally {
          _ephemeralInitDone = true;
        }
      }
      final url = serverUrl ?? _resolveServerUrl();
      print('Подключение к серверу: $url');
      
      _manualDisconnect = false; // Явное подключение отменяет флаг ручного отключения
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _messageController = StreamController<Map<String, dynamic>>.broadcast();

      // Создаем и сохраняем broadcast stream, чтобы все подписки использовали один и тот же поток
      _broadcastStream = _channel!.stream.asBroadcastStream();

      // Слушаем входящие сообщения основным обработчиком
      _broadcastStream!.listen(
        (data) {
          print('DEBUG: Получено сообщение от сервера: $data');
          try {
            _handleServerMessage(data as String);
          } catch (e) {
            print('Ошибка обработки входящего сообщения: $e');
          }
        },
        onError: (error) {
          print('DEBUG: WebSocket ошибка: $error');
          // Не вызываем отключение сразу, даем время на восстановление
          print('WebSocket ошибка, но соединение может быть восстановлено');
        },
        onDone: () {
          print('DEBUG: WebSocket соединение закрыто сервером');
          _handleDisconnection();
          _scheduleReconnect();
        },
        cancelOnError: false, // Не закрываем стрим при ошибках
      );
      
      _isConnected = true;
      _connectionController.add(true);
      _reconnectAttempt = 0;
      _isReconnecting = false;
      _startHeartbeat();
      print('Подключение к серверу успешно');
      return true;
    } catch (e) {
      print('Ошибка подключения к серверу: $e');
      _isConnected = false;
      _connectionController.add(false);
      _scheduleReconnect();
      return false;
    }
  }

  /// Регистрирует нового пользователя
  Future<String?> registerUser({String? nickname}) async {
    if (!_isConnected || _channel == null) {
      throw Exception('Нет подключения к серверу');
    }

    try {
      // Генерируем ключи если их нет
      await KeyManager.generateUserKeys();
      final keys = await KeyManager.loadUserKeys();
      
      if (keys == null) {
        throw Exception('Не удалось загрузить ключи');
      }

      final signingPublicKey = await keys.signingKeyPair.extractPublicKey();
      final encryptionPublicKey = await keys.encryptionKeyPair.extractPublicKey();
      
      final message = {
        'type': 'register',
        'publicSigningKey': await KeyManager.publicKeyToString(signingPublicKey),
        'publicEncryptionKey': await KeyManager.publicKeyToString(encryptionPublicKey),
        'nickname': nickname,
        'timestamp': DateTime.now().toIso8601String(),
      };

      _sendMessage(message);
      
      // Ждем ответ от сервера
      final response = await _waitForResponse('register_success');
      if (response != null) {
        _userId = response['userId'] as String?;
        if (_userId != null) {
          // Сохраняем userId из ответа сервера в KeyManager
          await KeyManager.setUserId(_userId!);
          print('userId сохранен в KeyManager: $_userId');
        }
        print('Пользователь зарегистрирован: $_userId');
        return _userId;
      }
      
      return null;
    } catch (e) {
      print('Ошибка регистрации: $e');
      return null;
    }
  }

  /// Аутентифицирует пользователя
  Future<bool> authenticate() async {
    if (!_isConnected || _channel == null) {
      throw Exception('Нет подключения к серверу');
    }

    try {
      var storedUserId = await KeyManager.getUserId();
      print('Попытка аутентификации с userId: $storedUserId');
      if (storedUserId == null) {
        // Авто-регистрация при отсутствии userId (после очистки для эфемерного режима)
        print('ID пользователя не найден — выполняем авто-регистрацию');
        storedUserId = await registerUser();
        if (storedUserId == null) {
          print('Авто-регистрация не удалась');
          return false;
        }
      }
      _userId = storedUserId;

      final keys = await KeyManager.loadUserKeys();
      if (keys == null) {
        print('Ключи пользователя не найдены');
        return false;
      }

      final timestamp = DateTime.now().toIso8601String();
      final signature = await CryptoEngine.signData(timestamp);

      final message = {
        'type': 'auth',
        'userId': _userId,
        'signature': signature,
        'timestamp': timestamp,
      };

      _sendMessage(message);
      
      // Ждем ответ от сервера
      final response = await _waitForResponse('auth_success');
      if (response != null && response['success'] == true) {
        print('Аутентификация успешна');
        // _userId уже установлен выше, сохраняем состояние аутентификации
        print('После успешной аутентификации: _isConnected=$_isConnected, _userId=$_userId');
        return true;
      } else {
        // Если аутентификация не удалась, сбрасываем _userId
        _userId = null;
      }
      
      return false;
    } catch (e) {
      print('Ошибка аутентификации: $e');
      return false;
    }
  }

  /// Отправляет сообщение
  Future<bool> sendMessage(String receiverId, String content, {MessageType type = MessageType.text}) async {
    print('DEBUG NetworkService.sendMessage: receiverId=$receiverId, content="$content", type=$type');
    
    if (!_isConnected || _userId == null) {
      print('DEBUG NetworkService.sendMessage: Не подключен или нет userId');
      return false;
    }

    try {
      final nowTs = DateTime.now();
      final isReceiverOnline = _onlineUsers.contains(receiverId);

      // Всегда показываем локально как отправленное/в очереди
      try {
        final localMsg = Message(
          id: 'local-${nowTs.millisecondsSinceEpoch}',
          senderId: _userId!,
          receiverId: receiverId,
          content: content,
          timestamp: nowTs,
          type: type,
          status: MessageStatus.sending,
          isEncrypted: false,
        );
        _storeInMemory(localMsg);
        _newMessageController.add(localMsg);
      } catch (e) {
        print('DEBUG NetworkService.sendMessage: не удалось создать локальное сообщение: $e');
      }

      if (!isReceiverOnline) {
        print('DEBUG NetworkService.sendMessage: Получатель оффлайн — кладём в локальную очередь');
        final list = _pendingByReceiver.putIfAbsent(receiverId, () => []);
        list.add(_pm(receiverId, content, type, nowTs));
        return true; // queued locally
      }

      // Получатель онлайн — отправляем немедленно на сервер
      return await _sendToServer(receiverId, content, type, timestamp: nowTs, emitLocal: false);
    } catch (e) {
      print('DEBUG NetworkService.sendMessage: Ошибка при отправке: $e');
      return false;
    }
  }

  Future<List<Message>> getMessageHistory(String userId, String otherUserId, {int limit = 50, DateTime? before}) async {
    if (!_isConnected) return [];

    try {
      final request = {
        'type': 'get_history',
        'userId': userId,
        'otherUserId': otherUserId,
        'limit': limit,
        if (before != null) 'before': before.toIso8601String(),
      };

      _channel!.sink.add(jsonEncode(request));
      print('DEBUG NetworkService.getMessageHistory: Отправлен запрос истории сообщений');
      
      // Ждем ответ от сервера - исправляем тип ответа
      final response = await _waitForResponse('message_history');
      if (response != null && response['messages'] != null) {
        final messagesData = (response['messages'] as List).cast<dynamic>();
        final List<Message> messages = [];
        for (final item in messagesData) {
          try {
            final Map<String, dynamic> msgJson = Map<String, dynamic>.from(item as Map);
            final decrypted = await _tryDecryptMessage(msgJson);
            if (decrypted != null) {
              msgJson['content'] = decrypted;
              msgJson['isEncrypted'] = true;
            }
            messages.add(Message.fromJson(msgJson));
          } catch (e) {
            print('DEBUG getMessageHistory: ошибка обработки сообщения истории: $e');
          }
        }
        print('DEBUG NetworkService.getMessageHistory: Получено ${messages.length} сообщений');
        return messages;
      }
      
      print('DEBUG NetworkService.getMessageHistory: Пустой ответ или ошибка');
      return [];
    } catch (e) {
      print('DEBUG NetworkService.getMessageHistory: Ошибка: $e');
      return [];
    }
  }

  Future<void> markMessageAsRead(String messageId) async {
    if (!_isConnected) return;

    try {
      final request = {
        'type': 'mark_read',
        'messageId': messageId,
      };

      _channel!.sink.add(jsonEncode(request));
    } catch (e) {
      print('Ошибка отметки прочитанным: $e');
    }
  }

  Future<void> getUsers() async {
    if (!_isConnected) return;

    try {
      final request = {
        'type': 'get_users',
      };

      _channel!.sink.add(jsonEncode(request));
    } catch (e) {
      print('Ошибка получения списка пользователей: $e');
    }
  }

  void _listenToMessages() {
    _channel!.stream.listen(
      (data) {
        print('DEBUG NetworkService._listenToMessages: Получены данные: $data');
        _handleServerMessage(data);
      },
      onError: (error) {
        print('Ошибка WebSocket: $error');
        _handleDisconnection();
      },
      onDone: () {
        print('WebSocket соединение закрыто');
        _handleDisconnection();
      },
    );
  }

  void _handleServerMessage(String data) {
    try {
      final jsonData = jsonDecode(data);
      print('DEBUG NetworkService._handleServerMessage: Разобранный JSON: $jsonData');
      
      final type = jsonData['type'];
      
      switch (type) {
        case 'new_message':
          print('DEBUG NetworkService: Получено new_message');
          // Server sends { type: 'new_message', message: {...} }
          final payload = (jsonData['message'] as Map<String, dynamic>?) ?? (jsonData['data'] as Map<String, dynamic>?) ?? jsonData;
          _handleNewMessageAsync(payload);
          break;
        case 'offline_message':
          // Эфемерный режим: игнорируем офлайн-доставку
          print('DEBUG NetworkService: offline_message игнорируется (эфемерный режим)');
          break;
        case 'message':
          // Эфемерный режим: игнорируем offline delivery
          print('DEBUG NetworkService: message (offline delivery) игнорируется (эфемерный режим)');
          break;
        case 'message_sent':
          print('DEBUG NetworkService: Получено message_sent');
          // Добавляем собственное отправленное сообщение в поток, чтобы оно отобразилось в UI
          try {
            final payload = (jsonData['message'] as Map<String, dynamic>?)
                ?? (jsonData['data'] as Map<String, dynamic>?)
                ?? jsonData;
            // Если это подтверждение для НАШЕГО сообщения, пропускаем, чтобы не показывать зашифрованный JSON
            final senderId = payload['senderId'] as String?;
            if (senderId != null && senderId == _userId) {
              print('DEBUG NetworkService: message_sent от нас самих — пропускаем отображение');
              break;
            }
            _handleNewMessageAsync(payload);
          } catch (e) {
            print('DEBUG NetworkService: Ошибка обработки message_sent: $e');
          }
          break;
        case 'message_read':
          print('DEBUG NetworkService: Получено message_read');
          break;
        case 'chat_added':
          print('DEBUG NetworkService: Получено chat_added');
          final userId = jsonData['user_id'] as String?;
          final nickname = jsonData['nickname'] as String?;
          if (userId != null) {
            _newChatController.add(userId);
            print('DEBUG NetworkService: Отправлено уведомление о новом чате для $userId');
          }
          break;
        case 'add_to_chat_success':
          print('DEBUG NetworkService: Получено add_to_chat_success');
          break;
        case 'users_list':
          print('DEBUG NetworkService: Получено users_list');
          final users = (jsonData['users'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _cacheUsersKeys(users);
          // Обновляем локальный список онлайн-пользователей
          _onlineUsers.clear();
          for (final u in users) {
            final id = (u['userId'] ?? u['id']) as String?;
            if (id == null) continue;
            final onlineRaw = u['isOnline'] ?? u['online'] ?? u['status'];
            bool isOnline;
            if (onlineRaw is bool) {
              isOnline = onlineRaw;
            } else if (onlineRaw is String) {
              final lower = onlineRaw.toLowerCase();
              isOnline = lower == 'true' || lower == 'online' || lower == '1';
            } else if (onlineRaw is num) {
              isOnline = onlineRaw != 0;
            } else {
              isOnline = false;
            }
            if (isOnline) _onlineUsers.add(id);
            // Пушим статус, чтобы UI сразу обновился
            _userStatusController.add({'userId': id, 'isOnline': isOnline});
          }
          _usersController.add(users);
          break;
        case 'user_status_update':
          print('DEBUG NetworkService: Получено user_status_update');
          _handleUserStatusUpdate(jsonData);
          break;
        case 'pong':
          break;
        case 'error':
          print('Ошибка сервера: ${jsonData['message']}');
          break;
      }
    } catch (e) {
      print('Ошибка обработки сообщения: $e');
    }
  }

  // Совместимость: синхронная обёртка
  void _handleNewMessage(Map<String, dynamic> data) {
    _handleNewMessageAsync(data);
  }

  // Асинхронная обработка: пытаемся расшифровать, затем пушим в стрим
  Future<void> _handleNewMessageAsync(Map<String, dynamic> data) async {
    try {
      final Map<String, dynamic> msgJson = Map<String, dynamic>.from(data);

      // Пытаемся расшифровать, если есть encryptedContent
      final decrypted = await _tryDecryptMessage(msgJson);
      if (decrypted != null) {
        msgJson['content'] = decrypted;
        msgJson['isEncrypted'] = true;
      } else {
        // Если это наше же сообщение и расшифровки нет — не показываем зашифрованный JSON
        final sid = msgJson['senderId'];
        final hasEnc = msgJson['encryptedContent'] != null;
        if (sid != null && sid == _userId && hasEnc) {
          print('DEBUG _handleNewMessageAsync: own echoed message without decryption, skip to avoid showing encrypted JSON');
          return;
        }
        // Фолбек: если encryptedContent является простой строкой (не JSON), трактуем её как plaintext
        final encField = msgJson['encryptedContent'];
        if (encField is String) {
          try {
            // Если это не JSON — будет исключение, значит это простой текст
            jsonDecode(encField);
          } catch (_) {
            msgJson['content'] = encField;
            msgJson['isEncrypted'] = false;
            print('DEBUG _handleNewMessageAsync: plaintext fallback из encryptedContent строки');
          }
        }
      }

      final message = Message.fromJson(msgJson);
      print('DEBUG NetworkService._handleNewMessageAsync: Создано сообщение: ${message.id}');
      _storeInMemory(message);
      _newMessageController.add(message);
    } catch (e) {
      print('Ошибка обработки нового сообщения: $e');
    }
  }

  void _storeInMemory(Message message) {
    try {
      final myId = _userId;
      if (myId == null) return;
      final otherId = message.senderId == myId ? message.receiverId : message.senderId;
      final key = otherId;
      final list = _inMemoryByPeer.putIfAbsent(key, () => <Message>[]);
      list.add(message);
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      // Можно ограничить размер в будущем (например, до 200 сообщений)
    } catch (e) {
      print('DEBUG _storeInMemory: ошибка: $e');
    }
  }

  // Возвращает plaintext или null, если расшифровать не удалось/не требуется
  Future<String?> _tryDecryptMessage(Map<String, dynamic> msgJson) async {
    try {
      final encField = msgJson['encryptedContent'];
      if (encField == null) return null;

      // encryptedContent может быть plain-строкой или JSON-строкой EncryptedMessage
      EncryptedMessage? enc;
      if (encField is String) {
        try {
          final parsed = jsonDecode(encField);
          if (parsed is Map<String, dynamic>) {
            enc = EncryptedMessage.fromJson(parsed);
          }
        } catch (_) {
          // не JSON — вероятно, plaintext
          return null;
        }
      } else if (encField is Map<String, dynamic>) {
        enc = EncryptedMessage.fromJson(encField);
      }

      if (enc == null) return null;

      final senderId = msgJson['senderId'] as String?;
      if (senderId == null) return null;

      // Нужны публичные ключи отправителя
      String? encKeyB64 = _publicEncKeys[senderId];
      String? signKeyB64 = _publicSignKeys[senderId];
      if (encKeyB64 == null || signKeyB64 == null) {
        // если сообщение наше собственное — возьмём публичные ключи из KeyManager
        if (senderId == _userId) {
          try {
            final keys = await KeyManager.loadUserKeys();
            if (keys != null) {
              final spk = await keys.signingKeyPair.extractPublicKey();
              final epk = await keys.encryptionKeyPair.extractPublicKey();
              _publicSignKeys[senderId] = await KeyManager.publicKeyToString(spk);
              _publicEncKeys[senderId] = await KeyManager.publicKeyToString(epk);
              encKeyB64 = _publicEncKeys[senderId];
              signKeyB64 = _publicSignKeys[senderId];
            }
          } catch (_) {}
        }
        // иначе попробуем подтянуть список пользователей
        if (encKeyB64 == null || signKeyB64 == null) {
          await _ensureRecipientKeys(senderId);
        }
      }

      final encKeyB64b = _publicEncKeys[senderId];
      final signKeyB64b = _publicSignKeys[senderId];
      if (encKeyB64b == null || signKeyB64b == null) return null;

      final senderEncKey = await KeyManager.publicKeyFromString(encKeyB64b, isEncryption: true);
      final senderSignKey = await KeyManager.publicKeyFromString(signKeyB64b, isEncryption: false);

      final plaintext = await CryptoEngine.decryptMessage(enc, senderEncKey, senderSignKey);
      return plaintext;
    } catch (e) {
      print('DEBUG _tryDecryptMessage: не удалось расшифровать: $e');
      return null;
    }
  }

  void _handleUserStatusUpdate(Map<String, dynamic> data) {
    try {
      print('DEBUG NetworkService._handleUserStatusUpdate: Обновление статуса пользователя: $data');
      // Нормализуем ключи: допускаем user_id/online и строковые булевы
      final uid = (data['userId'] ?? data['user_id']) as String?;
      dynamic onlineRaw = data['isOnline'] ?? data['online'] ?? data['status'];
      bool isOnline;
      if (onlineRaw is bool) {
        isOnline = onlineRaw;
      } else if (onlineRaw is String) {
        final lower = onlineRaw.toLowerCase();
        isOnline = lower == 'true' || lower == 'online' || lower == '1';
      } else if (onlineRaw is num) {
        isOnline = onlineRaw != 0;
      } else {
        isOnline = false;
      }
      if (uid != null) {
        final normalized = {'userId': uid, 'isOnline': isOnline};
        _userStatusController.add(normalized);
        // Обновляем локальное состояние онлайна
        if (isOnline) {
          _onlineUsers.add(uid);
          // Пробуем отправить отложенные сообщения этому пользователю
          final pending = _pendingByReceiver.remove(uid);
          if (pending != null && pending.isNotEmpty) {
            print('DEBUG NetworkService: Флаш отложенных сообщений для $uid: ${pending.length}');
            // Последовательно отправляем, не дублируя локальные сообщения
            () async {
              for (final p in pending) {
                try { await _sendToServer(p.receiverId, p.content, p.type, timestamp: p.timestamp, emitLocal: false); } catch (_) {}
              }
            }();
          }
        } else {
          _onlineUsers.remove(uid);
        }
      }
    } catch (e) {
      print('Ошибка обработки обновления статуса пользователя: $e');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isConnected) {
        _channel!.sink.add(jsonEncode({'type': 'ping'}));
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
  }

  void _handleDisconnection() {
    _isConnected = false;
    _stopHeartbeat();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;
    
    _reconnectTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (_reconnectAttempt < 5) {
          _reconnectAttempt++;
          connect();
        } else {
          _reconnectTimer?.cancel();
          _reconnectTimer = null;
        }
      },
    );
  }

  void disconnect() {
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _newMessageController.close();
    _chatsController.close();
    _usersController.close();
    _connectionController.close();
    _userStatusController.close();
    _newChatController.close();
  }

  // Проверка текущего онлайн-статуса пользователя по локальному набору
  bool isUserOnline(String userId) {
    return _onlineUsers.contains(userId);
  }

  void _sendMessage(Map<String, dynamic> message) {
    if (_channel != null) {
      final jsonMessage = jsonEncode(message);
      print('DEBUG: Отправка сообщения на сервер: $jsonMessage');
      _channel!.sink.add(jsonMessage);
    } else {
      print('DEBUG: Попытка отправить сообщение, но канал не подключен');
    }
  }

  Future<Map<String, dynamic>?> _waitForResponse(String expectedType, {Duration timeout = const Duration(seconds: 10)}) async {
    try {
      final completer = Completer<Map<String, dynamic>>();
      late StreamSubscription subscription;
      
      // Слушаем через единый _broadcastStream, чтобы избежать дублирующих подписок
      final bs = _broadcastStream;
      if (bs == null) {
        throw StateError('Broadcast stream not initialized');
      }
      subscription = bs.listen(
        (data) {
          try {
            final message = jsonDecode(data);
            if (message['type'] == expectedType) {
              subscription.cancel();
              if (!completer.isCompleted) {
                completer.complete(message);
              }
            }
          } catch (e) {
            print('Ошибка парсинга ответа: $e');
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        },
      );
      
      return await completer.future.timeout(timeout);
    } catch (e) {
      print('Ошибка ожидания ответа $expectedType: $e');
      return null;
    }
  }
  
  /// Добавляет пользователя в чат
  Future<bool> addUserToChat(String targetUserId) async {
    if (!_isConnected || _userId == null) {
      print('DEBUG NetworkService.addUserToChat: Не подключен или нет userId');
      return false;
    }

    try {
      final message = {
        'type': 'add_to_chat',
        'target_user_id': targetUserId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      print('DEBUG NetworkService.addUserToChat: Отправка запроса: $message');
      _channel!.sink.add(jsonEncode(message));
      
      // Ждем ответ от сервера
      final response = await _waitForResponse('add_to_chat_success');
      if (response != null) {
        print('DEBUG NetworkService.addUserToChat: Пользователь добавлен в чат');
        return true;
      }
      
      print('DEBUG NetworkService.addUserToChat: Ошибка при добавлении');
      return false;
    } catch (e) {
      print('DEBUG NetworkService.addUserToChat: Ошибка: $e');
      return false;
    }
  }
}

// Приватная модель для локальной очереди сообщений (Option B: local outbox)
class _PendingMessage {
  final String receiverId;
  final String content;
  final MessageType type;
  final DateTime timestamp;

  const _PendingMessage({
    required this.receiverId,
    required this.content,
    required this.type,
    required this.timestamp,
  });
}