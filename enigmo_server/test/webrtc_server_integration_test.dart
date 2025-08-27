import 'package:test/test.dart';
import 'package:mockito/mockito.dart';
import 'dart:async';
import 'package:enigmo_server/services/websocket_handler.dart';
import 'package:enigmo_server/services/user_manager.dart';
import 'package:enigmo_server/services/message_manager.dart';
import 'package:enigmo_server/services/auth_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// Mock classes
class MockWebSocketChannel extends Mock implements WebSocketChannel {
  final StreamController<String> _controller = StreamController<String>();
  final StreamController<String> _sinkController = StreamController<String>();

  @override
  Stream get stream => _controller.stream;

  @override
  WebSocketSink get sink => WebSocketSink._(_sinkController.sink as dynamic);

  void addMessage(String message) {
    _controller.add(message);
  }

  void close() {
    _controller.close();
    _sinkController.close();
  }
}

void main() {
  group('WebRTC Server Integration Tests', () {
    late WebSocketHandler webSocketHandler;
    late UserManager userManager;
    late MessageManager messageManager;
    late AuthService authService;
    late MockWebSocketChannel mockWebSocket;

    setUp(() {
      userManager = UserManager();
      messageManager = MessageManager(userManager);
      authService = AuthService(userManager);
      webSocketHandler = WebSocketHandler(userManager, messageManager);
      mockWebSocket = MockWebSocketChannel();
    });

    tearDown(() {
      mockWebSocket.close();
    });

    test('Complete call setup flow: register -> call_initiate -> call_accept -> call_end', () async {
      // Arrange
      final callerId = 'user_alice';
      final calleeId = 'user_bob';
      final callId = 'call_001';

      final messages = <String>[];
      mockWebSocket.stream.listen((message) {
        messages.add(message);
      });

      // Act & Assert - Step 1: Register caller
      final registerMessage = {
        'type': 'register',
        'publicSigningKey': 'signing_key_$callerId',
        'publicEncryptionKey': 'encryption_key_$callerId',
        'nickname': 'Alice',
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, registerMessage, null);

      // Step 2: Authenticate caller
      final authMessage = {
        'type': 'auth',
        'userId': callerId,
        'signature': 'mock_signature',
        'timestamp': DateTime.now().toIso8601String(),
      };

      final authResult = await webSocketHandler.testHandleAuthAndGetUserId(mockWebSocket, authMessage);
      expect(authResult, callerId);

      // Step 3: Register callee
      final registerCalleeMessage = {
        'type': 'register',
        'publicSigningKey': 'signing_key_$calleeId',
        'publicEncryptionKey': 'encryption_key_$calleeId',
        'nickname': 'Bob',
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, registerCalleeMessage, null);

      // Step 4: Initiate call
      final callInitiateMessage = {
        'type': 'call_initiate',
        'to': calleeId,
        'offer': 'encrypted_offer_sdp',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, callInitiateMessage, callerId);

      // Step 5: Accept call
      final callAcceptMessage = {
        'type': 'call_accept',
        'answer': 'encrypted_answer_sdp',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, callAcceptMessage, calleeId);

      // Step 6: End call
      final callEndMessage = {
        'type': 'call_end',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, callEndMessage, callerId);

      // Assert
      expect(messages.length, greaterThanOrEqualTo(3)); // register_success, auth_success, call_end
      expect(webSocketHandler.testActiveCalls.containsKey(callId), false); // Call should be cleaned up
    });

    test('ICE candidate exchange during call', () async {
      // Arrange
      final callerId = 'user_alice';
      final calleeId = 'user_bob';
      final callId = 'call_002';

      final messages = <String>[];
      mockWebSocket.stream.listen((message) {
        messages.add(message);
      });

      // Setup users
      await userManager.registerUser(id: callerId, publicSigningKey: 'key1', publicEncryptionKey: 'key1');
      await userManager.registerUser(id: calleeId, publicSigningKey: 'key2', publicEncryptionKey: 'key2');

      // Initiate call
      final callInitiateMessage = {
        'type': 'call_initiate',
        'to': calleeId,
        'offer': 'encrypted_offer_sdp',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, callInitiateMessage, callerId);

      // Act - Exchange ICE candidates
      final candidateMessage1 = {
        'type': 'call_candidate',
        'candidate': 'candidate:1 1 UDP 2122260223 192.168.1.1 5000 typ host',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final candidateMessage2 = {
        'type': 'call_candidate',
        'candidate': 'candidate:2 1 UDP 2122260223 192.168.1.2 5001 typ host',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, candidateMessage1, callerId);
      webSocketHandler.testHandleMessage(mockWebSocket, candidateMessage2, calleeId);

      // Assert
      expect(webSocketHandler.testActiveCalls.containsKey(callId), true);
      expect(webSocketHandler.testActiveCalls[callId]!.status, CallStatus.initiated);
    });

    test('Call restart functionality', () async {
      // Arrange
      final callerId = 'user_alice';
      final calleeId = 'user_bob';
      final callId = 'call_restart_001';

      // Setup users and initial call
      await userManager.registerUser(id: callerId, publicSigningKey: 'key1', publicEncryptionKey: 'key1');
      await userManager.registerUser(id: calleeId, publicSigningKey: 'key2', publicEncryptionKey: 'key2');

      final callInitiateMessage = {
        'type': 'call_initiate',
        'to': calleeId,
        'offer': 'encrypted_offer_sdp',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, callInitiateMessage, callerId);

      // Accept call
      final callAcceptMessage = {
        'type': 'call_accept',
        'answer': 'encrypted_answer_sdp',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, callAcceptMessage, calleeId);

      // Act - Restart call
      final restartOfferMessage = {
        'type': 'call_restart',
        'offer': 'encrypted_restart_offer_sdp',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, restartOfferMessage, callerId);

      final restartAnswerMessage = {
        'type': 'call_restart_answer',
        'answer': 'encrypted_restart_answer_sdp',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, restartAnswerMessage, calleeId);

      // Assert
      expect(webSocketHandler.testActiveCalls.containsKey(callId), true);
    });

    test('Multiple concurrent calls handling', () async {
      // Arrange
      final callerId1 = 'user_alice';
      final callerId2 = 'user_charlie';
      final calleeId = 'user_bob';
      final callId1 = 'call_multi_001';
      final callId2 = 'call_multi_002';

      // Setup users
      await userManager.registerUser(id: callerId1, publicSigningKey: 'key1', publicEncryptionKey: 'key1');
      await userManager.registerUser(id: callerId2, publicSigningKey: 'key3', publicEncryptionKey: 'key3');
      await userManager.registerUser(id: calleeId, publicSigningKey: 'key2', publicEncryptionKey: 'key2');

      // Act - Initiate multiple calls
      final callInitiateMessage1 = {
        'type': 'call_initiate',
        'to': calleeId,
        'offer': 'encrypted_offer_sdp_1',
        'call_id': callId1,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final callInitiateMessage2 = {
        'type': 'call_initiate',
        'to': calleeId,
        'offer': 'encrypted_offer_sdp_2',
        'call_id': callId2,
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, callInitiateMessage1, callerId1);
      webSocketHandler.testHandleMessage(mockWebSocket, callInitiateMessage2, callerId2);

      // Assert
      expect(webSocketHandler.testActiveCalls.containsKey(callId1), true);
      expect(webSocketHandler.testActiveCalls.containsKey(callId2), true);
      expect(webSocketHandler.testActiveCalls.length, 2);
    });

    test('Call timeout and cleanup', () async {
      // Arrange
      final callerId = 'user_alice';
      final calleeId = 'user_bob';
      final callId = 'call_timeout_001';

      // Setup users
      await userManager.registerUser(id: callerId, publicSigningKey: 'key1', publicEncryptionKey: 'key1');
      await userManager.registerUser(id: calleeId, publicSigningKey: 'key2', publicEncryptionKey: 'key2');

      // Initiate call
      final callInitiateMessage = {
        'type': 'call_initiate',
        'to': calleeId,
        'offer': 'encrypted_offer_sdp',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, callInitiateMessage, callerId);

      // Act - End call
      final callEndMessage = {
        'type': 'call_end',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, callEndMessage, callerId);

      // Assert
      expect(webSocketHandler.testActiveCalls.containsKey(callId), false);
    });

    test('Invalid call operations handling', () async {
      // Arrange
      final callerId = 'user_alice';
      final invalidCallId = 'invalid_call_001';

      // Act - Try to accept non-existent call
      final invalidAcceptMessage = {
        'type': 'call_accept',
        'answer': 'encrypted_answer_sdp',
        'call_id': invalidCallId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, invalidAcceptMessage, callerId);

      // Try to end non-existent call
      final invalidEndMessage = {
        'type': 'call_end',
        'call_id': invalidCallId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, invalidEndMessage, callerId);

      // Assert
      expect(webSocketHandler.testActiveCalls.containsKey(invalidCallId), false);
    });

    test('User status updates during calls', () async {
      // Arrange
      final callerId = 'user_alice';
      final calleeId = 'user_bob';

      // Setup users
      await userManager.registerUser(id: callerId, publicSigningKey: 'key1', publicEncryptionKey: 'key1');
      await userManager.registerUser(id: calleeId, publicSigningKey: 'key2', publicEncryptionKey: 'key2');

      // Act - Check initial status
      expect(userManager.isUserOnline(callerId), false);
      expect(userManager.isUserOnline(calleeId), false);

      // Connect users
      final mockWebSocketCaller = MockWebSocketChannel();
      final mockWebSocketCallee = MockWebSocketChannel();

      userManager.connectUser(callerId, mockWebSocketCaller);
      userManager.connectUser(calleeId, mockWebSocketCallee);

      // Assert
      expect(userManager.isUserOnline(callerId), true);
      expect(userManager.isUserOnline(calleeId), true);

      // Cleanup
      mockWebSocketCaller.close();
      mockWebSocketCallee.close();
    });

    test('Message routing during calls', () async {
      // Arrange
      final callerId = 'user_alice';
      final calleeId = 'user_bob';
      final callId = 'call_message_001';

      // Setup users
      await userManager.registerUser(id: callerId, publicSigningKey: 'key1', publicEncryptionKey: 'key1');
      await userManager.registerUser(id: calleeId, publicSigningKey: 'key2', publicEncryptionKey: 'key2');

      final mockWebSocketCaller = MockWebSocketChannel();
      final mockWebSocketCallee = MockWebSocketChannel();

      userManager.connectUser(callerId, mockWebSocketCaller);
      userManager.connectUser(calleeId, mockWebSocketCallee);

      // Initiate call
      final callInitiateMessage = {
        'type': 'call_initiate',
        'to': calleeId,
        'offer': 'encrypted_offer_sdp',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocketCaller, callInitiateMessage, callerId);

      // Act - Send message during call
      final messageData = {
        'type': 'send_message',
        'receiverId': calleeId,
        'encryptedContent': 'encrypted_message_content',
        'messageType': 'text',
        'signature': 'mock_signature',
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocketCaller, messageData, callerId);

      // Assert
      expect(webSocketHandler.testActiveCalls.containsKey(callId), true);

      // Cleanup
      mockWebSocketCaller.close();
      mockWebSocketCallee.close();
    });

    test('Server statistics during call activity', () async {
      // Arrange
      final callerId = 'user_alice';
      final calleeId = 'user_bob';
      final callId = 'call_stats_001';

      // Setup users
      await userManager.registerUser(id: callerId, publicSigningKey: 'key1', publicEncryptionKey: 'key1');
      await userManager.registerUser(id: calleeId, publicSigningKey: 'key2', publicEncryptionKey: 'key2');

      final initialStats = userManager.getStats();

      // Act - Create call
      final callInitiateMessage = {
        'type': 'call_initiate',
        'to': calleeId,
        'offer': 'encrypted_offer_sdp',
        'call_id': callId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      webSocketHandler.testHandleMessage(mockWebSocket, callInitiateMessage, callerId);

      final afterCallStats = userManager.getStats();

      // Assert
      expect(afterCallStats['totalUsers'], equals(initialStats['totalUsers']));
      expect(webSocketHandler.testActiveCalls.length, 1);
    });
  });
}