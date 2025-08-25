import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../services/network_service.dart';
import '../services/key_manager.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

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
  String? _activeChatUserId; // user whose chat is currently open
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
        // User went offline — remove chat and clear local data
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

  /// Full session reset: clear local data, new ID, and reconnect
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
          const SnackBar(content: Text('New session created. You received a new ID')),
        );
      } else {
        setState(() {
          _isConnected = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create a new session'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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
    print('INFO ChatListScreen._initializeNetwork: Starting network initialization');
    
    setState(() {
      _isConnecting = true;
    });

    try {
      // Connect to the server
      print('INFO ChatListScreen._initializeNetwork: Connecting to server');
      final connected = await _networkService.connect();
      
      if (!connected) {
        throw Exception('Failed to connect to server');
      }
      
      print('INFO ChatListScreen._initializeNetwork: Connected to server successfully');
      
      // Check if there is a stored userId
      final storedUserId = await KeyManager.getUserId();
      print('INFO ChatListScreen._initializeNetwork: Stored userId: $storedUserId');
      
      bool needsRegistration = storedUserId == null;
      
      if (!needsRegistration) {
        try {
          print('INFO ChatListScreen._initializeNetwork: Attempting authentication with existing userId');
          // Try to authenticate with existing userId
          final authenticated = await _networkService.authenticate();
          if (!authenticated) {
            print('WARNING ChatListScreen._initializeNetwork: Authentication failed, registration required');
            needsRegistration = true;
          } else {
            print('INFO ChatListScreen._initializeNetwork: Authentication successful');
          }
        } catch (e) {
          print('ERROR ChatListScreen._initializeNetwork: Authentication error: $e');
          needsRegistration = true;
        }
      }
      
      if (needsRegistration) {
        print('INFO ChatListScreen._initializeNetwork: Registering new user');
        // If authentication failed, register a new user
        final userId = await _networkService.registerUser(nickname: 'User');
        if (userId != null) {
          print('INFO ChatListScreen._initializeNetwork: User registered: $userId');
          final authSuccess = await _networkService.authenticate();
          if (!authSuccess) {
            throw Exception('Failed to authenticate after registration');
          }
          print('INFO ChatListScreen._initializeNetwork: Authentication after registration successful');
        } else {
          throw Exception('Failed to register user');
        }
      }
      
      // Load chats list
      print('INFO ChatListScreen._initializeNetwork: Loading chats');
      await _loadChats();
      
      // Start periodic users list refresh
      _startPeriodicRefresh();
      
      // Listen for new messages
      _networkService.newMessages.listen((message) {
        print('INFO ChatListScreen: Received new message: ${message.id}');
        _handleNewMessage(message);
      });
      
      // Listen for chats list updates
      _networkService.chats.listen((chats) {
        print('INFO ChatListScreen: Chats list updated: ${chats.length} chats');
        setState(() {
          // Update only if list is not empty or we are clearing the list
          if (chats.isNotEmpty || _chats.isNotEmpty) {
            _chats = chats;
          }
        });
      });
      
      // Listen for connection status
      _networkService.connectionStatus.listen((connected) {
        print('INFO ChatListScreen: Connection status changed: $connected');
        setState(() {
          _isConnected = connected;
          if (!connected) {
            _refreshTimer?.cancel();
          } else {
            // On reconnection, try to re-authenticate
            _handleReconnection();
          }
        });
      });
      
      // Listen for new chat notifications
      _networkService.newChatNotifications.listen((userId) {
        print('INFO ChatListScreen: New chat notification: $userId');
        _handleNewChatNotification({'userId': userId});
      });
      
      // Listen for user status updates
      _networkService.userStatusUpdates.listen((statusData) {
        print('INFO ChatListScreen: User status update: $statusData');
        _handleUserStatusUpdate(statusData);
      });
      
      // Set connection status as active
      setState(() {
        _isConnected = true;
        _currentUserId = _networkService.userId;
      });
      // Initialize online statuses (users_list)
      try {
        await _networkService.getUsers();
      } catch (_) {}
      
      print('INFO ChatListScreen._initializeNetwork: Network initialization finished successfully');
    } catch (e, stackTrace) {
      print('ERROR ChatListScreen._initializeNetwork: Network initialization error: $e');
      print('STACK: $stackTrace');
      
      setState(() {
        _isConnected = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Server connection error: $e'),
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
    print('INFO ChatListScreen._loadChats: Loading chats');
    // Remove automatic loading of all users
    // Now chats will be added only via the add dialog
    setState(() {
      // Keep only existing chats, do not load all users
    });
  }

  /// Handles reconnection
  Future<void> _handleReconnection() async {
    print('INFO ChatListScreen._handleReconnection: Handling reconnection');
    
    if (!_isConnected) {
      print('WARNING ChatListScreen._handleReconnection: No connection, skipping re-authentication');
      return;
    }
    
    try {
      final storedUserId = await KeyManager.getUserId();
      if (storedUserId != null) {
        print('INFO ChatListScreen._handleReconnection: Attempting re-authentication');
        final authenticated = await _networkService.authenticate();
        if (authenticated) {
          print('INFO ChatListScreen._handleReconnection: Re-authentication successful');
          setState(() {
            _currentUserId = _networkService.userId;
          });
          _startPeriodicRefresh();
        } else {
          print('WARNING ChatListScreen._handleReconnection: Re-authentication failed');
        }
      }
    } catch (e) {
      print('ERROR ChatListScreen._handleReconnection: Re-authentication error: $e');
    }
  }

  void _handleNewMessage(Message message) {
    // Update the corresponding chat
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
        
        // Move the chat to the top of the list
        final chat = _chats.removeAt(chatIndex);
        _chats.insert(0, chat);
      }
    });
  }

  /// Starts periodic refresh of the users list
  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected && mounted) {
        _loadChats();
        // Regularly update the users list to fetch online statuses
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _currentUserId != null ? () => _copyUserId() : null,
          child: Text(
            _currentUserId != null ? 'ID: $_currentUserId' : 'Enigmo',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              color: Colors.white,
            ),
          ),
        ),
        backgroundColor: scheme.surfaceVariant,
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          // Connection indicator (green online, red offline)
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isConnected ? Icons.wifi : Icons.wifi_off,
                  color: _isConnected ? Colors.green : scheme.error,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  _isConnected ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: _isConnected ? Colors.green : scheme.error,
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
                  Text('Connecting to server...'),
                ],
              ),
            )
          : _chats.isEmpty
              ? Align(
                  alignment: const Alignment(0, -0.2),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.forum_outlined, size: 72, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(height: 16),
                        const Text(
                          'Welcome to Enigmo',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isConnected ? 'To start chatting, follow a few quick steps' : 'Please connect to the server first... ',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        // Step 1
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Icon(Icons.content_copy, color: Colors.white70),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '1) Copy your ID — tap the ID at the top (AppBar) or use the button below',
                                style: TextStyle(color: Colors.white70, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Step 2
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Icon(Icons.person_add_alt_1, color: Colors.white70),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '2) Connect to ID — tap + in the top-right or use the button below, then paste the user ID',
                                style: TextStyle(color: Colors.white70, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Step 3
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Icon(Icons.notifications_active_outlined, color: Colors.white70),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '3) Notifications — enable/disable them in Settings',
                                style: TextStyle(color: Colors.white70, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Step 4 — Security
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Icon(Icons.shield_outlined, color: Colors.white70),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '4) Security — end-to-end: X25519 key agreement, ChaCha20-Poly1305 AEAD encryption, Ed25519 signatures, SHA-256 hashing',
                                style: TextStyle(color: Colors.white70, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Step 5 — Sessions
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Icon(Icons.restart_alt, color: Colors.white70),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '5) Sessions — when you generate a new ID or exit the app, all sessions are cleared for privacy',
                                style: TextStyle(color: Colors.white70, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Quick actions
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: _currentUserId != null ? _copyUserId : null,
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy my ID'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _isConnected ? _showAddUserDialog : null,
                              icon: const Icon(Icons.person_add),
                              label: const Text('Connect to ID'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                                );
                              },
                              icon: const Icon(Icons.settings),
                              label: const Text('Settings'),
                            ),
                          ],
                        ),
                      ],
                    ),
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
        tooltip: 'New session',
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
    final scheme = Theme.of(context).colorScheme;
    final online = chat.isOnline || _networkService.isUserOnline(chat.id);
    return InkWell(
      onTap: () async {
        print('DEBUG: Navigating to chat with user: ${chat.name} (ID: ${chat.id})');
        setState(() {
          _activeChatUserId = chat.id; // for direct chats, id = peer userId
          // Reset unread counter immediately upon entering the chat
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
        // Returned from chat — reset unread counter
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
                  backgroundColor: scheme.surfaceVariant,
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
                      color: online ? Colors.green : scheme.onSurfaceVariant,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.surface,
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
                              ? Colors.white
                              : Theme.of(context).colorScheme.onSurfaceVariant,
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
                          chat.lastMessage?.content ?? 'No messages',
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
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            chat.unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.black,
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
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }

  /// Copies the user's ID to the clipboard
  void _copyUserId() {
    if (_currentUserId != null) {
      Clipboard.setData(ClipboardData(text: _currentUserId!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ID copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Shows the add user dialog
  void _showAddUserDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: scheme.surfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: const Text(
            'Add user',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 260),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: const Icon(Icons.copy, color: Colors.white),
                  title: const Text('Copy my ID', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    _currentUserId ?? '',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  onTap: () {
                    _copyUserId();
                    Navigator.of(context).pop();
                  },
                ),
                Divider(color: scheme.outline.withOpacity(0.4), height: 1),
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: const Icon(Icons.person_add, color: Colors.white),
                  title: const Text('Add to chat', style: TextStyle(color: Colors.white)),
                  subtitle: Text('Enter user ID', style: TextStyle(color: scheme.onSurfaceVariant)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showAddUserByIdDialog();
                  },
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  /// Shows the dialog to input a user ID
  void _showAddUserByIdDialog() {
    final TextEditingController controller = TextEditingController();
    bool isValid = false;
    String? errorText;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final scheme = Theme.of(context).colorScheme;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            void validate(String v) {
              final val = v.trim();
              setStateDialog(() {
                isValid = val.length == 16;
                errorText = (val.isEmpty || isValid) ? null : 'ID должен содержать 16 HEX символов';
              });
            }

            return AlertDialog(
              backgroundColor: scheme.surfaceVariant,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              title: const Text('Add user by ID', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 16,
                    style: const TextStyle(fontFamily: 'monospace'),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                    ],
                    onChanged: validate,
                    onSubmitted: (_) {
                      final userId = controller.text.trim();
                      if (userId.length == 16) {
                        Navigator.of(context).pop();
                        _addUserToChat(userId);
                      } else {
                        validate(userId);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'User ID',
                      hintText: '16-character HEX ID',
                      errorText: errorText,
                      filled: true,
                      fillColor: scheme.surface,
                      counterText: '',
                      prefixIcon: Icon(Icons.fingerprint, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      suffixIcon: controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                controller.clear();
                                validate('');
                              },
                            ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: scheme.outline.withOpacity(0.4)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                        final text = (data?.text ?? '').trim();
                        if (text.isNotEmpty) {
                          controller.text = text;
                          controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
                          validate(text);
                        }
                      },
                      icon: const Icon(Icons.paste),
                      label: const Text('Paste from clipboard'),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: isValid
                      ? () {
                          final userId = controller.text.trim();
                          Navigator.of(context).pop();
                          _addUserToChat(userId);
                        }
                      : null,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Handles user status updates
  void _handleUserStatusUpdate(Map<String, dynamic> data) {
    final userId = data['userId'] as String?;
    final isOnline = data['isOnline'] as bool? ?? false;
    
    if (userId == null) return;
    
    setState(() {
      // Find the chat with this user and update its status
      final chatIndex = _chats.indexWhere((chat) => 
        chat.participants.contains(userId));
      
      if (chatIndex != -1) {
        _chats[chatIndex] = _chats[chatIndex].copyWith(isOnline: isOnline);
        print('INFO ChatListScreen: Updated user $userId status: ${isOnline ? "online" : "offline"}');
      }
    });
  }

  /// Adds a user to chat by ID
  /// Handles a notification about being added to a chat by another user
  void _handleNewChatNotification(Map<String, dynamic> data) {
    final userId = data['userId'] as String;
    final nickname = data['nickname'] as String?;
    final isInitiator = data['isInitiator'] as bool? ?? false;
    final isOnline = data['isOnline'] as bool? ?? false;
    final lastSeen = data['lastSeen'] as String?;
    
    // Check if a chat with this user already exists
    final existingChatIndex = _chats.indexWhere((chat) =>
      chat.participants.contains(userId));
    
    if (existingChatIndex == -1) {
      // Create a new chat
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
              ? 'User $displayName added to chats'
              : 'User $displayName added you to a chat'),
          backgroundColor: isInitiator ? Colors.green : Colors.blue,
        ),
      );
    } else if (isInitiator) {
      // If this is the initiator and the chat already exists, just navigate to it
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
      // Ensure this is not our own ID
      if (userId == _currentUserId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot add yourself to a chat'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Check if a chat with this user already exists
      final existingChatIndex = _chats.indexWhere((chat) => 
        chat.participants.contains(userId));
      
      if (existingChatIndex != -1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A chat with this user already exists'),
            backgroundColor: Colors.orange,
          ),
        );
        
        // Navigate to the existing chat
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(chat: _chats[existingChatIndex]),
          ),
        );
        return;
      }

      // Send a request to the server to add the user to the chat
      await _networkService.addUserToChat(userId);
      
      // Create a local chat for the initiator
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

      // Add the new chat
      setState(() {
        _chats.insert(0, targetUser);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User $userId added to chats'),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate to the new chat
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(chat: targetUser),
        ),
      );

    } catch (e) {
      print('Error adding user: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}