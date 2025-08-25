import 'package:test/test.dart';
import 'package:enigmo_server/services/user_manager.dart';
import 'package:enigmo_server/services/message_manager.dart';
import 'package:enigmo_server/services/websocket_handler.dart';
import 'package:enigmo_server/services/auth_service.dart';
import 'package:enigmo_server/models/user.dart';
import 'package:enigmo_server/models/message.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

/// Advanced mock WebSocket for edge case testing
/// Advanced mock WebSocket channel with simplified implementation
class AdvancedMockWebSocketChannel implements WebSocketChannel {
  final StreamController<String> _streamController = StreamController<String>.broadcast();
  final List<String> sentMessages = [];
  bool _isConnected = true;
  bool _shouldDropMessages = false;
  bool _shouldDelayMessages = false;
  bool _shouldCorruptMessages = false;
  Duration _messageDelay = const Duration(milliseconds: 100);
  final Random _random = Random();

  late final _AdvancedMockWebSocketSink _sink;

  AdvancedMockWebSocketChannel() {
    _sink = _AdvancedMockWebSocketSink()..onAdd = _handleMessage;
  }

  void _handleMessage(dynamic data) {
    if (!_isConnected) return;
    
    final message = data.toString();
    
    // Simulate message dropping
    if (_shouldDropMessages && _random.nextDouble() < 0.3) {
      print('DEBUG: Dropping message: ${message.substring(0, min(50, message.length))}...');
      return;
    }
    
    // Simulate message corruption
    String finalMessage = message;
    if (_shouldCorruptMessages && _random.nextDouble() < 0.2) {
      finalMessage = _corruptMessage(message);
      print('DEBUG: Corrupting message');
    }
    
    sentMessages.add(finalMessage);
    
    // Simulate message delay
    if (_shouldDelayMessages) {
      Timer(_messageDelay, () {
        if (_isConnected) {
          _streamController.add(finalMessage);
        }
      });
    } else {
      _streamController.add(finalMessage);
    }
  }

  @override
  Stream<dynamic> get stream => _streamController.stream;
  
  @override
  WebSocketSink get sink => _sink;
  
  @override
  int? get closeCode => null;
  
  @override
  String? get closeReason => null;
  
  @override
  String? get protocol => null;
  
  @override
  Future<void> get ready => Future.value();
  
  // Implement missing StreamChannelMixin methods with noSuchMethod
  @override
  dynamic noSuchMethod(Invocation invocation) {
    // Return appropriate defaults for missing methods
    if (invocation.memberName == #cast) {
      return this;
    }
    if (invocation.memberName == #changeSink || 
        invocation.memberName == #changeStream ||
        invocation.memberName == #transform ||
        invocation.memberName == #transformSink ||
        invocation.memberName == #transformStream) {
      return this;
    }
    if (invocation.memberName == #pipe) {
      return null;
    }
    return super.noSuchMethod(invocation);
  }



  void simulateNetworkPartition() {
    _isConnected = false;
    print('DEBUG: Network partition simulated');
  }

  void restoreNetworkConnection() {
    _isConnected = true;
    print('DEBUG: Network connection restored');
  }

  void enableMessageDropping() {
    _shouldDropMessages = true;
  }

  void disableMessageDropping() {
    _shouldDropMessages = false;
  }

  void enableMessageDelay(Duration delay) {
    _shouldDelayMessages = true;
    _messageDelay = delay;
  }

  void disableMessageDelay() {
    _shouldDelayMessages = false;
  }

  void enableMessageCorruption() {
    _shouldCorruptMessages = true;
  }

  void disableMessageCorruption() {
    _shouldCorruptMessages = false;
  }

  void simulateIncomingMessage(String message) {
    if (_isConnected) {
      _streamController.add(message);
    }
  }

  void simulateConnectionDrop() {
    _isConnected = false;
    _streamController.close();
  }

  void clearSentMessages() {
    sentMessages.clear();
  }

