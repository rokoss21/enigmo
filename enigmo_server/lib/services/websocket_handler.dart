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


/// WebSocket connections handler
class WebSocketHandler {
  final Logger _logger = Logger();
  final UserManager _userManager;
  final MessageManager _messageManager;
  final AuthService _authService;
  
  WebSocketHandler(this._userManager, this._messageManager) : _authService = AuthService(_userManager);

  /// Creates a WebSocket handler
  Handler get handler => webSocketHandler(_handleWebSocket);

  /// Handles a new WebSocket connection
  void _handleWebSocket(WebSocketChannel webSocket) {
    String? userId;
    
    _logger.info('New WebSocket connection');

    webSocket.stream.listen(
      (data) async {
        try {
          final message = jsonDecode(data as String) as Map<String, dynamic>;
          
          // Update userId if the user authenticated
          if (message['type'] == 'auth') {
            final tempUserId = message['userId'] as String?;
            final user = tempUserId != null ? await _userManager.authenticateUser(tempUserId) : null;
            if (user != null) {
              userId = tempUserId;
              _userManager.connectUser(userId!, webSocket);
              // Ephemeral mode: offline delivery is disabled
            }
          }
          
          await _handleMessage(webSocket, message, userId);
        } catch (e, stackTrace) {
          _logger.error('Message processing error: $e');
          _sendError(webSocket, 'Message processing error: $e');
        }
      },
      onError: (error) {
        _logger.warning('WebSocket error: $error');
        if (userId != null) {
          _userManager.disconnectUser(userId!);
        }
      },
      onDone: () {
        _logger.info('WebSocket connection closed');
        if (userId != null) {
          _userManager.disconnectUser(userId!);
        }
      },
    );
  }

