import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../services/network_service.dart';
import '../services/key_manager.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final NetworkService _networkService = NetworkService();
  List<Chat> _chats = [];
  bool _isConnecting = false;
  bool _isConnected = false;
  Timer? _refreshTimer;
  String? _currentUserId;
  String? _activeChatUserId; // пользователь, чат с которым сейчас открыт
  StreamSubscription<Map<String, dynamic>>? _statusSub;
  bool _isResetting = false;

  @override
  void initState() {
    super.initState();
    _initializeNetwork();
    _statusSub = _networkService.userStatusUpdates.listen((data) {
      final uid = data['userId'] as String?;
      final isOnline = data['isOnline'] as bool? ?? false;
      if (uid == null || uid == _currentUserId) return;
      if (!isOnline) {
        // Пользователь вышел — удаляем чат и чистим локальные данные
        _networkService.clearPeerSession(uid);
        setState(() {
          _chats.removeWhere((c) => c.id == uid);
          if (_activeChatUserId == uid) {
            _activeChatUserId = null;
          }
        });
      }
    });
  }

  /// Полный сброс сессии: очистка локальных данных, новый ID и переподключение
  Future<void> _resetAll() async {
    if (_isResetting) return;
    setState(() {
      _isResetting = true;
      _isConnecting = true;
    });
    try {
      _refreshTimer?.cancel();
      setState(() {
        _chats.clear();
        _activeChatUserId = null;
      });

      final ok = await _networkService.resetSession();
      if (!mounted) return;
      if (ok) {
        setState(() {
          _currentUserId = _networkService.userId;
          _isConnected = true;
        });
        _startPeriodicRefresh();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Новая сессия создана. Вы получили новый ID')),
        );
      } else {
        setState(() {
          _isConnected = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось создать новую сессию'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResetting = false;
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _initializeNetwork() async {
    print('INFO ChatListScreen._initializeNetwork: Начало инициализации сети');
    
    setState(() {
      _isConnecting = true;
    });

    try {
      // Подключаемся к серверу
      print('INFO ChatListScreen._initializeNetwork: Подключение к серверу');
      final connected = await _networkService.connect();
      
      if (!connected) {
        throw Exception('Не удалось подключиться к серверу');
      }
      
      print('INFO ChatListScreen._initializeNetwork: Подключение к серверу успешно');
      
      // Проверяем, есть ли сохраненный userId
      final storedUserId = await KeyManager.getUserId();
      print('INFO ChatListScreen._initializeNetwork: Сохраненный userId: $storedUserId');
      
      bool needsRegistration = storedUserId == null;
      
      if (!needsRegistration) {
        try {
          print('INFO ChatListScreen._initializeNetwork: Попытка аутентификации с существующим userId');
          // Пытаемся аутентифицироваться с существующим userId
          final authenticated = await _networkService.authenticate();
          if (!authenticated) {
            print('WARNING ChatListScreen._initializeNetwork: Аутентификация неудачна, требуется регистрация');
            needsRegistration = true;
          } else {
            print('INFO ChatListScreen._initializeNetwork: Аутентификация успешна');
          }
        } catch (e) {
          print('ERROR ChatListScreen._initializeNetwork: Ошибка аутентификации: $e');
          needsRegistration = true;
        }
      }
      
      if (needsRegistration) {
        print('INFO ChatListScreen._initializeNetwork: Регистрация нового пользователя');
        // Если аутентификация не удалась, регистрируем нового пользователя
        final userId = await _networkService.registerUser(nickname: 'Пользователь');
        if (userId != null) {
          print('INFO ChatListScreen._initializeNetwork: Пользователь зарегистрирован: $userId');
          final authSuccess = await _networkService.authenticate();
          if (!authSuccess) {
            throw Exception('Не удалось аутентифицироваться после регистрации');
          }
          print('INFO ChatListScreen._initializeNetwork: Аутентификация после регистрации успешна');
        } else {
          throw Exception('Не удалось зарегистрировать пользователя');
        }
      }
      
      // Загружаем список чатов
      print('INFO ChatListScreen._initializeNetwork: Загрузка чатов');
      await _loadChats();
      
      // Запускаем периодическое обновление списка пользователей
      _startPeriodicRefresh();
      
      // Слушаем новые сообщения
      _networkService.newMessages.listen((message) {
        print('INFO ChatListScreen: Получено новое сообщение: ${message.id}');
        _handleNewMessage(message);
      });
      
      // Слушаем обновления списка пользователей
      _networkService.chats.listen((chats) {
        print('INFO ChatListScreen: Обновление списка чатов: ${chats.length} чатов');
        setState(() {
          // Обновляем только если список не пустой или если мы очищаем список
          if (chats.isNotEmpty || _chats.isNotEmpty) {
            _chats = chats;
          }
        });
      });
      
      // Слушаем статус подключения
      _networkService.connectionStatus.listen((connected) {
        print('INFO ChatListScreen: Изменение статуса подключения: $connected');
        setState(() {
          _isConnected = connected;
          if (!connected) {
            _refreshTimer?.cancel();
          } else {
            // При восстановлении подключения пытаемся переаутентифицироваться
            _handleReconnection();
          }
        });
      });
      
      // Слушаем уведомления о новых чатах
      _networkService.newChatNotifications.listen((userId) {
        print('INFO ChatListScreen: Уведомление о новом чате: $userId');
        _handleNewChatNotification({'userId': userId});
      });
      
      // Слушаем обновления статуса пользователей
      _networkService.userStatusUpdates.listen((statusData) {
        print('INFO ChatListScreen: Обновление статуса пользователя: $statusData');
        _handleUserStatusUpdate(statusData);
      });
      
      // Устанавливаем статус подключения как активный
      setState(() {
        _isConnected = true;
        _currentUserId = _networkService.userId;
      });
      // Инициализируем статусы онлайна (users_list)
      try {
        await _networkService.getUsers();
      } catch (_) {}
      
      print('INFO ChatListScreen._initializeNetwork: Инициализация сети завершена успешно');
    } catch (e, stackTrace) {
      print('ERROR ChatListScreen._initializeNetwork: Ошибка инициализации сети: $e');
      print('STACK: $stackTrace');
      
      setState(() {
        _isConnected = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка подключения к серверу: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _loadChats() async {
    print('INFO ChatListScreen._loadChats: Загрузка чатов');
    // Убираем автоматическую загрузку всех пользователей
    // Теперь чаты будут добавляться только через диалог добавления
    setState(() {
      // Оставляем только существующие чаты, не загружаем всех пользователей
    });
  }

  /// Обрабатывает переподключение
  Future<void> _handleReconnection() async {
    print('INFO ChatListScreen._handleReconnection: Обработка переподключения');
    
    if (!_isConnected) {
      print('WARNING ChatListScreen._handleReconnection: Нет подключения, пропускаем переаутентификацию');
      return;
    }
    
    try {
      final storedUserId = await KeyManager.getUserId();
      if (storedUserId != null) {
        print('INFO ChatListScreen._handleReconnection: Попытка переаутентификации');
        final authenticated = await _networkService.authenticate();
        if (authenticated) {
          print('INFO ChatListScreen._handleReconnection: Переаутентификация успешна');
          setState(() {
            _currentUserId = _networkService.userId;
          });
          _startPeriodicRefresh();
        } else {
          print('WARNING ChatListScreen._handleReconnection: Переаутентификация неудачна');
        }
      }
    } catch (e) {
      print('ERROR ChatListScreen._handleReconnection: Ошибка переаутентификации: $e');
    }
  }

  void _handleNewMessage(Message message) {
    // Обновляем соответствующий чат
    setState(() {
      final chatIndex = _chats.indexWhere((chat) => 
        chat.participants.contains(message.senderId) || chat.participants.contains(message.receiverId));
      
      if (chatIndex != -1) {
        final isFromMe = message.senderId == _currentUserId;
        final isChatOpen = _activeChatUserId != null &&
            (_chats[chatIndex].participants.contains(_activeChatUserId));

        final shouldIncrementUnread = !isFromMe && !isChatOpen;

        _chats[chatIndex] = _chats[chatIndex].copyWith(
          lastMessage: message,
          unreadCount: shouldIncrementUnread ? _chats[chatIndex].unreadCount + 1 : _chats[chatIndex].unreadCount,
          lastActivity: message.timestamp,
        );
        
        // Перемещаем чат в начало списка
        final chat = _chats.removeAt(chatIndex);
        _chats.insert(0, chat);
      }
    });
  }

  /// Запускает периодическое обновление списка пользователей
  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected && mounted) {
        _loadChats();
        // Регулярно обновляем список пользователей, чтобы подтянуть статусы онлайна
        _networkService.getUsers();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _statusSub?.cancel();
    _networkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _currentUserId != null ? () => _copyUserId() : null,
          child: Text(
            _currentUserId != null ? 'ID: $_currentUserId' : 'Anongram',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
            ),
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // Индикатор подключения
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isConnected ? Icons.wifi : Icons.wifi_off,
                  color: _isConnected ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  _isConnected ? 'Онлайн' : 'Офлайн',
                  style: TextStyle(
                    color: _isConnected ? Colors.green : Colors.red,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _isConnected ? _showAddUserDialog : null,
          ),
        ],
      ),
      body: _isConnecting
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Подключение к серверу...'),
                ],
              ),
            )
          : _chats.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Нет активных чатов',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Другие пользователи появятся здесь',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _chats.length,
                  itemBuilder: (context, index) {
                    final chat = _chats[index];
                    return _buildChatTile(chat);
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isResetting ? null : _resetAll,
        tooltip: 'Новая сессия',
        child: _isResetting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.autorenew),
      ),
    );
  }

  Widget _buildChatTile(Chat chat) {
    final online = chat.isOnline || _networkService.isUserOnline(chat.id);
    return InkWell(
      onTap: () async {
        print('DEBUG: Переход в чат с пользователем: ${chat.name} (ID: ${chat.id})');
        setState(() {
          _activeChatUserId = chat.id; // для direct чатов id = userId собеседника
          // Сбрасываем счётчик непрочитанных сразу при входе в чат
          final idx = _chats.indexWhere((c) => c.id == chat.id);
          if (idx != -1) {
            _chats[idx] = _chats[idx].copyWith(unreadCount: 0);
          }
        });
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(chat: chat),
          ),
        );
        // Вернулись из чата — обнуляем счётчик непрочитанных
        setState(() {
          final idx = _chats.indexWhere((c) => c.id == chat.id);
          if (idx != -1) {
            _chats[idx] = _chats[idx].copyWith(unreadCount: 0);
          }
          _activeChatUserId = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Color(0xFF2C3E50),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: const Color(0xFF40A7E3),
                  child: Text(
                    chat.name[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: online ? const Color(0xFF4CAF50) : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0F1419),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            // Chat info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          chat.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatTime(chat.lastActivity),
                        style: TextStyle(
                          color: chat.unreadCount > 0
                              ? const Color(0xFF40A7E3)
                              : Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat.lastMessage?.content ?? 'Нет сообщений',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (chat.unreadCount > 0 && chat.id != _activeChatUserId)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF40A7E3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            chat.unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}д';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}ч';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}м';
    } else {
      return 'сейчас';
    }
  }

  /// Копирует ID пользователя в буфер обмена
  void _copyUserId() {
    if (_currentUserId != null) {
      Clipboard.setData(ClipboardData(text: _currentUserId!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ID скопирован в буфер обмена'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Показывает диалог добавления пользователя
  void _showAddUserDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Добавить пользователя'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Скопировать мой ID'),
                subtitle: Text(_currentUserId ?? ''),
                onTap: () {
                  _copyUserId();
                  Navigator.of(context).pop();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.person_add),
                title: const Text('Добавить в чат'),
                subtitle: const Text('Введите ID пользователя'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showAddUserByIdDialog();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
          ],
        );
      },
    );
  }

  /// Показывает диалог ввода ID пользователя
  void _showAddUserByIdDialog() {
    final TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Добавить пользователя'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'ID пользователя',
              hintText: 'Введите ID пользователя для добавления в чат',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                final userId = controller.text.trim();
                if (userId.isNotEmpty) {
                  Navigator.of(context).pop();
                  _addUserToChat(userId);
                }
              },
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );
  }

  /// Обрабатывает обновления статуса пользователей
  void _handleUserStatusUpdate(Map<String, dynamic> data) {
    final userId = data['userId'] as String?;
    final isOnline = data['isOnline'] as bool? ?? false;
    
    if (userId == null) return;
    
    setState(() {
      // Находим чат с этим пользователем и обновляем его статус
      final chatIndex = _chats.indexWhere((chat) => 
        chat.participants.contains(userId));
      
      if (chatIndex != -1) {
        _chats[chatIndex] = _chats[chatIndex].copyWith(isOnline: isOnline);
        print('INFO ChatListScreen: Обновлен статус пользователя $userId: ${isOnline ? "онлайн" : "офлайн"}');
      }
    });
  }

  /// Добавляет пользователя в чат по ID
  /// Обрабатывает уведомление о добавлении в чат другим пользователем
  void _handleNewChatNotification(Map<String, dynamic> data) {
    final userId = data['userId'] as String;
    final nickname = data['nickname'] as String?;
    final isInitiator = data['isInitiator'] as bool? ?? false;
    final isOnline = data['isOnline'] as bool? ?? false;
    final lastSeen = data['lastSeen'] as String?;
    
    // Проверяем, есть ли уже чат с этим пользователем
    final existingChatIndex = _chats.indexWhere((chat) =>
      chat.participants.contains(userId));
    
    if (existingChatIndex == -1) {
      // Создаем новый чат
      final newChat = Chat(
        id: userId,
        name: nickname ?? userId,
        participants: [_currentUserId!, userId],
        lastMessage: null,
        unreadCount: 0,
        lastActivity: lastSeen != null ? DateTime.parse(lastSeen) : DateTime.now(),
        type: ChatType.direct,
        isOnline: isOnline,
      );

      setState(() {
        _chats.insert(0, newChat);
      });

      final displayName = nickname ?? userId;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isInitiator
              ? 'Пользователь $displayName добавлен в чаты'
              : 'Пользователь $displayName добавил вас в чат'),
          backgroundColor: isInitiator ? Colors.green : Colors.blue,
        ),
      );
    } else if (isInitiator) {
      // Если это инициатор и чат уже существует, просто переходим к нему
      final existingChat = _chats[existingChatIndex];
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(chat: existingChat),
        ),
      );
    }
  }

  Future<void> _addUserToChat(String userId) async {
    try {
      // Проверяем, что это не наш собственный ID
      if (userId == _currentUserId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нельзя добавить самого себя в чат'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Проверяем, есть ли уже чат с этим пользователем
      final existingChatIndex = _chats.indexWhere((chat) => 
        chat.participants.contains(userId));
      
      if (existingChatIndex != -1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Чат с этим пользователем уже существует'),
            backgroundColor: Colors.orange,
          ),
        );
        
        // Переходим к существующему чату
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(chat: _chats[existingChatIndex]),
          ),
        );
        return;
      }

      // Отправляем запрос на сервер для добавления пользователя в чат
      await _networkService.addUserToChat(userId);
      
      // Создаем локальный чат для инициатора
      final targetUser = Chat(
        id: userId,
        name: userId,
        participants: [_currentUserId!, userId],
        lastMessage: null,
        unreadCount: 0,
        lastActivity: DateTime.now(),
        type: ChatType.direct,
        isOnline: false,
      );

      // Добавляем новый чат
      setState(() {
        _chats.insert(0, targetUser);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Пользователь $userId добавлен в чаты'),
          backgroundColor: Colors.green,
        ),
      );

      // Переходим к новому чату
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(chat: targetUser),
        ),
      );

    } catch (e) {
      print('Ошибка добавления пользователя: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}