import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enigmo_app/services/crypto_engine.dart';
import 'package:enigmo_app/services/key_manager.dart';
import 'package:enigmo_app/services/network_service.dart';
import 'package:enigmo_app/models/message.dart';
import 'package:enigmo_app/models/chat.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';
import 'dart:async';

/// Mock KeyManager for integration testing to avoid flutter_secure_storage plugin issues
class MockKeyManager {
  static SimpleKeyPair? _mockSigningKeyPair;
  static SimpleKeyPair? _mockEncryptionKeyPair;
  
  static Future<MockKeyPair> generateUserKeys() async {
    final ed25519 = Ed25519();
    final x25519 = X25519();
    
    _mockSigningKeyPair = await ed25519.newKeyPair();
    _mockEncryptionKeyPair = await x25519.newKeyPair();
    
    return MockKeyPair(
      signingKeyPair: _mockSigningKeyPair!,
      encryptionKeyPair: _mockEncryptionKeyPair!,
    );
  }
  
  static Future<SimpleKeyPair?> getSigningKeyPair() async {
    return _mockSigningKeyPair;
  }
  
  static Future<SimpleKeyPair?> getEncryptionKeyPair() async {
    return _mockEncryptionKeyPair;
  }
}

class MockKeyPair {
  final SimpleKeyPair signingKeyPair;
  final SimpleKeyPair encryptionKeyPair;
  
  MockKeyPair({required this.signingKeyPair, required this.encryptionKeyPair});
}

/// Mock NetworkService for integration testing
class MockNetworkService {
  final Map<String, dynamic> _userKeys = {};
  final List<Map<String, dynamic>> _messageHistory = [];
  bool _isConnected = false;
  String? _userId;
  
  final StreamController<Message> _messageController = StreamController<Message>.broadcast();
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  
  Stream<Message> get newMessages => _messageController.stream;
  Stream<bool> get connectionStatus => _connectionController.stream;
  
  bool get isConnected => _isConnected;
  String? get userId => _userId;

  Future<bool> connect() async {
    await Future.delayed(const Duration(milliseconds: 100)); // Simulate network delay
    _isConnected = true;
    _connectionController.add(true);
    return true;
  }

  Future<String?> registerUser() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _userId = 'test_user_${DateTime.now().millisecondsSinceEpoch}';
    return _userId;
  }

  Future<bool> authenticate() async {
    await Future.delayed(const Duration(milliseconds: 150));
    return _userId != null;
  }

  Future<bool> sendMessage(String receiverId, String content, MessageType type) async {
    if (!_isConnected || _userId == null) return false;
    
    await Future.delayed(const Duration(milliseconds: 300)); // Simulate encryption and network
    
    final message = {
      'id': 'msg_${DateTime.now().millisecondsSinceEpoch}',
      'senderId': _userId!,
      'receiverId': receiverId,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
      'type': type.toString().split('.').last,
    };
    
    _messageHistory.add(message);
    
    // Simulate receiving acknowledgment
    final ackMessage = Message(
      id: message['id'] as String,
      senderId: _userId!,
      receiverId: receiverId,
      content: content,
      timestamp: DateTime.parse(message['timestamp'] as String),
      type: type,
      status: MessageStatus.delivered,
      isEncrypted: true,
    );
    
    _messageController.add(ackMessage);
    return true;
  }

  void disconnect() {
    _isConnected = false;
    _connectionController.add(false);
  }

  void dispose() {
    _messageController.close();
    _connectionController.close();
  }
}

