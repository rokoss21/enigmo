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


/// Call state model
class CallState {
  final String id;
  final String callerId;
  final String calleeId;
  CallStatus status;
  final DateTime startTime;
  DateTime? endTime;

  CallState({
    required this.id,
    required this.callerId,
    required this.calleeId,
    required this.status,
    required this.startTime,
    this.endTime,
  });
}

enum CallStatus {
  initiated,
  connected,
  ended,
}

/// WebSocket connections handler
class WebSocketHandler {
  final Logger _logger = Logger();
  final UserManager _userManager;
  final MessageManager _messageManager;
  final AuthService _authService;

  // In-memory storage for active calls
  final Map<String, CallState> _activeCalls = {};

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
          
          // Update userId when authentication succeeds
          if (message['type'] == 'auth') {
            final authResult = await _handleAuthAndGetUserId(webSocket, message);
            if (authResult != null) {
              userId = authResult;
            }
          } else {
            await _handleMessage(webSocket, message, userId);
          }
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
        
      case 'call_initiate':
        if (currentUserId != null) {
          await _handleCallInitiate(webSocket, message, currentUserId);
        } else {
          _sendError(webSocket, 'Authentication required');
        }
        break;

      case 'call_accept':
        if (currentUserId != null) {
          await _handleCallAccept(webSocket, message, currentUserId);
        } else {
          _sendError(webSocket, 'Authentication required');
        }
        break;

      case 'call_candidate':
        if (currentUserId != null) {
          await _handleCallCandidate(webSocket, message, currentUserId);
        } else {
          _sendError(webSocket, 'Authentication required');
        }
        break;

      case 'call_end':
        if (currentUserId != null) {
          await _handleCallEnd(webSocket, message, currentUserId);
        } else {
          _sendError(webSocket, 'Authentication required');
        }
        break;

      case 'call_restart':
        if (currentUserId != null) {
          await _handleCallRestart(webSocket, message, currentUserId);
        } else {
          _sendError(webSocket, 'Authentication required');
        }
        break;

      case 'call_restart_answer':
        if (currentUserId != null) {
          await _handleCallRestartAnswer(webSocket, message, currentUserId);
        } else {
          _sendError(webSocket, 'Authentication required');
        }
        break;

      case 'ping':
        _sendResponse(webSocket, 'pong', {'timestamp': DateTime.now().toIso8601String()});
        break;

      case 'keepalive':
        // Respond to keepalive ping - no response needed, just log
        _logger.info('Keepalive ping received from user: $currentUserId');
        break;

      case 'user_status':
        // Handle user status updates - acknowledge but don't broadcast
        _logger.info('User status update received from user: $currentUserId');
        break;

