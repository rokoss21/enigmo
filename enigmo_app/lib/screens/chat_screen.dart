import 'package:flutter/material.dart';
import 'dart:async';
import '../models/message.dart';
import '../models/chat.dart';
import '../services/network_service.dart';
import '../services/crypto_engine.dart';
import '../services/key_manager.dart';
import '../services/audio_call_service.dart';
import '../widgets/message_bubble.dart';
import '../models/call.dart';
import '../screens/audio_call_screen.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;
  final AudioCallService audioCallService;

  const ChatScreen({super.key, required this.chat, required this.audioCallService});

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
    _networkService = NetworkService(); // Get singleton
    _otherOnline = widget.chat.isOnline;
    _setupMessageListener();
    _loadMessages();
    _setupStatusListener();
    _refreshOtherUserStatus();
    
    // Set up call status listener
    widget.audioCallService.onCallStatusChange = _handleCallStatusChange;
  }

  void _setupMessageListener() {
    _newMsgSub = _networkService.newMessages.listen((message) {
      print('DEBUG ChatScreen: Received new message: ${message.id}');
      print('DEBUG ChatScreen: senderId=${message.senderId}, receiverId=${message.receiverId}');
      print('DEBUG ChatScreen: content="${message.content}"');
      print('DEBUG ChatScreen: otherUserId=${_getOtherUserId()}');
      print('DEBUG ChatScreen: current userId=${_networkService.userId}');

      // Check if the message belongs to this chat
      final otherUserId = _getOtherUserId();
      final currentUserId = _networkService.userId;

      if ((message.senderId == otherUserId && message.receiverId == currentUserId) ||
          (message.senderId == currentUserId && message.receiverId == otherUserId)) {
        print('DEBUG ChatScreen: Message belongs to this chat, adding');
        setState(() {
          _messages.add(message);
          _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        });
        _scrollToBottom();
      } else {
        print('DEBUG ChatScreen: Message does NOT belong to this chat');
        print('DEBUG ChatScreen: Expected sender/receiver: $otherUserId/$currentUserId');
      }
    });
  }

  void _setupStatusListener() {
    final otherUserId = _getOtherUserId();
    _statusSub = _networkService.userStatusUpdates.listen((data) {
      final uid = data['userId'] as String?;
      final isOnline = data['isOnline'] as bool?;
      print('DEBUG ChatScreen._setupStatusListener: received status uid=$uid, isOnline=$isOnline, otherUserId=$otherUserId');
      if (uid == otherUserId && isOnline != null) {
        if (!isOnline) {
          // Peer went fully offline — close the chat and clear local data
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

  // One-time refresh of the peer's status from the users list
  Future<void> _refreshOtherUserStatus() async {
    try {
      final otherUserId = _getOtherUserId();
      print('DEBUG ChatScreen._refreshOtherUserStatus: requesting status for $otherUserId');
      // Subscribe once and wait for users_list
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
            print('DEBUG ChatScreen._refreshOtherUserStatus: found status=$isOnline');
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
      print('DEBUG ChatScreen._refreshOtherUserStatus: error: $e');
    }
  }

  String _getOtherUserId() {
    // Get the other user's ID from chat participants
    final result = widget.chat.participants.firstWhere(
      (id) => id != _networkService.userId,
      orElse: () {
        print('DEBUG ChatScreen _getOtherUserId: Other user not found, returning first: ${widget.chat.participants.first}');
        return widget.chat.participants.first;
      },
    );
    print('DEBUG ChatScreen _getOtherUserId: Result=$result');
    return result;
  }

  Future<void> _loadMessages() async {
    // Load messages from the local session buffer
    try {
      final otherUserId = _getOtherUserId();
      final msgs = _networkService.getRecentMessages(otherUserId);
      print('DEBUG ChatScreen _loadMessages: loaded from buffer: ${msgs.length}');
      setState(() {
        _messages = msgs..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      print('DEBUG ChatScreen _loadMessages: error loading from buffer: $e');
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
  
  void _handleCallStatusChange(Call call) {
    // Handle call status changes
    if (call.status == CallStatus.connected) {
      // Navigate to call screen when connected
      // This would typically be done through the app's navigation system
    }
    
    // Update UI state if needed
    setState(() {});
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
            Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 1),
              ),
              child: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                radius: 15,
                child: Text(
                  widget.chat.name[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
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
                    _otherOnline ? 'online' : 'offline',
                    style: TextStyle(
                      fontSize: 12,
                      color: _otherOnline ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: _startAudioCall,
          ),
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
                          'No messages\nSend the first message!',
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
                          return MessageBubble(message: message, isMe: isMe);
                        },
                      ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: scheme.outline.withOpacity(0.4)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
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
                    print('DEBUG: Send button pressed');
                    _sendMessage();
                  },
                  icon: const Icon(Icons.send),
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.surfaceVariant,
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
      print('DEBUG ChatScreen _sendMessage: Exit - empty text or already sending');
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final otherUserId = _getOtherUserId();
      final currentUserId = _networkService.userId;
      print('DEBUG ChatScreen _sendMessage: otherUserId=$otherUserId, myUserId=$currentUserId');
      print('DEBUG ChatScreen _sendMessage: Network connected: ${_networkService.isConnected}');
      print('DEBUG ChatScreen _sendMessage: Other user online: ${_networkService.isUserOnline(otherUserId)}');

      final success = await _networkService.sendMessage(
        otherUserId,
        text,
        type: MessageType.text,
      );
      print('DEBUG ChatScreen _sendMessage: Send result: $success');

      if (success) {
        print('DEBUG ChatScreen _sendMessage: Message sent successfully, clearing input');
        _messageController.clear();
        // The message will be added via listener upon receiving confirmation
      } else {
        print('DEBUG ChatScreen _sendMessage: Failed to send message');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message')),
        );
      }
    } catch (e) {
      print('ERROR ChatScreen _sendMessage: Exception: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }
  
  void _startAudioCall() {
    final otherUserId = _getOtherUserId();

    // Show loading indicator
    setState(() {
      // You could add a loading state here
    });

    try {
      // Check if we have a network connection
      if (!_networkService.isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No server connection. Please check your network.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      widget.audioCallService.initiateCall(otherUserId);

      // Navigate to call screen immediately
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AudioCallScreen(audioCallService: widget.audioCallService),
        ),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Calling ${widget.chat.name}...'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start call: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}