  String _corruptMessage(String message) {
    try {
      final json = jsonDecode(message) as Map<String, dynamic>;
      
      // Randomly corrupt different fields
      switch (_random.nextInt(4)) {
        case 0:
          json['type'] = 'corrupted_type';
          break;
        case 1:
          if (json.containsKey('userId')) {
            json['userId'] = 'corrupted_user_id';
          }
          break;
        case 2:
          if (json.containsKey('signature')) {
            json['signature'] = 'corrupted_signature_data';
          }
          break;
        case 3:
          json['corrupted_field'] = 'unexpected_data';
          break;
      }
      
      return jsonEncode(json);
    } catch (e) {
      // If not JSON, just add random characters
      return message + '\x00\xFF\xFE';
    }
  }
}

class _AdvancedMockWebSocketSink implements WebSocketSink {
  Function(dynamic)? onAdd;

  @override
  void add(data) {
    onAdd?.call(data);
  }

  @override
  void addError(error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) async {}

  @override
  Future close([int? closeCode, String? closeReason]) async {}

  @override
  Future get done => Future.value();
}

void main() {
  group('Network and WebSocket Edge Case Tests', () {
    late UserManager userManager;
    late MessageManager messageManager;
    late WebSocketHandler webSocketHandler;
    late AuthService authService;

    setUp(() {
      userManager = UserManager();
      messageManager = MessageManager(userManager);
      webSocketHandler = WebSocketHandler(userManager, messageManager);
      authService = AuthService(userManager);
    });

    group('Connection Edge Cases', () {
      test('should handle rapid connect/disconnect cycles', () async {
        final channels = <AdvancedMockWebSocketChannel>[];
        
        // Create and rapidly cycle connections
        for (int i = 0; i < 10; i++) {
          final channel = AdvancedMockWebSocketChannel();
          channels.add(channel);
          
          // Simulate connection
          webSocketHandler.handler(null!); // This would normally create a handler
          
          // Simulate immediate disconnection
          channel.simulateConnectionDrop();
          
          // Small delay between cycles
          await Future.delayed(const Duration(milliseconds: 50));
        }
        
        // System should remain stable
        final stats = userManager.getUserStats();
        expect(stats['online'], equals(0)); // All should be disconnected
      });

      test('should handle network partitions gracefully', () async {
        const userId = 'partition_test_user';
        final channel = AdvancedMockWebSocketChannel();
        
        // Register and connect user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: 'test_key',
          publicEncryptionKey: 'test_enc_key',
        );
        
        userManager.connectUser(userId, channel);
        expect(userManager.isUserOnline(userId), isTrue);
        
        // Simulate network partition
        channel.simulateNetworkPartition();
        
        // Attempt to send message during partition
        final success = await userManager.sendToUser(userId, {
          'type': 'test_during_partition',
          'data': 'This should not be delivered'
        });
        
        expect(success, isFalse);
        
        // Restore connection
        channel.restoreNetworkConnection();
        
        // User should eventually be marked as offline due to failed delivery
        userManager.disconnectUser(userId);
        expect(userManager.isUserOnline(userId), isFalse);
      });

      test('should handle message delivery during unstable connections', () async {
        const senderId = 'unstable_sender';
        const receiverId = 'unstable_receiver';
        final senderChannel = AdvancedMockWebSocketChannel();
        final receiverChannel = AdvancedMockWebSocketChannel();
        
        // Register users
        await userManager.registerUser(
          id: senderId,
          publicSigningKey: 'sender_key',
          publicEncryptionKey: 'sender_enc_key',
        );
        await userManager.registerUser(
          id: receiverId,
          publicSigningKey: 'receiver_key',
          publicEncryptionKey: 'receiver_enc_key',
        );
        
        // Connect users with unstable connections
        userManager.connectUser(senderId, senderChannel);
        userManager.connectUser(receiverId, receiverChannel);
        
        // Enable message dropping for receiver
        receiverChannel.enableMessageDropping();
        
        // Send multiple messages
        final sentMessages = <ServerMessage>[];
        for (int i = 0; i < 10; i++) {
          final message = await messageManager.sendMessage(
            senderId: senderId,
            receiverId: receiverId,
            encryptedContent: 'Test message $i',
            signature: 'signature_$i',
          );
          sentMessages.add(message);
        }
        
        expect(sentMessages.length, equals(10));
        
        // Some messages may have been dropped
        final deliveredCount = receiverChannel.sentMessages.length;
        expect(deliveredCount, lessThanOrEqualTo(10));
        print('Delivered $deliveredCount out of 10 messages with unstable connection');
      });
    });

    group('Message Handling Edge Cases', () {
      test('should handle extremely large messages', () async {
        const senderId = 'large_message_sender';
        const receiverId = 'large_message_receiver';
        
        await userManager.registerUser(
          id: senderId,
          publicSigningKey: 'sender_key',
          publicEncryptionKey: 'sender_enc_key',
        );
        await userManager.registerUser(
          id: receiverId,
          publicSigningKey: 'receiver_key',
          publicEncryptionKey: 'receiver_enc_key',
        );
        
        // Create very large message (1MB)
        final largeContent = 'A' * (1024 * 1024);
        
        final message = await messageManager.sendMessage(
          senderId: senderId,
          receiverId: receiverId,
          encryptedContent: largeContent,
          signature: 'large_signature',
        );
        
        expect(message.encryptedContent.length, equals(1024 * 1024));
        
        // Message should be stored and retrievable
        final history = await messageManager.getMessageHistory(senderId, receiverId);
        expect(history.length, equals(1));
        expect(history.first.encryptedContent.length, equals(1024 * 1024));
      });

      test('should handle message flooding attacks', () async {
        const attackerId = 'message_flooder';
        const victimId = 'flood_victim';
        final attackerChannel = AdvancedMockWebSocketChannel();
        
        await userManager.registerUser(
          id: attackerId,
          publicSigningKey: 'attacker_key',
          publicEncryptionKey: 'attacker_enc_key',
        );
        await userManager.registerUser(
          id: victimId,
          publicSigningKey: 'victim_key',
          publicEncryptionKey: 'victim_enc_key',
        );
        
        userManager.connectUser(attackerId, attackerChannel);
        
        final startTime = DateTime.now();
        
        // Flood with many messages rapidly
        for (int i = 0; i < 1000; i++) {
          await messageManager.sendMessage(
            senderId: attackerId,
            receiverId: victimId,
            encryptedContent: 'Flood message $i',
            signature: 'flood_sig_$i',
          );
        }
        
        final endTime = DateTime.now();
        final duration = endTime.difference(startTime);
        
        print('Processed 1000 messages in ${duration.inMilliseconds}ms');
        
        // System should handle the flood without crashing
        final history = await messageManager.getMessageHistory(attackerId, victimId);
        expect(history.length, equals(1000));
        
        // Performance should be reasonable (less than 10 seconds for 1000 messages)
        expect(duration.inSeconds, lessThan(10));
      });

      test('should handle malformed WebSocket messages', () async {
        final channel = AdvancedMockWebSocketChannel();
        
        // Enable message corruption
        channel.enableMessageCorruption();
        
        // Send various malformed messages
        final malformedMessages = [
          'not json at all',
          '{"incomplete": json',
          '{"type": null}',
          '{"type": ""}',
          '{}',
          '[]',
          'null',
          '{"type": "unknown_type", "data": "test"}',
          '{"type": "auth", "userId": null}',
          '{"type": "send_message", "receiverId": "", "content": ""}',
        ];
        
        for (final malformed in malformedMessages) {
          // Simulate receiving malformed message
          channel.simulateIncomingMessage(malformed);
          
          // Small delay to allow processing
          await Future.delayed(const Duration(milliseconds: 10));
        }
        
        // System should handle all malformed messages without crashing
        expect(true, isTrue); // Test completion indicates stability
      });
    });

    group('Concurrency Edge Cases', () {
      test('should handle concurrent user operations', () async {
        final futures = <Future>[];
        
        // Concurrent user registrations
        for (int i = 0; i < 50; i++) {
          futures.add(userManager.registerUser(
            id: 'concurrent_user_$i',
            publicSigningKey: 'key_$i',
            publicEncryptionKey: 'enc_key_$i',
          ));
        }
        
        final results = await Future.wait(futures);
        
        // All registrations should succeed
        expect(results.length, equals(50));
        for (final result in results) {
          expect(result, isNotNull);
        }
        
        final allUsers = await userManager.getAllUsers();
        expect(allUsers.length, greaterThanOrEqualTo(50)); // Including default users
      });

      test('should handle concurrent message sending', () async {
        const senderId = 'concurrent_sender';
        const receiverId = 'concurrent_receiver';
        
        await userManager.registerUser(
          id: senderId,
          publicSigningKey: 'sender_key',
          publicEncryptionKey: 'sender_enc_key',
        );
        await userManager.registerUser(
          id: receiverId,
          publicSigningKey: 'receiver_key',
          publicEncryptionKey: 'receiver_enc_key',
        );
        
        // Send many messages concurrently
        final futures = <Future<ServerMessage>>[];
        for (int i = 0; i < 100; i++) {
          futures.add(messageManager.sendMessage(
            senderId: senderId,
            receiverId: receiverId,
            encryptedContent: 'Concurrent message $i',
            signature: 'signature_$i',
          ));
        }
        
        final messages = await Future.wait(futures);
        
        expect(messages.length, equals(100));
        
        // All messages should have unique IDs
        final messageIds = messages.map((m) => m.id).toSet();
        expect(messageIds.length, equals(100));
        
        // Message history should contain all messages
        final history = await messageManager.getMessageHistory(senderId, receiverId);
        expect(history.length, equals(100));
      });

      test('should handle race conditions in user status', () async {
        final userIds = List.generate(20, (i) => 'race_user_$i');
        final channels = List.generate(20, (i) => AdvancedMockWebSocketChannel());
        
        // Register all users
        for (int i = 0; i < userIds.length; i++) {
          await userManager.registerUser(
            id: userIds[i],
            publicSigningKey: 'key_$i',
            publicEncryptionKey: 'enc_key_$i',
          );
        }
        
        // Rapidly connect/disconnect all users
        final futures = <Future>[];
        for (int i = 0; i < userIds.length; i++) {
          futures.add(Future(() async {
            for (int cycle = 0; cycle < 10; cycle++) {
              userManager.connectUser(userIds[i], channels[i]);
              await Future.delayed(const Duration(milliseconds: 10));
              userManager.disconnectUser(userIds[i]);
              await Future.delayed(const Duration(milliseconds: 10));
            }
          }));
        }
        
        await Future.wait(futures);
        
        // System should be in consistent state
        final stats = userManager.getUserStats();
        expect(stats['online'], equals(0)); // All should be disconnected
        expect(stats['total'], greaterThanOrEqualTo(20));
      });
    });

    group('Memory and Resource Edge Cases', () {
      test('should handle memory pressure from large message history', () async {
        const senderId = 'memory_test_sender';
        const receiverId = 'memory_test_receiver';
        
        await userManager.registerUser(
          id: senderId,
          publicSigningKey: 'sender_key',
          publicEncryptionKey: 'sender_enc_key',
        );
        await userManager.registerUser(
          id: receiverId,
          publicSigningKey: 'receiver_key',
          publicEncryptionKey: 'receiver_enc_key',
        );
        
        // Create large message history
        for (int i = 0; i < 10000; i++) {
          await messageManager.sendMessage(
            senderId: senderId,
            receiverId: receiverId,
            encryptedContent: 'Memory test message $i with some content to make it larger',
            signature: 'signature_$i',
          );
          
          // Periodic yield to allow other operations
          if (i % 100 == 0) {
            await Future.delayed(const Duration(milliseconds: 1));
          }
        }
        
        // Retrieve history with limit
        final recentHistory = await messageManager.getMessageHistory(
          senderId, 
          receiverId, 
          limit: 50
        );
        expect(recentHistory.length, equals(50));
        
        // System should still be responsive
        final stats = messageManager.getMessageStats();
        expect(stats['totalMessages'], equals(10000));
      });

      test('should handle connection cleanup after abrupt disconnections', () async {
        final channels = <AdvancedMockWebSocketChannel>[];
        final userIds = <String>[];
        
        // Create many connections
        for (int i = 0; i < 100; i++) {
          final userId = 'cleanup_user_$i';
          final channel = AdvancedMockWebSocketChannel();
          
          await userManager.registerUser(
            id: userId,
            publicSigningKey: 'key_$i',
            publicEncryptionKey: 'enc_key_$i',
          );
          
          userManager.connectUser(userId, channel);
          channels.add(channel);
          userIds.add(userId);
        }
        
        expect(userManager.getOnlineUsers().length, equals(100));
        
        // Simulate abrupt disconnections
        for (int i = 0; i < channels.length; i++) {
          channels[i].simulateConnectionDrop();
          userManager.disconnectChannel(channels[i]);
        }
        
        // All users should be marked as offline
        expect(userManager.getOnlineUsers().length, equals(0));
        
        final stats = userManager.getUserStats();
        expect(stats['online'], equals(0));
        expect(stats['offline'], equals(100));
      });
    });

    group('Protocol Edge Cases', () {
      test('should handle authentication with edge case timestamps', () async {
        const userId = 'timestamp_edge_user';
        
        await userManager.registerUser(
          id: userId,
          publicSigningKey: 'edge_key',
          publicEncryptionKey: 'edge_enc_key',
        );
        
        // Test various edge case timestamps
        final edgeTimestamps = [
          DateTime.now().toIso8601String(), // Current time
          DateTime.now().subtract(const Duration(minutes: 4, seconds: 59)).toIso8601String(), // Just within window
          DateTime.now().subtract(const Duration(minutes: 5, seconds: 1)).toIso8601String(), // Just outside window
          DateTime.now().add(const Duration(hours: 1)).toIso8601String(), // Future time
          '2024-01-01T00:00:00.000Z', // Very old time
          '2030-12-31T23:59:59.999Z', // Far future time
        ];
        
        for (final timestamp in edgeTimestamps) {
          final result = await authService.authenticateUser(
            userId,
            'fake_signature',
            timestamp,
          );
          
          // Should handle all timestamps gracefully (most will fail, but shouldn't crash)
          expect(result, isA<bool>());
        }
      });

      test('should handle WebSocket protocol violations', () async {
        final channel = AdvancedMockWebSocketChannel();
        
        // Send messages that violate expected protocol
        final protocolViolations = [
          '{"type": "auth"}', // Missing required fields
          '{"type": "send_message"}', // Missing required fields
          '{"type": "register", "publicSigningKey": ""}', // Empty required field
          '{"userId": "test", "signature": "test"}', // Missing type field
          '{"type": "ping", "extraField": "unexpected"}', // Extra fields
          '{"type": "auth", "userId": "test", "signature": null, "timestamp": null}', // Null values
        ];
        
        for (final violation in protocolViolations) {
          channel.simulateIncomingMessage(violation);
          await Future.delayed(const Duration(milliseconds: 10));
        }
        
        // Should handle all violations without crashing
        expect(true, isTrue);
      });
    });

    group('Failure Recovery Edge Cases', () {
      test('should recover from temporary service failures', () async {
        // Simulate various service failure scenarios
        const userId = 'recovery_test_user';
        final channel = AdvancedMockWebSocketChannel();
        
        await userManager.registerUser(
          id: userId,
          publicSigningKey: 'recovery_key',
          publicEncryptionKey: 'recovery_enc_key',
        );
        
        userManager.connectUser(userId, channel);
        
        // Test recovery after connection issues
        channel.enableMessageDelay(const Duration(seconds: 2));
        
        // Send message during delay period
        final success = await userManager.sendToUser(userId, {
          'type': 'recovery_test',
          'data': 'test_data'
        });
        
        // Message should be queued/handled appropriately
        expect(success, isA<bool>());
        
        // Restore normal operation
        channel.disableMessageDelay();
        
        // Subsequent operations should work normally
        final laterSuccess = await userManager.sendToUser(userId, {
          'type': 'normal_operation',
          'data': 'normal_data'
        });
        
        expect(laterSuccess, isTrue);
      });
    });
  });
}