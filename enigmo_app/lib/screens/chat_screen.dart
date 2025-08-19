import 'package:flutter/material.dart';
import 'dart:async';
import '../models/message.dart';
import '../models/chat.dart';
import '../services/network_service.dart';
import '../services/crypto_engine.dart';
import '../services/key_manager.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;

  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final NetworkService _networkService;
  
  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _otherOnline = false;
  StreamSubscription? _statusSub;
  StreamSubscription? _newMsgSub;
  bool _poppedOnOffline = false;

  @override
  void initState() {
    super.initState();
    _networkService = NetworkService(); // Получаем синглтон
    _otherOnline = widget.chat.isOnline;
    _setupMessageListener();
    _loadMessages();
    _setupStatusListener();
    _refreshOtherUserStatus();
  }

  void _setupMessageListener() {
    _newMsgSub = _networkService.newMessages.listen((message) {
      print('DEBUG ChatScreen: Получено новое сообщение: ${message.id}');
      print('DEBUG ChatScreen: senderId=${message.senderId}, receiverId=${message.receiverId}');
      print('DEBUG ChatScreen: otherUserId=${_getOtherUserId()}');
      
      // Проверяем, относится ли сообщение к этому чату
      final otherUserId = _getOtherUserId();
      if (message.senderId == otherUserId || message.receiverId == otherUserId) {
        print('DEBUG ChatScreen: Сообщение относится к этому чату, добавляем');
        setState(() {
          _messages.add(message);
          _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        });
        _scrollToBottom();
      } else {
        print('DEBUG ChatScreen: Сообщение НЕ относится к этому чату');
      }
    });
  }

  void _setupStatusListener() {
    final otherUserId = _getOtherUserId();
    _statusSub = _networkService.userStatusUpdates.listen((data) {
      final uid = data['userId'] as String?;
      final isOnline = data['isOnline'] as bool?;
      print('DEBUG ChatScreen._setupStatusListener: пришёл статус uid=$uid, isOnline=$isOnline, otherUserId=$otherUserId');
      if (uid == otherUserId && isOnline != null) {
        if (!isOnline) {
          // Собеседник вышел полностью — закрываем чат и чистим локальные данные
          if (!_poppedOnOffline) {
            _poppedOnOffline = true;
            _networkService.clearPeerSession(otherUserId);
            if (mounted) {
              Navigator.of(context).maybePop();
            }
          }
          return;
        }
        if (mounted) {
          setState(() {
            _otherOnline = isOnline;
          });
        }
      }
    });
  }

  // Разово обновляем статус собеседника из списка пользователей
  Future<void> _refreshOtherUserStatus() async {
    try {
      final otherUserId = _getOtherUserId();
      print('DEBUG ChatScreen._refreshOtherUserStatus: запрос статуса для $otherUserId');
      // Подпишемся один раз и дождёмся users_list
      late StreamSubscription usersSub;
      usersSub = _networkService.users.listen((users) {
        try {
          final u = users.firstWhere(
            (e) => (e['userId'] ?? e['id']) == otherUserId,
            orElse: () => {},
          );
          if (u.isNotEmpty) {
            final onlineRaw = u['isOnline'] ?? u['online'] ?? u['status'];
            final isOnline = onlineRaw is bool
                ? onlineRaw
                : onlineRaw is String
                    ? (onlineRaw.toLowerCase() == 'true' || onlineRaw.toLowerCase() == 'online' || onlineRaw == '1')
                    : onlineRaw is num
                        ? onlineRaw != 0
                        : false;
            print('DEBUG ChatScreen._refreshOtherUserStatus: найден статус=$isOnline');
            setState(() {
              _otherOnline = isOnline;
            });
          }
        } finally {
          usersSub.cancel();
        }
      });
      await _networkService.getUsers();
    } catch (e) {
      print('DEBUG ChatScreen._refreshOtherUserStatus: ошибка: $e');
    }
  }

  String _getOtherUserId() {
    // Получаем ID другого пользователя из участников чата
    final result = widget.chat.participants.firstWhere(
      (id) => id != _networkService.userId,
      orElse: () {
        print('DEBUG ChatScreen _getOtherUserId: Не найден другой пользователь, возвращаем первого: ${widget.chat.participants.first}');
        return widget.chat.participants.first;
      },
    );
    print('DEBUG ChatScreen _getOtherUserId: Результат=$result');
    return result;
  }

  Future<void> _loadMessages() async {
    // Загружаем сообщения из локального буфера сеанса
    try {
      final otherUserId = _getOtherUserId();
      final msgs = _networkService.getRecentMessages(otherUserId);
      print('DEBUG ChatScreen _loadMessages: загружено из буфера: ${msgs.length}');
      setState(() {
        _messages = msgs..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      print('DEBUG ChatScreen _loadMessages: ошибка загрузки из буфера: $e');
      setState(() {
        _messages = [];
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatMessageTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${dateTime.day}.${dateTime.month}';
    } else {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _newMsgSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inDays > 0) {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    } else if (difference.inHours > 0) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              backgroundColor: _otherOnline ? Colors.green : Colors.grey,
              radius: 16,
              child: Text(
                widget.chat.name[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.chat.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _otherOnline ? 'в сети' : 'не в сети',
                    style: TextStyle(
                      fontSize: 12,
                      color: _otherOnline ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMessages,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Нет сообщений\nНапишите первое сообщение!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isMe = message.senderId == _networkService.userId;
                          return _buildMessageBubble(message, isMe);
                        },
                      ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.circular(18),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                   _formatTime(message.timestamp),
                   style: TextStyle(
                     color: isMe ? Colors.white70 : Colors.black54,
                     fontSize: 12,
                   ),
                 ),
                 if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      message.status == MessageStatus.read ? Icons.done_all : Icons.done,
                      color: message.status == MessageStatus.read ? Colors.lightBlue : Colors.white70,
                      size: 16,
                    ),
                  ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Введите сообщение...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          const SizedBox(width: 8),
          _isSending
              ? const SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : IconButton(
                  onPressed: () {
                    print('DEBUG: Кнопка отправки нажата');
                    _sendMessage();
                  },
                  icon: const Icon(Icons.send),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: const CircleBorder(),
                  ),
                ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    print('DEBUG ChatScreen _sendMessage: text="$text", _isSending=$_isSending');
    if (text.isEmpty || _isSending) {
      print('DEBUG ChatScreen _sendMessage: Выход - пустой текст или уже отправляется');
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final otherUserId = _getOtherUserId();
      print('DEBUG ChatScreen _sendMessage: otherUserId=$otherUserId, myUserId=${_networkService.userId}');
      final success = await _networkService.sendMessage(
        otherUserId,
        text,
        type: MessageType.text,
      );
      print('DEBUG ChatScreen _sendMessage: success=$success');

      if (success) {
        _messageController.clear();
        // Сообщение будет добавлено через listener при получении подтверждения
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось отправить сообщение')),
        );
      }
    } catch (e) {
      print('Ошибка отправки сообщения: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }
}