      default:
        _sendError(webSocket, 'Unknown message type: $type');
    }
  }

  /// Handles user registration
  Future<void> _handleRegister(WebSocketChannel webSocket, Map<String, dynamic> message) async {
    try {
      _logger.info('🔐 Starting user registration process...');

      final publicSigningKey = message['publicSigningKey'] as String?;
      final publicEncryptionKey = message['publicEncryptionKey'] as String?;
      final nickname = message['nickname'] as String?;

      _logger.info('📝 Registration data: signingKey=${publicSigningKey?.substring(0, 20)}..., encryptionKey=${publicEncryptionKey?.substring(0, 20)}..., nickname=$nickname');

      if (publicSigningKey == null || publicEncryptionKey == null) {
        _logger.warning('❌ Missing required fields for registration');
        _sendError(webSocket, 'Missing required fields');
        return;
      }

      // Generate userId based on the public signing key
      final userId = _generateUserIdFromPublicKey(publicSigningKey);
      _logger.info('🔑 Generated userId: $userId');

      _logger.info('👤 Registering user with UserManager...');
      final user = await _userManager.registerUser(
        id: userId,
        publicSigningKey: publicSigningKey,
        publicEncryptionKey: publicEncryptionKey,
        nickname: nickname,
      );

      if (user != null) {
        _logger.info('✅ User registered successfully: ${user.id}');
        _sendResponse(webSocket, 'register_success', {
          'userId': user.id,
          'user': user.toJson(),
        });

        _logger.info('📤 Registration success response sent');
      } else {
        _logger.error('❌ Registration failed: UserManager returned null');
        _sendError(webSocket, 'Registration error: could not create user');
      }
    } catch (e) {
      _logger.error('❌ Registration exception: $e');
      _logger.error('🔍 Exception details: ${e.toString()}');
      _sendError(webSocket, 'Registration error: $e');
    }
  }

  /// Handles user authentication and returns userId if successful
  Future<String?> _handleAuthAndGetUserId(WebSocketChannel webSocket, Map<String, dynamic> message) async {
    try {
      final userId = message['userId'] as String?;
      final signature = message['signature'] as String?;
      final timestamp = message['timestamp'] as String?;
      
      if (userId == null || signature == null || timestamp == null) {
        _sendError(webSocket, 'Missing required fields for authentication');
        return null;
      }
      
      // CRITICAL: Validate input parameters
      if (userId.isEmpty || signature.isEmpty || timestamp.isEmpty) {
        _sendError(webSocket, 'Empty authentication parameters');
        return null;
      }
      
      // CRITICAL: Verify signature before authenticating
      final authSuccess = await _authService.authenticateUser(userId, signature, timestamp);
      
      if (authSuccess) {
        // Connect the user to WebSocket (register the channel itself)
        _userManager.connectUser(userId, webSocket);
        
        _sendResponse(webSocket, 'auth_success', {
          'userId': userId,
          'success': true,
        });
        
        _logger.info('User authenticated: $userId');
        return userId; // Return the authenticated userId
      } else {
        _sendError(webSocket, 'Authentication failed: invalid signature or timestamp');
        _logger.warning('Failed authentication attempt for user: $userId');
        return null;
      }
    } catch (e) {
      _sendError(webSocket, 'Authentication error: $e');
      _logger.error('Authentication error: $e');
      return null;
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
  
  /// Handles call initiation
  Future<void> _handleCallInitiate(WebSocketChannel webSocket, Map<String, dynamic> message, String callerId) async {
    try {
      _logger.info('Call initiation request received from $callerId');
      final recipientId = message['to'] as String?;
      final offer = message['offer'] as String?;
      final callId = message['call_id'] as String?;

      _logger.info('Call details: recipientId=$recipientId, callId=$callId, offer_length=${offer?.length}');

      if (recipientId == null || offer == null || callId == null) {
        _logger.warning('Missing required fields for call initiation');
        _sendError(webSocket, 'Missing required fields for call initiation');
        return;
      }

      if (recipientId == callerId) {
        _logger.warning('User $callerId attempted to call themselves');
        _sendError(webSocket, 'Cannot call yourself');
        return;
      }

      // Check if recipient exists and is online
      final recipient = _userManager.getUser(recipientId);
      if (recipient == null) {
        _logger.warning('Recipient $recipientId not found');
        _sendError(webSocket, 'Recipient not found');
        return;
      }

      _logger.info('Recipient $recipientId found, checking online status...');
      final isOnline = _userManager.isUserOnline(recipientId);
      _logger.info('Recipient $recipientId online status: $isOnline');

      // Store call state
      _activeCalls[callId] = CallState(
        id: callId,
        callerId: callerId,
        calleeId: recipientId,
        status: CallStatus.initiated,
        startTime: DateTime.now(),
      );
      _logger.info('Call state stored for callId: $callId');

      // Forward offer to recipient if online
      if (isOnline) {
        _logger.info('Forwarding call offer to $recipientId...');
        final success = await _userManager.sendToUser(recipientId, {
          'type': 'call_offer',
          'from': callerId,
          'offer': offer,
          'call_id': callId,
          'timestamp': DateTime.now().toIso8601String(),
        });

        if (success) {
          _logger.info('Call offer forwarded successfully: $callerId -> $recipientId (callId: $callId)');
        } else {
          _logger.error('Failed to forward call offer to $recipientId');
          _sendError(webSocket, 'Failed to deliver call to recipient');
          _activeCalls.remove(callId);
        }
      } else {
        _logger.warning('Recipient $recipientId is offline, cannot initiate call');
        _sendError(webSocket, 'Recipient is offline');
        _activeCalls.remove(callId);
      }
    } catch (e) {
      _logger.error('Call initiation error: $e');
      _sendError(webSocket, 'Call initiation error: $e');
    }
  }

  /// Handles call acceptance
  Future<void> _handleCallAccept(WebSocketChannel webSocket, Map<String, dynamic> message, String calleeId) async {
    try {
      final answer = message['answer'] as String?;
      final callId = message['call_id'] as String?;

      if (answer == null || callId == null) {
        _sendError(webSocket, 'Missing required fields for call acceptance');
        return;
      }

      final call = _activeCalls[callId];
      if (call == null || call.calleeId != calleeId) {
        _sendError(webSocket, 'Call not found or unauthorized');
        return;
      }

      // Update call status
      call.status = CallStatus.connected;

      // Forward answer to caller
      await _userManager.sendToUser(call.callerId, {
        'type': 'call_answer',
        'from': calleeId,
        'answer': answer,
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      _logger.info('Call accepted: ${call.callerId} <- $calleeId (callId: $callId)');
    } catch (e) {
      _sendError(webSocket, 'Call acceptance error: $e');
    }
  }

  /// Handles ICE candidates
  Future<void> _handleCallCandidate(WebSocketChannel webSocket, Map<String, dynamic> message, String senderId) async {
    try {
      final candidate = message['candidate'] as String?;
      final callId = message['call_id'] as String?;

      if (candidate == null || callId == null) {
        _sendError(webSocket, 'Missing required fields for ICE candidate');
        return;
      }

      final call = _activeCalls[callId];
      if (call == null) {
        _sendError(webSocket, 'Call not found');
        return;
      }

      // Determine recipient
      final recipientId = call.callerId == senderId ? call.calleeId : call.callerId;

      // Forward candidate to recipient
      await _userManager.sendToUser(recipientId, {
        'type': 'call_candidate',
        'from': senderId,
        'candidate': candidate,
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      _logger.info('ICE candidate forwarded: $senderId -> $recipientId (callId: $callId)');
    } catch (e) {
      _sendError(webSocket, 'ICE candidate error: $e');
    }
  }

  /// Handles call termination
  Future<void> _handleCallEnd(WebSocketChannel webSocket, Map<String, dynamic> message, String senderId) async {
    try {
      final callId = message['call_id'] as String?;

      if (callId == null) {
        _sendError(webSocket, 'Missing call ID for call termination');
        return;
      }

      final call = _activeCalls[callId];
      if (call == null) {
        _sendError(webSocket, 'Call not found');
        return;
      }

      if (call.callerId != senderId && call.calleeId != senderId) {
        _sendError(webSocket, 'Unauthorized call termination');
        return;
      }

      // Update call status
      call.status = CallStatus.ended;
      call.endTime = DateTime.now();

      // Determine recipient
      final recipientId = call.callerId == senderId ? call.calleeId : call.callerId;

      // Forward end message to recipient
      await _userManager.sendToUser(recipientId, {
        'type': 'call_end',
        'from': senderId,
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Clean up call state after delay
      Timer(const Duration(minutes: 1), () {
        _activeCalls.remove(callId);
      });

      _logger.info('Call ended: $senderId -> $recipientId (callId: $callId)');
    } catch (e) {
      _sendError(webSocket, 'Call termination error: $e');
    }
  }

  /// Handles call restart (ICE restart)
  Future<void> _handleCallRestart(WebSocketChannel webSocket, Map<String, dynamic> message, String senderId) async {
    try {
      final offer = message['offer'] as String?;
      final callId = message['call_id'] as String?;

      if (offer == null || callId == null) {
        _sendError(webSocket, 'Missing required fields for call restart');
        return;
      }

      final call = _activeCalls[callId];
      if (call == null) {
        _sendError(webSocket, 'Call not found');
        return;
      }

      // Determine recipient
      final recipientId = call.callerId == senderId ? call.calleeId : call.callerId;

      // Forward restart offer to recipient
      await _userManager.sendToUser(recipientId, {
        'type': 'call_restart',
        'from': senderId,
        'offer': offer,
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      _logger.info('Call restart initiated: $senderId -> $recipientId (callId: $callId)');
    } catch (e) {
      _sendError(webSocket, 'Call restart error: $e');
    }
  }

  /// Handles call restart answer
  Future<void> _handleCallRestartAnswer(WebSocketChannel webSocket, Map<String, dynamic> message, String senderId) async {
    try {
      final answer = message['answer'] as String?;
      final callId = message['call_id'] as String?;

      if (answer == null || callId == null) {
        _sendError(webSocket, 'Missing required fields for call restart answer');
        return;
      }

      final call = _activeCalls[callId];
      if (call == null) {
        _sendError(webSocket, 'Call not found');
        return;
      }

      // Determine recipient
      final recipientId = call.callerId == senderId ? call.calleeId : call.callerId;

      // Forward restart answer to recipient
      await _userManager.sendToUser(recipientId, {
        'type': 'call_restart_answer',
        'from': senderId,
        'answer': answer,
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      _logger.info('Call restart answered: $senderId -> $recipientId (callId: $callId)');
    } catch (e) {
      _sendError(webSocket, 'Call restart answer error: $e');
    }
  }

  /// Generates a userId based on the public signing key
  String _generateUserIdFromPublicKey(String publicKey) {
    // Use the first 16 characters of the public key hash as userId
    final bytes = utf8.encode(publicKey);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16).toUpperCase();
  }

  // Test helper methods
  void testHandleMessage(WebSocketChannel webSocket, Map<String, dynamic> message, String? userId) {
    _handleMessage(webSocket, message, userId);
  }

  Future<String?> testHandleAuthAndGetUserId(WebSocketChannel webSocket, Map<String, dynamic> message) async {
    return await _handleAuthAndGetUserId(webSocket, message);
  }

  Map<String, CallState> get testActiveCalls => _activeCalls;
}