void main() {
  // Initialize Flutter test bindings to support secure storage in tests
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('End-to-End Integration Tests', () {
    late MockNetworkService mockNetwork;

    setUp(() {
      mockNetwork = MockNetworkService();
    });

    tearDown(() {
      mockNetwork.dispose();
    });

    group('Complete Message Flow Integration', () {
      test('should complete full message encryption and sending flow', () async {
        // Step 1: Generate keys for Alice
        final aliceKeyPair = await MockKeyManager.generateUserKeys();
        final aliceSigningPublicKey = await aliceKeyPair.signingKeyPair.extractPublicKey();
        final aliceEncryptionPublicKey = await aliceKeyPair.encryptionKeyPair.extractPublicKey();
        
        // Step 2: Generate keys for Bob
        final ed25519 = Ed25519();
        final x25519 = X25519();
        final bobSigningKeyPair = await ed25519.newKeyPair();
        final bobEncryptionKeyPair = await x25519.newKeyPair();
        final bobSigningPublicKey = await bobSigningKeyPair.extractPublicKey();
        final bobEncryptionPublicKey = await bobEncryptionKeyPair.extractPublicKey();
        
        // Step 3: Alice encrypts a message for Bob
        const originalMessage = 'Hello Bob! This is an end-to-end encrypted message.';
        
        final encryptedMessage = await CryptoEngine.encryptMessage(
          originalMessage,
          bobEncryptionPublicKey,
        );
        
        expect(encryptedMessage.encryptedData, isNotEmpty);
        expect(encryptedMessage.nonce, isNotEmpty);
        expect(encryptedMessage.mac, isNotEmpty);
        expect(encryptedMessage.signature, isNotEmpty);
        
        // Step 4: Simulate network transmission (message would be sent as JSON)
        final messageJson = encryptedMessage.toJson();
        final transmittedMessage = EncryptedMessage.fromJson(messageJson);
        
        // Step 5: Bob decrypts the message
        final decryptedMessage = await CryptoEngine.decryptMessage(
          transmittedMessage,
          aliceEncryptionPublicKey,
          aliceSigningPublicKey,
        );
        
        expect(decryptedMessage, equals(originalMessage));
      });

      test('should handle multiple message exchanges', () async {
        // Generate keys for both users
        final aliceKeyPair = await MockKeyManager.generateUserKeys();
        final aliceSigningPublicKey = await aliceKeyPair.signingKeyPair.extractPublicKey();
        final aliceEncryptionPublicKey = await aliceKeyPair.encryptionKeyPair.extractPublicKey();
        
        final ed25519 = Ed25519();
        final x25519 = X25519();
        final bobSigningKeyPair = await ed25519.newKeyPair();
        final bobEncryptionKeyPair = await x25519.newKeyPair();
        final bobSigningPublicKey = await bobSigningKeyPair.extractPublicKey();
        final bobEncryptionPublicKey = await bobEncryptionKeyPair.extractPublicKey();
        
        final messages = [
          'Hello Bob!',
          'How are you today?',
          'Let\'s meet for coffee ☕',
          'Sure! What time works for you?',
          'How about 3 PM?',
        ];
        
        final encryptedMessages = <EncryptedMessage>[];
        final decryptedMessages = <String>[];
        
        // Simulate conversation: Alice sends messages to Bob
        for (int i = 0; i < messages.length; i++) {
          // Alice encrypts message
          final encrypted = await CryptoEngine.encryptMessage(
            messages[i],
            bobEncryptionPublicKey,
          );
          encryptedMessages.add(encrypted);
          
          // Bob decrypts message
          final decrypted = await CryptoEngine.decryptMessage(
            encrypted,
            aliceEncryptionPublicKey,
            aliceSigningPublicKey,
          );
          decryptedMessages.add(decrypted);
        }
        
        // Verify all messages were transmitted correctly
        for (int i = 0; i < messages.length; i++) {
          expect(decryptedMessages[i], equals(messages[i]));
        }
      });

      test('should handle different message types and content', () async {
        final aliceKeyPair = await KeyManager.generateUserKeys();
        final ed25519 = Ed25519();
        final x25519 = X25519();
        final bobEncryptionKeyPair = await x25519.newKeyPair();
        final bobEncryptionPublicKey = await bobEncryptionKeyPair.extractPublicKey();
        
        final testCases = [
          'Simple text message',
          'Message with émojis 🔐🚀💻',
          'Very long message: ' + 'x' * 1000,
          'Special characters: !@#\$%^&*()_+-=[]{}|;\":,.<>?',
          'Unicode: العربية русский 中文 日本語',
          'Newlines and\\ttabs\\nand\\rcarriage returns',
          '{"json": "message", "number": 42, "array": [1,2,3]}',
        ];
        
        for (final testMessage in testCases) {
          final encrypted = await CryptoEngine.encryptMessage(
            testMessage,
            bobEncryptionPublicKey,
          );
          
          // Simulate transmission
          final transmitted = EncryptedMessage.fromJson(encrypted.toJson());
          
          final decrypted = await CryptoEngine.decryptMessage(
            transmitted,
            await aliceKeyPair.encryptionKeyPair.extractPublicKey(),
            await aliceKeyPair.signingKeyPair.extractPublicKey(),
          );
          
          expect(decrypted, equals(testMessage));
        }
      });
    });

    group('Network Service Integration', () {
      test('should handle complete connection and authentication flow', () async {
        // Connect to network
        final connected = await mockNetwork.connect();
        expect(connected, isTrue);
        expect(mockNetwork.isConnected, isTrue);
        
        // Register user
        final userId = await mockNetwork.registerUser();
        expect(userId, isNotNull);
        expect(mockNetwork.userId, isNotNull);
        
        // Authenticate
        final authenticated = await mockNetwork.authenticate();
        expect(authenticated, isTrue);
      });

      test('should handle message sending with network simulation', () async {
        // Setup connection
        await mockNetwork.connect();
        await mockNetwork.registerUser();
        await mockNetwork.authenticate();
        
        // Setup message listener
        final receivedMessages = <Message>[];
        final subscription = mockNetwork.newMessages.listen((message) {
          receivedMessages.add(message);
        });
        
        // Send test message
        const receiverId = 'test_receiver';
        const messageContent = 'Test message through network';
        
        final success = await mockNetwork.sendMessage(
          receiverId,
          messageContent,
          MessageType.text,
        );
        
        expect(success, isTrue);
        
        // Wait for message processing
        await Future.delayed(const Duration(milliseconds: 500));
        
        expect(receivedMessages.length, equals(1));
        expect(receivedMessages.first.content, equals(messageContent));
        expect(receivedMessages.first.receiverId, equals(receiverId));
        expect(receivedMessages.first.status, equals(MessageStatus.delivered));
        
        await subscription.cancel();
      });

      test('should handle connection status changes', () async {
        final connectionStates = <bool>[];
        final subscription = mockNetwork.connectionStatus.listen((state) {
          connectionStates.add(state);
        });
        
        // Initial state
        expect(mockNetwork.isConnected, isFalse);
        
        // Connect
        await mockNetwork.connect();
        expect(mockNetwork.isConnected, isTrue);
        
        // Disconnect
        mockNetwork.disconnect();
        expect(mockNetwork.isConnected, isFalse);
        
        // Wait for state changes to propagate
        await Future.delayed(const Duration(milliseconds: 100));
        
        expect(connectionStates, contains(true));
        expect(connectionStates, contains(false));
        
        await subscription.cancel();
      });

      test('should handle offline message queuing simulation', () async {
        // Try to send message while offline
        const messageContent = 'Offline message';
        const receiverId = 'offline_receiver';
        
        final success = await mockNetwork.sendMessage(
          receiverId,
          messageContent,
          MessageType.text,
        );
        
        expect(success, isFalse); // Should fail when offline
        
        // Connect and try again
        await mockNetwork.connect();
        await mockNetwork.registerUser();
        await mockNetwork.authenticate();
        
        final onlineSuccess = await mockNetwork.sendMessage(
          receiverId,
          messageContent,
          MessageType.text,
        );
        
        expect(onlineSuccess, isTrue);
      });
    });

    group('Error Handling Integration', () {
      test('should handle network failures gracefully', () async {
        // Simulate connection failure
        expect(mockNetwork.isConnected, isFalse);
        
        // Attempt operations while disconnected
        final authResult = await mockNetwork.authenticate();
        expect(authResult, isFalse);
        
        final sendResult = await mockNetwork.sendMessage(
          'test_receiver',
          'test_message',
          MessageType.text,
        );
        expect(sendResult, isFalse);
      });

      test('should handle malformed encrypted messages', () async {
        final aliceKeyPair = await KeyManager.generateUserKeys();
        final aliceSigningPublicKey = await aliceKeyPair.signingKeyPair.extractPublicKey();
        final aliceEncryptionPublicKey = await aliceKeyPair.encryptionKeyPair.extractPublicKey();
        
        final malformedMessages = [
          EncryptedMessage(
            encryptedData: 'invalid_base64!@#',
            nonce: 'valid_nonce_data',
            mac: 'valid_mac_data',
            signature: 'valid_signature',
          ),
          EncryptedMessage(
            encryptedData: '',
            nonce: 'dGVzdA==',
            mac: 'dGVzdA==',
            signature: 'dGVzdA==',
          ),
          EncryptedMessage(
            encryptedData: 'dGVzdA==',
            nonce: '',
            mac: 'dGVzdA==',
            signature: 'dGVzdA==',
          ),
        ];
        
        for (final malformedMessage in malformedMessages) {
          expect(
            () async => await CryptoEngine.decryptMessage(
              malformedMessage,
              aliceEncryptionPublicKey,
              aliceSigningPublicKey,
            ),
            throwsException,
          );
        }
      });

      test('should detect signature tampering in integration flow', () async {
        final aliceKeyPair = await KeyManager.generateUserKeys();
        final aliceSigningPublicKey = await aliceKeyPair.signingKeyPair.extractPublicKey();
        final aliceEncryptionPublicKey = await aliceKeyPair.encryptionKeyPair.extractPublicKey();
        
        final ed25519 = Ed25519();
        final x25519 = X25519();
        final bobEncryptionKeyPair = await x25519.newKeyPair();
        final bobEncryptionPublicKey = await bobEncryptionKeyPair.extractPublicKey();
        
        // Create a valid encrypted message
        const originalMessage = 'Message to be tampered with';
        final encryptedMessage = await CryptoEngine.encryptMessage(
          originalMessage,
          bobEncryptionPublicKey,
        );
        
        // Tamper with the signature
        final tamperedSignature = encryptedMessage.signature.replaceFirst('A', 'B');
        final tamperedMessage = EncryptedMessage(
          encryptedData: encryptedMessage.encryptedData,
          nonce: encryptedMessage.nonce,
          mac: encryptedMessage.mac,
          signature: tamperedSignature,
        );
        
        // Decryption should fail due to invalid signature
        expect(
          () async => await CryptoEngine.decryptMessage(
            tamperedMessage,
            aliceEncryptionPublicKey,
            aliceSigningPublicKey,
          ),
          throwsException,
        );
      });
    });

    group('Performance Integration Tests', () {
      test('should handle rapid message encryption/decryption cycles', () async {
        final aliceKeyPair = await KeyManager.generateUserKeys();
        final aliceSigningPublicKey = await aliceKeyPair.signingKeyPair.extractPublicKey();
        final aliceEncryptionPublicKey = await aliceKeyPair.encryptionKeyPair.extractPublicKey();
        
        final ed25519 = Ed25519();
        final x25519 = X25519();
        final bobEncryptionKeyPair = await x25519.newKeyPair();
        final bobEncryptionPublicKey = await bobEncryptionKeyPair.extractPublicKey();
        
        const messageCount = 50;
        const testMessage = 'Performance test message';
        
        final stopwatch = Stopwatch()..start();
        
        for (int i = 0; i < messageCount; i++) {
          final encrypted = await CryptoEngine.encryptMessage(
            '$testMessage $i',
            bobEncryptionPublicKey,
          );
          
          final decrypted = await CryptoEngine.decryptMessage(
            encrypted,
            aliceEncryptionPublicKey,
            aliceSigningPublicKey,
          );
          
          expect(decrypted, equals('$testMessage $i'));
        }
        
        stopwatch.stop();
        
        // Should complete within reasonable time
        expect(stopwatch.elapsedMilliseconds, lessThan(30000)); // 30 seconds
        
        final avgTimePerMessage = stopwatch.elapsedMilliseconds / messageCount;
        print('Average time per encrypt/decrypt cycle: ${avgTimePerMessage.toStringAsFixed(2)}ms');
      });

      test('should handle concurrent message processing', () async {
        final aliceKeyPair = await KeyManager.generateUserKeys();
        final aliceSigningPublicKey = await aliceKeyPair.signingKeyPair.extractPublicKey();
        final aliceEncryptionPublicKey = await aliceKeyPair.encryptionKeyPair.extractPublicKey();
        
        final ed25519 = Ed25519();
        final x25519 = X25519();
        final bobEncryptionKeyPair = await x25519.newKeyPair();
        final bobEncryptionPublicKey = await bobEncryptionKeyPair.extractPublicKey();
        
        const concurrentMessages = 10;
        const testMessage = 'Concurrent test message';
        
        // Create concurrent encryption tasks
        final encryptionFutures = List.generate(concurrentMessages, (i) {
          return CryptoEngine.encryptMessage(
            '$testMessage $i',
            bobEncryptionPublicKey,
          );
        });
        
        final encryptedMessages = await Future.wait(encryptionFutures);
        expect(encryptedMessages.length, equals(concurrentMessages));
        
        // Create concurrent decryption tasks
        final decryptionFutures = encryptedMessages.map((encrypted) {
          return CryptoEngine.decryptMessage(
            encrypted,
            aliceEncryptionPublicKey,
            aliceSigningPublicKey,
          );
        }).toList();
        
        final decryptedMessages = await Future.wait(decryptionFutures);
        expect(decryptedMessages.length, equals(concurrentMessages));
        
        // Verify all messages were processed correctly
        for (int i = 0; i < concurrentMessages; i++) {
          expect(decryptedMessages[i], equals('$testMessage $i'));
        }
      });
    });

    group('Security Integration Tests', () {
      test('should maintain security properties in complete flow', () async {
        // Generate keys for Alice and Bob
        final aliceKeyPair = await KeyManager.generateUserKeys();
        final aliceSigningPublicKey = await aliceKeyPair.signingKeyPair.extractPublicKey();
        final aliceEncryptionPublicKey = await aliceKeyPair.encryptionKeyPair.extractPublicKey();
        
        final ed25519 = Ed25519();
        final x25519 = X25519();
        final bobEncryptionKeyPair = await x25519.newKeyPair();
        final bobEncryptionPublicKey = await bobEncryptionKeyPair.extractPublicKey();
        
        // Generate keys for Eve (attacker)
        final eveSigningKeyPair = await ed25519.newKeyPair();
        final eveEncryptionKeyPair = await x25519.newKeyPair();
        final eveSigningPublicKey = await eveSigningKeyPair.extractPublicKey();
        final eveEncryptionPublicKey = await eveEncryptionKeyPair.extractPublicKey();
        
        const secretMessage = 'This is a secret message that Eve should not be able to read';
        
        // Alice encrypts message for Bob
        final encryptedMessage = await CryptoEngine.encryptMessage(
          secretMessage,
          bobEncryptionPublicKey,
        );
        
        // Eve should not be able to decrypt the message with her keys
        expect(
          () async => await CryptoEngine.decryptMessage(
            encryptedMessage,
            eveEncryptionPublicKey, // Wrong key
            eveSigningPublicKey,    // Wrong key
          ),
          throwsException,
        );
        
        // Eve should not be able to decrypt with mixed keys either
        expect(
          () async => await CryptoEngine.decryptMessage(
            encryptedMessage,
            aliceEncryptionPublicKey, // Correct key
            eveSigningPublicKey,      // Wrong signature key
          ),
          throwsException,
        );
        
        // Only Bob with correct keys should be able to decrypt
        final decryptedMessage = await CryptoEngine.decryptMessage(
          encryptedMessage,
          aliceEncryptionPublicKey,
          aliceSigningPublicKey,
        );
        
        expect(decryptedMessage, equals(secretMessage));
      });

      test('should prevent replay attacks with nonce uniqueness', () async {
        final aliceKeyPair = await KeyManager.generateUserKeys();
        final ed25519 = Ed25519();
        final x25519 = X25519();
        final bobEncryptionKeyPair = await x25519.newKeyPair();
        final bobEncryptionPublicKey = await bobEncryptionKeyPair.extractPublicKey();
        
        const message = 'Message for nonce uniqueness test';
        
        // Encrypt the same message multiple times
        final encryptedMessages = <EncryptedMessage>[];
        for (int i = 0; i < 10; i++) {
          final encrypted = await CryptoEngine.encryptMessage(
            message,
            bobEncryptionPublicKey,
          );
          encryptedMessages.add(encrypted);
        }
        
        // All nonces should be unique
        final nonces = encryptedMessages.map((m) => m.nonce).toSet();
        expect(nonces.length, equals(encryptedMessages.length));
        
        // All encrypted data should be different (due to unique nonces)
        final encryptedData = encryptedMessages.map((m) => m.encryptedData).toSet();
        expect(encryptedData.length, equals(encryptedMessages.length));
        
        // All signatures should be different (signing encrypted data with unique nonces)
        final signatures = encryptedMessages.map((m) => m.signature).toSet();
        expect(signatures.length, equals(encryptedMessages.length));
      });
    });
  });
}