  /// Handles an incoming message
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
          _sendError(webSocket, 'Authentication required');
        }
        break;
        
      case 'get_history':
        if (currentUserId != null) {
          await _handleGetHistory(webSocket, message, currentUserId);
        } else {
          _sendError(webSocket, 'Authentication required');
        }
        break;
        
      case 'mark_read':
        if (currentUserId != null) {
          await _handleMarkRead(webSocket, message, currentUserId);
        } else {
          _sendError(webSocket, 'Authentication required');
        }
        break;
        
      case 'get_users':
        if (currentUserId != null) {
          await _handleGetUsers(webSocket, message, currentUserId);
        } else {
          _sendError(webSocket, 'Authentication required');
        }
        break;
        
      case 'add_to_chat':
        if (currentUserId != null) {
          await _handleAddToChat(webSocket, message, currentUserId);
        } else {
          _sendError(webSocket, 'Authentication required');
        }
        break;
        
      case 'ping':
        _sendResponse(webSocket, 'pong', {'timestamp': DateTime.now().toIso8601String()});
        break;
        
      default:
        _sendError(webSocket, 'Unknown message type: $type');
    }
  }

  /// Handles user registration
  Future<void> _handleRegister(WebSocketChannel webSocket, Map<String, dynamic> message) async {
    try {
      final publicSigningKey = message['publicSigningKey'] as String?;
      final publicEncryptionKey = message['publicEncryptionKey'] as String?;
      final nickname = message['nickname'] as String?;
      
      if (publicSigningKey == null || publicEncryptionKey == null) {
        _sendError(webSocket, 'Missing required fields');
        return;
      }

      // Generate userId based on the public signing key
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
        
        _logger.info('User registered: ${user.id}');
      } else {
        _sendError(webSocket, 'Registration error: could not create user');
      }
    } catch (e) {
      _sendError(webSocket, 'Registration error: $e');
    }
  }

  /// Handles user authentication
  Future<void> _handleAuth(WebSocketChannel webSocket, Map<String, dynamic> message) async {
    try {
      final userId = message['userId'] as String?;
      final signature = message['signature'] as String?;
      final timestamp = message['timestamp'] as String?;
      
      if (userId == null || signature == null || timestamp == null) {
        _sendError(webSocket, 'Missing required fields for authentication');
        return;
      }

      final user = await _userManager.authenticateUser(userId);
      final success = user != null;

      if (success) {
        // Connect the user to WebSocket (register the channel itself)
        _userManager.connectUser(userId, webSocket);
        
        _sendResponse(webSocket, 'auth_success', {
          'userId': userId,
          'success': true,
        });
        
        // Ephemeral mode: offline delivery is disabled
        
        _logger.info('User authenticated: $userId');
      } else {
        _sendError(webSocket, 'Authentication error');
      }
    } catch (e) {
      _sendError(webSocket, 'Authentication error: $e');
    }
  }

  /// Handles sending a message
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
        _sendError(webSocket, 'Missing required fields for sending a message');
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
      
      _logger.info('Message sent: ${sentMessage.id}');
    } catch (e) {
      _sendError(webSocket, 'Message send error: $e');
    }
  }

  /// Handles a message history request
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
        _sendError(webSocket, 'Missing interlocutor ID');
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
      
      _logger.info('Message history sent: $userId <-> $otherUserId');
    } catch (e) {
      _sendError(webSocket, 'Error retrieving history: $e');
    }
  }

  /// Handles marking a message as read
  Future<void> _handleMarkRead(
    WebSocketChannel webSocket,
    Map<String, dynamic> message,
    String userId,
  ) async {
    try {
      final messageId = message['messageId'] as String?;
      
      if (messageId == null) {
        _sendError(webSocket, 'Missing message ID');
        return;
      }

      final success = await _messageManager.markMessageAsRead(messageId, userId);

      _sendResponse(webSocket, 'message_marked_read', {
        'messageId': messageId,
        'success': success,
      });
      
      if (success) {
        _logger.info('Message marked as read: $messageId');
      }
    } catch (e) {
      _sendError(webSocket, 'Error marking message: $e');
    }
  }

  /// Handles a users list request
  Future<void> _handleGetUsers(
    WebSocketChannel webSocket,
    Map<String, dynamic> message,
    String userId,
  ) async {
    try {
      final onlineUsers = _userManager.getOnlineUsers();
      
      final users = onlineUsers
          .where((user) => user.id != userId) // Exclude current user
          .map((user) => user.toJson())
          .toList();
      
      _sendResponse(webSocket, 'users_list', {
        'users': users,
      });
      
      _logger.info('Users list sent: $userId');
    } catch (e) {
      _sendError(webSocket, 'Error retrieving users list: $e');
    }
  }

  /// Sends a response to the client
  void _sendResponse(WebSocketChannel webSocket, String type, Map<String, dynamic> data) {
    final response = {
      'type': type,
      'timestamp': DateTime.now().toIso8601String(),
      ...data,
    };
    
    try {
      webSocket.sink.add(jsonEncode(response));
    } catch (e) {
      _logger.warning('Error sending response: $e');
    }
  }

  /// Handles adding a user to a chat
  Future<void> _handleAddToChat(WebSocketChannel webSocket, Map<String, dynamic> message, String currentUserId) async {
    try {
      final targetUserId = message['target_user_id'] as String?;
      
      if (targetUserId == null) {
        _sendError(webSocket, 'User ID to add to chat not provided');
        return;
      }
      
      if (targetUserId == currentUserId) {
        _sendError(webSocket, 'Cannot add yourself to chat');
        return;
      }
      
      // Check if the target user exists
      final targetUser = _userManager.getUser(targetUserId);
      if (targetUser == null) {
        _sendError(webSocket, 'User not found');
        return;
      }
      
      // Notify the target user about being added to a chat
      if (_userManager.isUserOnline(targetUserId)) {
        await _userManager.sendToUser(targetUserId, {
          'type': 'chat_added',
          'user_id': currentUserId,
          'nickname': _userManager.getUser(currentUserId)?.nickname ?? currentUserId,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
      
      // Send target user's info back to the initiator
      final initiatorInfo = {
        'id': targetUserId,
        'nickname': targetUser.nickname ?? targetUserId,
        'isOnline': _userManager.isUserOnline(targetUserId),
        'lastSeen': targetUser.lastSeen?.toIso8601String() ?? DateTime.now().toIso8601String(),
      };
      
      // Confirm to initiator that the user was added
      _sendResponse(webSocket, 'add_to_chat_success', {
        'target_user': initiatorInfo,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
    } catch (e) {
      print('Error adding user to chat: $e');
      _sendError(webSocket, 'Error adding user to chat');
    }
  }

  /// Sends an error to the client
  void _sendError(WebSocketChannel webSocket, String error) {
    _sendResponse(webSocket, 'error', {'message': error});
  }

  /// Parses message type from string
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
  
  /// Generates a userId based on the public signing key
  String _generateUserIdFromPublicKey(String publicKey) {
    // Use the first 16 characters of the public key hash as userId
    final bytes = utf8.encode(publicKey);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16).toUpperCase();
  }
}