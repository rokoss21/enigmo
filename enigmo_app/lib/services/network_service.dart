import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/html.dart' if (dart.library.io) 'package:web_socket_channel/io.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';
import '../models/chat.dart';
import 'key_manager.dart';
import 'crypto_engine.dart';
// Import lifecycle service for background message handling
// Note: Using late initialization to avoid circular dependency

/// Service for working with the network and the Bootstrap server
class NetworkService {
  static final NetworkService _instance = NetworkService._internal();

  factory NetworkService() {
    return _instance;
  }

  // Internal helper to send to server (without duplicating local message when flushing the queue)
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

      print('DEBUG _sendToServer: Sending message: $wire');

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
          print('DEBUG _sendToServer: failed to create local message: $e');
        }
      }

      _channel!.sink.add(jsonEncode(wire));
      return true;
    } catch (e) {
      print('DEBUG _sendToServer: Error while sending: $e');
      return false;
    }
  }

  // Ensures we have recipient public keys in cache
  Future<bool> _ensureRecipientKeys(String userId) async {
    if (_publicEncKeys.containsKey(userId) && _publicSignKeys.containsKey(userId)) {
      return true;
    }
    try {
      // Request the users list and wait for response
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
  static const String _defaultServerUrl = 'ws://localhost:8081/ws';
  static const String _serverUrlKey = 'custom_server_url';

  // Save custom server URL to preferences
  static Future<void> saveServerUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_serverUrlKey, url);
      print('NetworkService: Server URL saved: $url');
    } catch (e) {
      print('NetworkService: Error saving server URL: $e');
    }
  }

  // Load custom server URL from preferences
  static Future<String?> loadServerUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(_serverUrlKey);
      if (savedUrl != null && savedUrl.isNotEmpty) {
        print('NetworkService: Loaded saved server URL: $savedUrl');
        return savedUrl;
      }
    } catch (e) {
      print('NetworkService: Error loading server URL: $e');
    }
    return null;
  }
  
  WebSocketChannel? _channel;
  // Single broadcast stream for all subscribers
  Stream<dynamic>? _broadcastStream;
  StreamController<Map<String, dynamic>>? _messageController;
  String? _userId;
  bool _isConnected = false;
  
  // Heartbeat and auto-reconnect
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  DateTime? _lastPongAt;
  Duration _pingInterval = const Duration(seconds: 20);
  Duration _pongTimeout = const Duration(seconds: 10);
  bool _manualDisconnect = false;
  bool _isReconnecting = false;
  int _reconnectAttempt = 0;
  final int _maxReconnectDelaySeconds = 30;
  bool _ephemeralInitDone = false; // perform key cleanup once per app launch
  
  // KeyManager and CryptoEngine are used as static classes
  
  // Streams for various message types
  final StreamController<Message> _newMessageController = StreamController.broadcast();
  final StreamController<List<Message>> _messageHistoryController = StreamController.broadcast();
  final StreamController<List<Chat>> _chatsController = StreamController.broadcast();
  final StreamController<bool> _connectionController = StreamController.broadcast();
  final StreamController<String> _newChatController = StreamController.broadcast();
  final StreamController<List<Map<String, dynamic>>> _usersController = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _userStatusController = StreamController.broadcast();
  // Cache of users' public keys
  final Map<String, String> _publicEncKeys = {}; // userId -> base64 X25519
  final Map<String, String> _publicSignKeys = {}; // userId -> base64 Ed25519
  // Online tracking and local message queue for ephemeral mode
  final Set<String> _onlineUsers = <String>{};
  final Map<String, List<_PendingMessage>> _pendingByReceiver = {};
  // Local in-memory messages per peer (session-lifetime only)
  final Map<String, List<Message>> _inMemoryByPeer = {};
  // Lifecycle service for background message handling (late init to avoid circular dependency)
  dynamic _lifecycleService; // Will be AppLifecycleService when initialized

  // Local structure for deferred messages
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

  // Returns a copy of the latest messages with a specific peer
  List<Message> getRecentMessages(String otherUserId) {
    final list = _inMemoryByPeer[otherUserId];
    if (list == null) return const [];
    return List<Message>.from(list);
  }

  // Clears all local data for a peer (messages/queue/online-flag)
  void clearPeerSession(String otherUserId) {
    try {
      _inMemoryByPeer.remove(otherUserId);
      _pendingByReceiver.remove(otherUserId);
      _onlineUsers.remove(otherUserId);
      print('DEBUG NetworkService.clearPeerSession: cleared data for $otherUserId');
    } catch (e) {
      print('DEBUG NetworkService.clearPeerSession: error: $e');
    }
  }

  // Full reset of the current session: delete keys/ID, clear local caches and reconnect
  Future<bool> resetSession() async {
    try {
      print('🔄 NetworkService.resetSession: Starting session reset');

      // Clear local structures first
      _inMemoryByPeer.clear();
      _pendingByReceiver.clear();
      _onlineUsers.clear();
      _publicEncKeys.clear();
      _publicSignKeys.clear();
      _userId = null;

      // Delete keys and userId in storage
      print('🗑️ NetworkService.resetSession: Clearing stored keys and user data');
      await KeyManager.deleteUserKeys();

      // Disconnect existing connection cleanly
      print('🔌 NetworkService.resetSession: Disconnecting existing connection');
      await disconnect();
      
      // Wait for cleanup to complete
      await Future.delayed(const Duration(milliseconds: 500));

      // Reset ephemeral init flag to allow key clearing on reconnect
      _ephemeralInitDone = false;

      // Establish new connection with ephemeral identity enabled
      print('🔗 NetworkService.resetSession: Establishing new connection');
      final connected = await connect(ephemeralIdentity: true);
      if (!connected) {
        print('❌ NetworkService.resetSession: Connection failed');
        return false;
      }

      // Register new user with fresh identity
      print('📝 NetworkService.resetSession: Registering new user');
      final registeredId = await registerUser(nickname: 'User');
      if (registeredId == null) {
        print('❌ NetworkService.resetSession: Registration failed');
        return false;
      }

      // After registration, we need to authenticate to establish the session
      print('🔐 NetworkService.resetSession: Authenticating after registration...');
      final authSuccess = await authenticate();
      if (!authSuccess) {
        print('❌ NetworkService.resetSession: Authentication failed after registration');
        return false;
      }
      print('✅ NetworkService.resetSession: Authentication successful after registration');

      print('✅ NetworkService.resetSession: Session reset successful with new ID: $registeredId');
      return true;
    } catch (e) {
      print('❌ NetworkService.resetSession: Error during session reset: $e');
      return false;
    }
  }

  // Puts users' keys into local cache
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

        // Also update local online set based on users_list
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
              // If a user just became online — flush deferred messages
              final pending = _pendingByReceiver.remove(id);
              if (pending != null && pending.isNotEmpty) {
                print('DEBUG _cacheUsersKeys: Flushing deferred messages for $id: ${pending.length}');
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
      print('DEBUG _cacheUsersKeys: cached encKeys=${_publicEncKeys.length}, signKeys=${_publicSignKeys.length}');
    } catch (e) {
      print('DEBUG _cacheUsersKeys: key caching error: $e');
    }
  }

  Future<String> _resolveServerUrl() async {
    // First, check for saved custom server URL
    final savedUrl = await loadServerUrl();
    if (savedUrl != null) {
      print('🔗 NetworkService._resolveServerUrl: Using saved server URL: $savedUrl');
      return savedUrl;
    }

    // For web, allow overrides via query parameters for easier testing
    if (kIsWeb) {
      final wsOverride = Uri.base.queryParameters['ws'];
      if (wsOverride != null && wsOverride.isNotEmpty) {
        print('🔗 NetworkService._resolveServerUrl: Using explicit override: $wsOverride');
        return wsOverride;
      }
      // Default for web development
      print('🔗 NetworkService._resolveServerUrl: Using default for web: ws://localhost:8081/ws');
      return 'ws://localhost:8081/ws';
    }

    // For mobile (Android/iOS) and desktop
    // Use 10.0.2.2 for Android emulator to connect to host's localhost
    if (Platform.isAndroid) {
      print('🔗 NetworkService._resolveServerUrl: Using Android emulator host: ws://10.0.2.2:8081/ws');
      return 'ws://10.0.2.2:8081/ws';
    }

    // Default for iOS, macOS, Windows, Linux
    print('🔗 NetworkService._resolveServerUrl: Using default for desktop/iOS: ws://localhost:8081/ws');
    return 'ws://localhost:8081/ws';
  }

  // Get current server URL (for settings screen)
  static Future<String> getCurrentServerUrl() async {
    final savedUrl = await loadServerUrl();
    if (savedUrl != null) {
      return savedUrl;
    }

    if (kIsWeb) {
      return 'ws://localhost:8081/ws';
    }

    if (Platform.isAndroid) {
      return 'ws://10.0.2.2:8081/ws';
    }

    return 'ws://localhost:8081/ws';
  }

  /// Connect to Bootstrap server
  Future<bool> connect({String? serverUrl, bool ephemeralIdentity = false}) async {
    try {
      // Only clear keys if explicitly requested via resetSession()
      // Removed automatic ephemeral clearing that was causing issues
      if (ephemeralIdentity && !_ephemeralInitDone) {
        try {
          print('🔄 NetworkService.connect: Ephemeral mode — clearing keys for new session');
          await KeyManager.deleteUserKeys();
        } catch (e) {
          print('❌ NetworkService.connect: Error clearing keys: $e');
        } finally {
          _ephemeralInitDone = true;
        }
      }
      
      final url = serverUrl ?? await _resolveServerUrl();
      print('🔗 NetworkService.connect: Attempting to connect to server: $url');
      print('📱 NetworkService.connect: Running on ${kIsWeb ? "web" : "mobile/desktop"} platform');
      
      // Disconnect existing connection if any
      if (_channel != null) {
        print('🔄 NetworkService.connect: Closing existing connection');
        await disconnect();
        await Future.delayed(const Duration(milliseconds: 200)); // Give time for cleanup
      }
      
      _manualDisconnect = false;
      
      // Create connection with timeout
      print('⏳ NetworkService.connect: Creating WebSocket connection...');
      _channel = WebSocketChannel.connect(
        Uri.parse(url),
        protocols: ['websocket'], // Explicitly set protocol
      );
      _messageController = StreamController<Map<String, dynamic>>.broadcast();

      // Create and store a broadcast stream so all subscriptions share the same stream
      _broadcastStream = _channel!.stream.asBroadcastStream();

      // Test connection with a simple ping first
      print('🏓 NetworkService.connect: Testing connection...');
      
      // Send a ping to verify connection works
      try {
        _channel!.sink.add('{"type":"ping","timestamp":"${DateTime.now().toIso8601String()}"}');
      } catch (e) {
        print('⚠️ NetworkService.connect: Failed to send initial ping: $e');
      }
      
      // Listen to incoming messages with the main handler
      _broadcastStream!.listen(
        (data) {
           print('📨 NetworkService: Received message from server: $data');
           try {
             _handleServerMessage(data as String);
           } catch (e) {
             print('❌ NetworkService: Error handling incoming message: $e');
             print('❌ Raw data that caused error: $data');
           }
         },
        onError: (error) {
          print('❌ NetworkService: WebSocket error: $error');
          _handleDisconnection();
          _scheduleReconnect();
        },
        onDone: () {
          print('🔚 NetworkService: WebSocket connection closed by server');
          _handleDisconnection();
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
      
      // Wait for connection to establish and receive pong
      print('⏱️ NetworkService.connect: Waiting for connection to stabilize...');
      await Future.delayed(const Duration(milliseconds: 1000)); // Increased timeout for mobile
      
      // Verify connection is working by checking if channel is still active
      if (_channel?.closeCode != null) {
        print('❌ NetworkService.connect: Connection failed immediately (close code: ${_channel?.closeCode})');
        return false;
      }
      
      // Additional verification - try to send a test message
      try {
        if (_channel?.sink != null) {
          print('✅ NetworkService.connect: WebSocket sink is available and ready');
        }
      } catch (e) {
        print('❌ NetworkService.connect: WebSocket sink test failed: $e');
        return false;
      }
      
      _isConnected = true;
      _connectionController.add(true);
      _reconnectAttempt = 0;
      _isReconnecting = false;
      _startHeartbeat();
      
      print('✅ NetworkService: Connected to server successfully!');
      print('🌐 Server URL: $url');
      print('🔗 Connection status: $_isConnected');
      return true;
    } catch (e) {
      print('❌ NetworkService: Failed to connect to server!');
      print('🔗 Error details: $e');
      print('🌐 Server URL: $_defaultServerUrl');
      print('📱 Platform: ${kIsWeb ? "web" : "mobile/desktop"}');

      // Check for common connection issues
      if (e.toString().contains('Connection refused')) {
        print('🚫 Connection refused - check if server is running on port 8081');
      } else if (e.toString().contains('Network is unreachable')) {
        print('🚫 Network unreachable - check internet connection');
      } else if (e.toString().contains('SSL')) {
        print('🚫 SSL error - server certificate issue');
      } else if (e.toString().contains('timeout')) {
        print('🚫 Connection timeout - server may be slow to respond');
      }

      _isConnected = false;
      _connectionController.add(false);
      _scheduleReconnect();
      return false;
    }
  }

  /// Register a new user
  Future<String?> registerUser({String? nickname}) async {
    print('🔐 NetworkService.registerUser: Starting user registration process...');

    if (!_isConnected || _channel == null) {
      print('🔗 NetworkService.registerUser: No connection, attempting to connect first');
      final connected = await connect();
      if (!connected) {
        print('❌ NetworkService.registerUser: Failed to establish connection');
        throw Exception('No connection to server');
      }
      // Give more time for connection to stabilize
      await Future.delayed(const Duration(milliseconds: 1000));
      print('✅ NetworkService.registerUser: Connection established successfully');
    }

    try {
      print('🔑 NetworkService.registerUser: Generating user keys...');
      
      // Always generate fresh keys for new registration
      await KeyManager.generateUserKeys();
      final keys = await KeyManager.loadUserKeys();

      if (keys == null) {
        print('❌ NetworkService.registerUser: Failed to load keys');
        throw Exception('Failed to load keys');
      }
      print('✅ NetworkService.registerUser: Keys generated and loaded successfully');

      final signingPublicKey = await keys.signingKeyPair.extractPublicKey();
      final encryptionPublicKey = await keys.encryptionKeyPair.extractPublicKey();

      final signingKeyStr = await KeyManager.publicKeyToString(signingPublicKey);
      final encryptionKeyStr = await KeyManager.publicKeyToString(encryptionPublicKey);

      print('📝 NetworkService.registerUser: Preparing registration message...');
      final message = {
        'type': 'register',
        'publicSigningKey': signingKeyStr,
        'publicEncryptionKey': encryptionKeyStr,
        'nickname': nickname ?? 'User',
        'timestamp': DateTime.now().toIso8601String(),
      };

      print('📤 NetworkService.registerUser: Sending registration to server...');
      _sendMessage(message);

      print('⏳ NetworkService.registerUser: Waiting for server response (15s timeout)...');
      // Wait for server response with longer timeout
      final response = await _waitForResponse('register_success', timeout: const Duration(seconds: 15));
      
      if (response != null) {
        _userId = response['userId'] as String?;
        print('✅ NetworkService.registerUser: Registration successful! UserId: $_userId');
        
        if (_userId != null) {
          // Save userId from server response in KeyManager
          await KeyManager.setUserId(_userId!);
          print('💾 NetworkService.registerUser: userId saved in KeyManager: $_userId');
          print('🎉 NetworkService.registerUser: User registration completed successfully');
          return _userId;
        }
      }
      
      print('❌ NetworkService.registerUser: Registration failed - no valid response');
      return null;

    } catch (e) {
      print('❌ NetworkService.registerUser: Registration error: $e');
      if (e.toString().contains('Server error')) {
        print('🔍 NetworkService.registerUser: Server rejected registration: ${e.toString()}');
      }
      return null;
    }
  }

  /// Authenticate the user
  Future<bool> authenticate() async {
    if (!_isConnected || _channel == null) {
      print('🔗 NetworkService.authenticate: No connection, attempting to connect first');
      final connected = await connect();
      if (!connected) {
        print('❌ NetworkService.authenticate: Connection failed');
        throw Exception('No connection to server');
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    try {
      var storedUserId = await KeyManager.getUserId();
      print('🔐 NetworkService.authenticate: Attempting authentication with userId: $storedUserId');
      
      if (storedUserId == null) {
        print('❌ NetworkService.authenticate: No stored userId, authentication not possible');
        return false;
      }
      
      final keys = await KeyManager.loadUserKeys();
      if (keys == null) {
        print('❌ NetworkService.authenticate: No user keys found');
        return false;
      }

      _userId = storedUserId;
      
      final timestamp = DateTime.now().toIso8601String();
      final signature = await CryptoEngine.signData(timestamp);

      final message = {
        'type': 'auth',
        'userId': _userId,
        'signature': signature,
        'timestamp': timestamp,
      };

      print('📤 NetworkService.authenticate: Sending auth message to server');
      _sendMessage(message);
      
      // Wait for server response with timeout
      print('⏳ NetworkService.authenticate: Waiting for server response...');
      final response = await _waitForResponse('auth_success', timeout: const Duration(seconds: 10));
      
      if (response != null && response['success'] == true) {
        print('✅ NetworkService.authenticate: Authentication successful');
        print('🔗 Connection state: _isConnected=$_isConnected, _userId=$_userId');
        return true;
      } else {
        print('❌ NetworkService.authenticate: Server rejected authentication');
        // Keep userId but mark auth as failed - user may need to re-register
        return false;
      }
    } catch (e) {
      print('❌ NetworkService.authenticate: Authentication error: $e');
      return false;
    }
  }

  /// Send a message
  Future<bool> sendMessage(String receiverId, String content, {MessageType type = MessageType.text}) async {
    print('DEBUG NetworkService.sendMessage: receiverId=$receiverId, content="$content", type=$type');
    
    if (!_isConnected || _userId == null) {
      print('DEBUG NetworkService.sendMessage: Not connected or missing userId');
      return false;
    }

    try {
      final nowTs = DateTime.now();
      final isReceiverOnline = _onlineUsers.contains(receiverId);

      // Always show locally as sent/queued
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
        print('DEBUG NetworkService.sendMessage: failed to create local message: $e');
      }

      if (!isReceiverOnline) {
        print('DEBUG NetworkService.sendMessage: Receiver offline — queuing locally');
        final list = _pendingByReceiver.putIfAbsent(receiverId, () => []);
        list.add(_pm(receiverId, content, type, nowTs));
        return true; // queued locally
      }

      // Receiver is online — send immediately to the server
      return await _sendToServer(receiverId, content, type, timestamp: nowTs, emitLocal: false);
    } catch (e) {
      print('DEBUG NetworkService.sendMessage: Error while sending: $e');
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
      print('DEBUG NetworkService.getMessageHistory: Sent message history request');
      
      // Wait for server response - fixed response type
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
            print('DEBUG getMessageHistory: error processing a history message: $e');
          }
        }
        print('DEBUG NetworkService.getMessageHistory: Received ${messages.length} messages');
        return messages;
      }
      
      print('DEBUG NetworkService.getMessageHistory: Empty response or error');
      return [];
    } catch (e) {
      print('DEBUG NetworkService.getMessageHistory: Error: $e');
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
      print('Error marking as read: $e');
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
      print('Error getting users list: $e');
    }
  }

  void _listenToMessages() {
    _channel!.stream.listen(
      (data) {
        print('DEBUG NetworkService._listenToMessages: Data received: $data');
        _handleServerMessage(data);
      },
      onError: (error) {
        print('WebSocket error: $error');
        _handleDisconnection();
      },
      onDone: () {
        print('WebSocket connection closed');
        _handleDisconnection();
      },
    );
  }

  void _handleServerMessage(String data) {
    try {
      final jsonData = jsonDecode(data);
      print('DEBUG NetworkService._handleServerMessage: Parsed JSON: $jsonData');

      final type = jsonData['type'];
      print('DEBUG NetworkService._handleServerMessage: Message type: $type');

      switch (type) {
        case 'ping':
          // Respond to ping with pong
          try {
            _channel?.sink.add('{"type":"pong","timestamp":"${DateTime.now().toIso8601String()}"}');
            print('🏓 NetworkService: Responded to ping with pong');
          } catch (e) {
            print('❌ NetworkService: Failed to send pong: $e');
          }
          break;
        case 'pong':
          print('🏓 NetworkService: Received pong from server');
          _lastPongAt = DateTime.now();
          break;
        case 'new_message':
          print('DEBUG NetworkService: Received new_message');
          // Server sends { type: 'new_message', message: {...} }
          final payload = (jsonData['message'] as Map<String, dynamic>?) ?? (jsonData['data'] as Map<String, dynamic>?) ?? jsonData;
          print('DEBUG NetworkService: new_message payload: $payload');
          _handleNewMessageAsync(payload);
          break;
        case 'offline_message':
          // Ephemeral mode: ignore offline delivery
          print('DEBUG NetworkService: offline_message ignored (ephemeral mode)');
          break;
        case 'message':
          // Ephemeral mode: ignore offline delivery
          print('DEBUG NetworkService: message (offline delivery) ignored (ephemeral mode)');
          break;
        case 'message_sent':
          print('DEBUG NetworkService: Received message_sent');
          // Add our own sent message to the stream so it appears in the UI
          try {
            final payload = (jsonData['message'] as Map<String, dynamic>?)
                ?? (jsonData['data'] as Map<String, dynamic>?)
                ?? jsonData;
            // If this is an ack for OUR message, skip to avoid showing encrypted JSON
            final senderId = payload['senderId'] as String?;
            if (senderId != null && senderId == _userId) {
              print('DEBUG NetworkService: message_sent from ourselves — skipping display');
              break;
            }
            _handleNewMessageAsync(payload);
          } catch (e) {
            print('DEBUG NetworkService: Error handling message_sent: $e');
          }
          break;
        case 'message_read':
          print('DEBUG NetworkService: Received message_read');
          break;
        case 'chat_added':
          print('DEBUG NetworkService: Received chat_added');
          final userId = jsonData['user_id'] as String?;
          final nickname = jsonData['nickname'] as String?;
          if (userId != null) {
            // Send the full notification data to match what ChatListScreen expects
            final notificationData = {
              'userId': userId,
              'nickname': nickname,
              'isInitiator': false, // This is the recipient, not the initiator
              'isOnline': true, // Assume online since they just connected
              'lastSeen': DateTime.now().toIso8601String(),
            };
            _newChatController.add(userId);
            print('DEBUG NetworkService: Sent a new chat notification for $userId');
          }
          break;
        case 'call_offer':
          print('DEBUG NetworkService: Received call_offer');
          print('DEBUG NetworkService: call_offer data: $jsonData');
          _handleCallOffer(jsonData);
          break;
        case 'call_answer':
          print('DEBUG NetworkService: Received call_answer');
          print('DEBUG NetworkService: call_answer data: $jsonData');
          _handleCallAnswer(jsonData);
          break;
        case 'call_candidate':
          print('DEBUG NetworkService: Received call_candidate');
          print('DEBUG NetworkService: call_candidate data: $jsonData');
          _handleCallCandidate(jsonData);
          break;
        case 'call_end':
          print('DEBUG NetworkService: Received call_end');
          print('DEBUG NetworkService: call_end data: $jsonData');
          _handleCallEnd(jsonData);
          break;
        case 'add_to_chat_success':
          print('DEBUG NetworkService: Received add_to_chat_success');
          break;
        case 'users_list':
          print('DEBUG NetworkService: Received users_list');
          final users = (jsonData['users'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _cacheUsersKeys(users);
          // Update local list of online users
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
            // Push status so UI updates immediately
            _userStatusController.add({'userId': id, 'isOnline': isOnline});
          }
          _usersController.add(users);
          break;
        case 'user_status_update':
          print('DEBUG NetworkService: Received user_status_update');
          _handleUserStatusUpdate(jsonData);
          break;
        case 'pong':
          break;
        case 'auth_success':
          print('DEBUG NetworkService: Received auth_success');
          // Authentication successful - server has established our session
          break;
        case 'error':
          print('Server error: ${jsonData['message']}');
          break;
      }
    } catch (e) {
      print('Error processing message: $e');
    }
  }

  // Compatibility: synchronous wrapper
  void _handleNewMessage(Map<String, dynamic> data) {
    _handleNewMessageAsync(data);
  }

  // Async handling: try to decrypt, then push to stream
  Future<void> _handleNewMessageAsync(Map<String, dynamic> data) async {
    try {
      final Map<String, dynamic> msgJson = Map<String, dynamic>.from(data);

      // Try to decrypt if there is encryptedContent
      final decrypted = await _tryDecryptMessage(msgJson);
      if (decrypted != null) {
        msgJson['content'] = decrypted;
        msgJson['isEncrypted'] = true;
      } else {
        // If this is our own message and there's no decryption — don't show encrypted JSON
        final sid = msgJson['senderId'];
        final hasEnc = msgJson['encryptedContent'] != null;
        if (sid != null && sid == _userId && hasEnc) {
          print('DEBUG _handleNewMessageAsync: own echoed message without decryption, skip to avoid showing encrypted JSON');
          return;
        }
        // Fallback: if encryptedContent is a plain string (not JSON), treat it as plaintext
        final encField = msgJson['encryptedContent'];
        if (encField is String) {
          try {
            // If it's not JSON — exception will be thrown, meaning it's plain text
            jsonDecode(encField);
          } catch (_) {
            msgJson['content'] = encField;
            msgJson['isEncrypted'] = false;
            print('DEBUG _handleNewMessageAsync: plaintext fallback from encryptedContent string');
          }
        }
      }

      final message = Message.fromJson(msgJson);
      print('DEBUG NetworkService._handleNewMessageAsync: Created message: ${message.id}');
      _storeInMemory(message);
      _newMessageController.add(message);
      
      // Trigger background notification if lifecycle service is available
      if (_lifecycleService != null && _lifecycleService.isInBackground) {
        final messageData = {
          'content': message.content,
          'senderName': 'User ${message.senderId}', // TODO: Get actual sender name from users cache
          'senderId': message.senderId,
          'chatId': message.senderId, // Use senderId as chatId for now
          'timestamp': message.timestamp.toIso8601String(),
        };
        _lifecycleService.handleBackgroundMessage(messageData);
      }
    } catch (e) {
      print('Error handling new message: $e');
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
      // We can limit the size in the future (e.g., to 200 messages)
    } catch (e) {
      print('DEBUG _storeInMemory: error: $e');
    }
  }

  // Returns plaintext or null if decryption failed/not required
  Future<String?> _tryDecryptMessage(Map<String, dynamic> msgJson) async {
    try {
      final encField = msgJson['encryptedContent'];
      if (encField == null) return null;

      // encryptedContent can be a plain string or JSON string of EncryptedMessage
      EncryptedMessage? enc;
      if (encField is String) {
        try {
          final parsed = jsonDecode(encField);
          if (parsed is Map<String, dynamic>) {
            enc = EncryptedMessage.fromJson(parsed);
          }
        } catch (_) {
          // not JSON — likely plaintext
          return null;
        }
      } else if (encField is Map<String, dynamic>) {
        enc = EncryptedMessage.fromJson(encField);
      }

      if (enc == null) return null;

      final senderId = msgJson['senderId'] as String?;
      if (senderId == null) return null;

      // Sender's public keys are required
      String? encKeyB64 = _publicEncKeys[senderId];
      String? signKeyB64 = _publicSignKeys[senderId];
      if (encKeyB64 == null || signKeyB64 == null) {
        // if the message is our own — take public keys from KeyManager
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
        // otherwise try to fetch the users list
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
      print('DEBUG _tryDecryptMessage: failed to decrypt: $e');
      return null;
    }
  }

  void _handleUserStatusUpdate(Map<String, dynamic> data) {
    try {
      print('DEBUG NetworkService._handleUserStatusUpdate: User status update: $data');
      // Normalize keys: allow user_id/online and string booleans
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
        // Update local online state
        if (isOnline) {
          _onlineUsers.add(uid);
          // Try to send deferred messages to this user
          final pending = _pendingByReceiver.remove(uid);
          if (pending != null && pending.isNotEmpty) {
            print('DEBUG NetworkService: Flushing deferred messages for $uid: ${pending.length}');
            // Send sequentially, without duplicating local messages
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
      print('Error handling user status update: $e');
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

  Future<void> disconnect() async {
    print('🔌 NetworkService.disconnect: Disconnecting from server');
    _manualDisconnect = true; // Mark as manual disconnect to prevent auto-reconnect
    
    // Stop all timers
    _stopHeartbeat();
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    
    // Close WebSocket connection gracefully
    if (_channel != null) {
      try {
        await _channel!.sink.close();
      } catch (e) {
        print('⚠️ NetworkService.disconnect: Error closing WebSocket: $e');
      }
      _channel = null;
    }
    
    // Clean up controllers and streams
    if (_messageController != null && !_messageController!.isClosed) {
      await _messageController!.close();
      _messageController = null;
    }
    
    _broadcastStream = null;
    _isConnected = false;
    _connectionController.add(false);
    
    print('✅ NetworkService.disconnect: Disconnection completed');
  }

  void dispose() {
    // Use the non-async version for dispose to avoid issues
    _manualDisconnect = true;
    _stopHeartbeat();
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _messageController?.close();
    _messageController = null;
    _broadcastStream = null;
    _isConnected = false;
    
    _newMessageController.close();
    _chatsController.close();
    _usersController.close();
    _connectionController.close();
    _userStatusController.close();
    _newChatController.close();
  }

  // Check the current user's online status using the local set
  bool isUserOnline(String userId) {
    return _onlineUsers.contains(userId);
  }

  void _sendMessage(Map<String, dynamic> message) {
    if (_channel != null) {
      final jsonMessage = jsonEncode(message);
      print('DEBUG: Sending message to server: $jsonMessage');
      _channel!.sink.add(jsonMessage);
    } else {
      print('DEBUG: Attempted to send message, but channel is not connected');
    }
  }

  Future<Map<String, dynamic>?> _waitForResponse(String expectedType, {Duration timeout = const Duration(seconds: 10)}) async {
    print('⏳ NetworkService._waitForResponse: Waiting for response type: $expectedType (timeout: ${timeout.inSeconds}s)');

    try {
      final completer = Completer<Map<String, dynamic>>();
      late StreamSubscription subscription;

      // Listen via unified _broadcastStream to avoid duplicate subscriptions
      final bs = _broadcastStream;
      if (bs == null) {
        print('❌ NetworkService._waitForResponse: Broadcast stream not initialized');
        throw StateError('Broadcast stream not initialized');
      }

      print('👂 NetworkService._waitForResponse: Listening for server response...');
      subscription = bs.listen(
        (data) {
          try {
            print('📨 NetworkService._waitForResponse: Received data: $data');
            final message = jsonDecode(data);
            print('📨 NetworkService._waitForResponse: Parsed message type: ${message['type']}');

            if (message['type'] == expectedType) {
              print('✅ NetworkService._waitForResponse: Expected response received!');
              subscription.cancel();
              if (!completer.isCompleted) {
                completer.complete(message);
              }
            } else if (message['type'] == 'error') {
              print('❌ NetworkService._waitForResponse: Server error received: ${message['message']}');
              subscription.cancel();
              if (!completer.isCompleted) {
                completer.completeError(Exception('Server error: ${message['message']}'));
              }
            } else {
              print('⏭️ NetworkService._waitForResponse: Ignoring message type: ${message['type']}');
            }
          } catch (e) {
            print('❌ NetworkService._waitForResponse: Error parsing response: $e');
            print('❌ NetworkService._waitForResponse: Raw data: $data');
          }
        },
        onError: (error) {
          print('❌ NetworkService._waitForResponse: Stream error: $error');
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
        onDone: () {
          print('🔚 NetworkService._waitForResponse: Stream closed');
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        },
      );

      final result = await completer.future.timeout(timeout);
      print('✅ NetworkService._waitForResponse: Response received successfully');
      return result;
    } catch (e) {
      print('❌ NetworkService._waitForResponse: Error waiting for response $expectedType: $e');
      return null;
    }
  }
  
  /// Add a user to chat
  Future<bool> addUserToChat(String targetUserId) async {
    if (!_isConnected || _userId == null) {
      print('DEBUG NetworkService.addUserToChat: Not connected or missing userId');
      return false;
    }

    try {
      final message = {
        'type': 'add_to_chat',
        'target_user_id': targetUserId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      print('DEBUG NetworkService.addUserToChat: Sending request: $message');
      _channel!.sink.add(jsonEncode(message));
      
      // Wait for server response
      final response = await _waitForResponse('add_to_chat_success');
      if (response != null) {
        print('DEBUG NetworkService.addUserToChat: User added to chat');
        return true;
      }
      
      print('DEBUG NetworkService.addUserToChat: Error while adding');
      return false;
    } catch (e) {
      print('DEBUG NetworkService.addUserToChat: Error: $e');
      return false;
    }
  }

  // =============================================================================
  // LIFECYCLE AND SESSION PERSISTENCE METHODS
  // =============================================================================

  /// Send keepalive ping to maintain connection during background operation
  Future<void> sendKeepalivePing() async {
    if (!_isConnected || _channel == null) {
      print('DEBUG NetworkService.sendKeepalivePing: Not connected, skipping keepalive');
      return;
    }

    try {
      final message = {
        'type': 'keepalive',
        'userId': _userId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      print('DEBUG NetworkService.sendKeepalivePing: Sending keepalive ping');
      _channel!.sink.add(jsonEncode(message));
    } catch (e) {
      print('DEBUG NetworkService.sendKeepalivePing: Error sending keepalive: $e');
    }
  }

  /// Set user status (active/inactive) to notify server of user activity state
  Future<void> setUserStatus({required bool isActive}) async {
    if (!_isConnected || _channel == null || _userId == null) {
      print('DEBUG NetworkService.setUserStatus: Not connected or missing userId, skipping status update');
      return;
    }

    try {
      final message = {
        'type': 'user_status',
        'userId': _userId,
        'isActive': isActive,
        'status': isActive ? 'active' : 'away',
        'timestamp': DateTime.now().toIso8601String(),
      };

      print('DEBUG NetworkService.setUserStatus: Setting user status to ${isActive ? "active" : "away"}');
      _channel!.sink.add(jsonEncode(message));
    } catch (e) {
      print('DEBUG NetworkService.setUserStatus: Error setting user status: $e');
    }
  }

  /// Force reconnection (for recovery after background periods)
  Future<bool> reconnect() async {
    print('DEBUG NetworkService.reconnect: Attempting forced reconnection');
    
    // Reset manual disconnect flag to allow reconnection
    _manualDisconnect = false;
    
    try {
      // Disconnect cleanly first
      if (_isConnected) {
        print('DEBUG NetworkService.reconnect: Disconnecting existing connection');
        disconnect();
        // Wait a moment for clean disconnection
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // Attempt to reconnect
      final success = await connect();
      
      if (success && _userId != null) {
        // Re-authenticate after reconnection
        print('DEBUG NetworkService.reconnect: Re-authenticating after reconnection');
        final authSuccess = await authenticate();
        if (authSuccess) {
          print('DEBUG NetworkService.reconnect: Reconnection and re-authentication successful');
          return true;
        } else {
          print('DEBUG NetworkService.reconnect: Re-authentication failed after reconnection');
          return false;
        }
      }
      
      print('DEBUG NetworkService.reconnect: Reconnection failed');
      return false;
    } catch (e) {
      print('DEBUG NetworkService.reconnect: Error during reconnection: $e');
      return false;
    }
  }

  /// Get current connection state
  // bool get isConnected => _isConnected; // Duplicate removed - already defined above
  
  /// Get current user ID
  String? get currentUserId => _userId;
  
  /// Check if currently reconnecting
  bool get isReconnecting => _isReconnecting;
  
  /// Disable automatic reconnection (for manual disconnect)
  void setManualDisconnect(bool manual) {
    _manualDisconnect = manual;
    print('DEBUG NetworkService.setManualDisconnect: Manual disconnect set to $manual');
  }

  /// Set lifecycle service for background message handling (to avoid circular import)
  void setLifecycleService(dynamic lifecycleService) {
    _lifecycleService = lifecycleService;
    print('DEBUG NetworkService: Lifecycle service integrated for background notifications');
  }

  /// Send WebRTC signaling message
  void send(String type, Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) {
      print('NetworkService.send: Not connected');
      return;
    }

    final message = {
      'type': type,
      ...data,
      'timestamp': DateTime.now().toIso8601String(),
    };

    _channel!.sink.add(jsonEncode(message));
  }

  // Map to store message handlers
  final Map<String, Function(Map<String, dynamic>)> _messageHandlers = {};

  /// Register message handler for specific message types
  void onMessage(String messageType, Function(Map<String, dynamic>) handler) {
    _messageHandlers[messageType] = handler;
    print('NetworkService.onMessage: Registered handler for $messageType');
  }

  /// Handle WebRTC call offer
  void _handleCallOffer(Map<String, dynamic> data) {
    final handler = _messageHandlers['call_offer'];
    if (handler != null) {
      print('DEBUG NetworkService._handleCallOffer: Calling handler with data: $data');
      handler(data);
    } else {
      print('DEBUG NetworkService._handleCallOffer: No handler registered for call_offer');
    }
  }

  /// Handle WebRTC call answer
  void _handleCallAnswer(Map<String, dynamic> data) {
    final handler = _messageHandlers['call_answer'];
    if (handler != null) {
      print('DEBUG NetworkService._handleCallAnswer: Calling handler with data: $data');
      handler(data);
    } else {
      print('DEBUG NetworkService._handleCallAnswer: No handler registered for call_answer');
    }
  }

  /// Handle WebRTC ICE candidate
  void _handleCallCandidate(Map<String, dynamic> data) {
    final handler = _messageHandlers['call_candidate'];
    if (handler != null) {
      print('DEBUG NetworkService._handleCallCandidate: Calling handler with data: $data');
      handler(data);
    } else {
      print('DEBUG NetworkService._handleCallCandidate: No handler registered for call_candidate');
    }
  }

  /// Handle WebRTC call end
  void _handleCallEnd(Map<String, dynamic> data) {
    final handler = _messageHandlers['call_end'];
    if (handler != null) {
      print('DEBUG NetworkService._handleCallEnd: Calling handler with data: $data');
      handler(data);
    } else {
      print('DEBUG NetworkService._handleCallEnd: No handler registered for call_end');
    }
  }

  /// Encrypt data using CryptoEngine
  Future<String> encrypt(String data) async {
    return await CryptoEngine.encrypt(data);
  }

  /// Decrypt data using CryptoEngine
  Future<String> decrypt(String encryptedData) async {
    return await CryptoEngine.decrypt(encryptedData);
  }
}

// Private model for local message queue (Option B: local outbox)
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