import 'package:flutter_test/flutter_test.dart';
import 'package:enigmo_app/services/crypto_engine.dart';
import 'package:enigmo_app/services/key_manager.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';
import 'dart:typed_data';

/// Mock implementation of FlutterSecureStorage for testing
class MockFlutterSecureStorage {
  final Map<String, String> _storage = {};

  Future<String?> read({required String key}) async {
    return _storage[key];
  }

  Future<void> write({required String key, required String value}) async {
    _storage[key] = value;
  }

  Future<void> delete({required String key}) async {
    _storage.remove(key);
  }

  Future<void> deleteAll() async {
    _storage.clear();
  }
}

void main() {
  group('CryptoEngine Comprehensive Tests', () {
    late SimpleKeyPair alice_signingKeyPair;
    late SimpleKeyPair alice_encryptionKeyPair;
    late SimpleKeyPair bob_signingKeyPair;
    late SimpleKeyPair bob_encryptionKeyPair;
    
    late SimplePublicKey alice_signingPublicKey;
    late SimplePublicKey alice_encryptionPublicKey;
    late SimplePublicKey bob_signingPublicKey;
    late SimplePublicKey bob_encryptionPublicKey;

    setUpAll(() async {
      // Create test keys for Alice and Bob
      final ed25519 = Ed25519();
      final x25519 = X25519();
      
      // Alice's keys
      alice_signingKeyPair = await ed25519.newKeyPair();
      alice_encryptionKeyPair = await x25519.newKeyPair();
      alice_signingPublicKey = await alice_signingKeyPair.extractPublicKey();
      alice_encryptionPublicKey = await alice_encryptionKeyPair.extractPublicKey();
      
      // Bob's keys
      bob_signingKeyPair = await ed25519.newKeyPair();
      bob_encryptionKeyPair = await x25519.newKeyPair();
      bob_signingPublicKey = await bob_signingKeyPair.extractPublicKey();
      bob_encryptionPublicKey = await bob_encryptionKeyPair.extractPublicKey();
    });

    group('EncryptedMessage Serialization', () {
      test('should properly serialize and deserialize EncryptedMessage', () {
        final originalMessage = EncryptedMessage(
          encryptedData: 'dGVzdF9lbmNyeXB0ZWRfZGF0YQ==',
          nonce: 'dGVzdF9ub25jZQ==',
          mac: 'dGVzdF9tYWM=',
          signature: 'dGVzdF9zaWduYXR1cmU=',
        );

        final json = originalMessage.toJson();
        final deserializedMessage = EncryptedMessage.fromJson(json);

        expect(deserializedMessage.encryptedData, equals(originalMessage.encryptedData));
        expect(deserializedMessage.nonce, equals(originalMessage.nonce));
        expect(deserializedMessage.mac, equals(originalMessage.mac));
        expect(deserializedMessage.signature, equals(originalMessage.signature));
      });

      test('should handle empty MAC field in deserialization', () {
        final json = {
          'encryptedData': 'dGVzdF9lbmNyeXB0ZWRfZGF0YQ==',
          'nonce': 'dGVzdF9ub25jZQ==',
          'signature': 'dGVzdF9zaWduYXR1cmU=',
          // MAC field intentionally omitted
        };

        final message = EncryptedMessage.fromJson(json);
        expect(message.mac, equals(''));
      });
    });

    group('Digital Signatures', () {
      test('should successfully create and verify Ed25519 signatures', () async {
        final testData = 'Test message for signing verification';
        final dataBytes = utf8.encode(testData);
        
        // Create signature
        final ed25519 = Ed25519();
        final signature = await ed25519.sign(dataBytes, keyPair: alice_signingKeyPair);
        final signatureString = base64Encode(signature.bytes);

        // Verify signature
        final isValid = await CryptoEngine.verifySignature(
          testData,
          signatureString,
          alice_signingPublicKey,
        );

        expect(isValid, isTrue);
        expect(signature.bytes.length, equals(64)); // Ed25519 signatures are 64 bytes
      });

      test('should reject tampered data', () async {
        final originalData = 'Original message content';
        final tamperedData = 'Tampered message content';
        
        // Create signature for original data
        final ed25519 = Ed25519();
        final dataBytes = utf8.encode(originalData);
        final signature = await ed25519.sign(dataBytes, keyPair: alice_signingKeyPair);
        final signatureString = base64Encode(signature.bytes);

        // Verify against tampered data should fail
        final isValid = await CryptoEngine.verifySignature(
          tamperedData,
          signatureString,
          alice_signingPublicKey,
        );

        expect(isValid, isFalse);
      });

      test('should reject invalid signature format', () async {
        final testData = 'Test data';
        final invalidSignature = 'not_a_valid_base64_signature';

        final isValid = await CryptoEngine.verifySignature(
          testData,
          invalidSignature,
          alice_signingPublicKey,
        );

        expect(isValid, isFalse);
      });

      test('should reject signature from wrong key', () async {
        final testData = 'Test message for wrong key test';
        
        // Create signature with Alice's key
        final ed25519 = Ed25519();
        final dataBytes = utf8.encode(testData);
        final signature = await ed25519.sign(dataBytes, keyPair: alice_signingKeyPair);
        final signatureString = base64Encode(signature.bytes);

        // Try to verify with Bob's public key (should fail)
        final isValid = await CryptoEngine.verifySignature(
          testData,
          signatureString,
          bob_signingPublicKey,
        );

        expect(isValid, isFalse);
      });

      test('should handle empty data signing', () async {
        expect(
          () async => await CryptoEngine.signData(''),
          throwsException,
        );
      });
    });

    group('End-to-End Message Encryption', () {
      test('should successfully encrypt and decrypt a complete message flow', () async {
        final originalMessage = 'Secret message: Hello Bob! 🔐';
        
        // Alice encrypts message for Bob
        final sharedSecret_alice = await X25519().sharedSecretKey(
          keyPair: alice_encryptionKeyPair,
          remotePublicKey: bob_encryptionPublicKey,
        );
        
        final sharedSecretBytes_alice = await sharedSecret_alice.extractBytes();
        final secretKey_alice = SecretKey(sharedSecretBytes_alice);
        
        final chacha20 = Chacha20.poly1305Aead();
        final messageBytes = utf8.encode(originalMessage);
        final secretBox = await chacha20.encrypt(messageBytes, secretKey: secretKey_alice);
        
        // Alice signs the encrypted data
        final signature = await Ed25519().sign(secretBox.cipherText, keyPair: alice_signingKeyPair);
        
        final encryptedMessage = EncryptedMessage(
          encryptedData: base64Encode(secretBox.cipherText),
          nonce: base64Encode(secretBox.nonce),
          mac: base64Encode(secretBox.mac.bytes),
          signature: base64Encode(signature.bytes),
        );

        // Bob decrypts the message
        final sharedSecret_bob = await X25519().sharedSecretKey(
          keyPair: bob_encryptionKeyPair,
          remotePublicKey: alice_encryptionPublicKey,
        );
        
        final sharedSecretBytes_bob = await sharedSecret_bob.extractBytes();
        final secretKey_bob = SecretKey(sharedSecretBytes_bob);
        
        // Verify signature first
        final encryptedData = base64Decode(encryptedMessage.encryptedData);
        final signatureObj = Signature(
          base64Decode(encryptedMessage.signature),
          publicKey: alice_signingPublicKey,
        );
        
        final isValidSignature = await Ed25519().verify(
          encryptedData,
          signature: signatureObj,
        );
        
        expect(isValidSignature, isTrue);
        
        // Decrypt
        final bobSecretBox = SecretBox(
          encryptedData,
          nonce: base64Decode(encryptedMessage.nonce),
          mac: Mac(base64Decode(encryptedMessage.mac)),
        );
        
        final decryptedBytes = await chacha20.decrypt(
          bobSecretBox,
          secretKey: secretKey_bob,
        );
        
        final decryptedMessage = utf8.decode(decryptedBytes);
        
        expect(decryptedMessage, equals(originalMessage));
      });

      test('should fail decryption with wrong encryption key', () async {
        final originalMessage = 'Message encrypted with wrong key test';
        
        // Alice encrypts message for Bob
        final sharedSecret = await X25519().sharedSecretKey(
          keyPair: alice_encryptionKeyPair,
          remotePublicKey: bob_encryptionPublicKey,
        );
        
        final sharedSecretBytes = await sharedSecret.extractBytes();
        final secretKey = SecretKey(sharedSecretBytes);
        
        final chacha20 = Chacha20.poly1305Aead();
        final messageBytes = utf8.encode(originalMessage);
        final secretBox = await chacha20.encrypt(messageBytes, secretKey: secretKey);
        
        // Alice signs the encrypted data
        final signature = await Ed25519().sign(secretBox.cipherText, keyPair: alice_signingKeyPair);
        
        final encryptedMessage = EncryptedMessage(
          encryptedData: base64Encode(secretBox.cipherText),
          nonce: base64Encode(secretBox.nonce),
          mac: base64Encode(secretBox.mac.bytes),
          signature: base64Encode(signature.bytes),
        );

        // Try to decrypt with Alice's own key (wrong key pair)
        final wrongSharedSecret = await X25519().sharedSecretKey(
          keyPair: alice_encryptionKeyPair,
          remotePublicKey: alice_encryptionPublicKey, // Wrong key!
        );
        
        final wrongSharedSecretBytes = await wrongSharedSecret.extractBytes();
        final wrongSecretKey = SecretKey(wrongSharedSecretBytes);
        
        final encryptedData = base64Decode(encryptedMessage.encryptedData);
        final wrongSecretBox = SecretBox(
          encryptedData,
          nonce: base64Decode(encryptedMessage.nonce),
          mac: Mac(base64Decode(encryptedMessage.mac)),
        );
        
        // Decryption should fail
        expect(
          () async => await chacha20.decrypt(wrongSecretBox, secretKey: wrongSecretKey),
          throwsException,
        );
      });

      test('should detect MAC tampering', () async {
        final originalMessage = 'Message with tampered MAC test';
        
        // Create a valid encrypted message
        final sharedSecret = await X25519().sharedSecretKey(
          keyPair: alice_encryptionKeyPair,
          remotePublicKey: bob_encryptionPublicKey,
        );
        
        final sharedSecretBytes = await sharedSecret.extractBytes();
        final secretKey = SecretKey(sharedSecretBytes);
        
        final chacha20 = Chacha20.poly1305Aead();
        final messageBytes = utf8.encode(originalMessage);
        final secretBox = await chacha20.encrypt(messageBytes, secretKey: secretKey);
        
        final signature = await Ed25519().sign(secretBox.cipherText, keyPair: alice_signingKeyPair);
        
        // Tamper with MAC
        final tamperedMac = List<int>.from(secretBox.mac.bytes);
        tamperedMac[0] = tamperedMac[0] ^ 1; // Flip one bit
        
        final encryptedMessage = EncryptedMessage(
          encryptedData: base64Encode(secretBox.cipherText),
          nonce: base64Encode(secretBox.nonce),
          mac: base64Encode(tamperedMac),
          signature: base64Encode(signature.bytes),
        );

        // Decryption should fail due to MAC mismatch
        final wrongSecretBox = SecretBox(
          base64Decode(encryptedMessage.encryptedData),
          nonce: base64Decode(encryptedMessage.nonce),
          mac: Mac(base64Decode(encryptedMessage.mac)),
        );
        
        expect(
          () async => await chacha20.decrypt(wrongSecretBox, secretKey: secretKey),
          throwsException,
        );
      });
    });

    group('Cryptographic Utilities', () {
      test('should generate secure random nonces', () {
        final nonce1 = CryptoEngine.generateNonce(16);
        final nonce2 = CryptoEngine.generateNonce(16);
        final nonce3 = CryptoEngine.generateNonce(24);

        expect(nonce1.length, equals(16));
        expect(nonce2.length, equals(16));
        expect(nonce3.length, equals(24));
        
        // Nonces should be different
        expect(nonce1, isNot(equals(nonce2)));
        
        // Default nonce length should be 12
        final defaultNonce = CryptoEngine.generateNonce();
        expect(defaultNonce.length, equals(12));
      });

      test('should create deterministic SHA-256 hashes', () async {
        final testData = 'Test data for hashing 📊';
        
        final hash1 = await CryptoEngine.hashData(testData);
        final hash2 = await CryptoEngine.hashData(testData);
        
        expect(hash1, equals(hash2)); // Should be deterministic
        expect(hash1, isNotEmpty);
        
        // Different data should produce different hashes
        final differentHash = await CryptoEngine.hashData('Different data');
        expect(hash1, isNot(equals(differentHash)));
      });

      test('should verify data integrity correctly', () async {
        final testData = 'Data integrity test content';
        
        final hash = await CryptoEngine.hashData(testData);
        
        // Valid data should pass
        final isValid = await CryptoEngine.verifyDataIntegrity(testData, hash);
        expect(isValid, isTrue);
        
        // Modified data should fail
        final isInvalid = await CryptoEngine.verifyDataIntegrity('Modified content', hash);
        expect(isInvalid, isFalse);
      });

      test('should handle empty string hashing', () async {
        final hash = await CryptoEngine.hashData('');
        expect(hash, isNotEmpty);
        
        final verification = await CryptoEngine.verifyDataIntegrity('', hash);
        expect(verification, isTrue);
      });

      test('should handle Unicode data correctly', () async {
        final unicodeData = 'Unicode test: 🔐🌟🚀 العربية русский 中文';
        
        final hash = await CryptoEngine.hashData(unicodeData);
        expect(hash, isNotEmpty);
        
        final verification = await CryptoEngine.verifyDataIntegrity(unicodeData, hash);
        expect(verification, isTrue);
      });
    });

    group('Input Validation and Error Handling', () {
      test('should validate message encryption inputs', () async {
        // Test empty message
        expect(
          () async => await CryptoEngine.encryptMessage('', bob_encryptionPublicKey),
          throwsException,
        );
        
        // Test invalid public key
        final invalidKey = SimplePublicKey(Uint8List(0), type: KeyPairType.x25519);
        expect(
          () async => await CryptoEngine.encryptMessage('test', invalidKey),
          throwsException,
        );
      });

      test('should validate signature verification inputs', () async {
        expect(
          () async => await CryptoEngine.verifySignature('', 'signature', alice_signingPublicKey),
          returnsNormally, // Empty data should not throw, but should return false
        );

        final result = await CryptoEngine.verifySignature('', 'invalid_sig', alice_signingPublicKey);
        expect(result, isFalse);
      });

      test('should handle malformed encrypted message data', () {
        // Test with invalid base64 data
        final malformedMessage = EncryptedMessage(
          encryptedData: 'invalid_base64!@#',
          nonce: 'invalid_nonce!@#',
          mac: 'invalid_mac!@#',
          signature: 'invalid_signature!@#',
        );

        expect(
          () async => await CryptoEngine.decryptMessage(
            malformedMessage,
            alice_encryptionPublicKey,
            alice_signingPublicKey,
          ),
          throwsException,
        );
      });

      test('should handle missing message fields', () {
        final incompleteMessage = EncryptedMessage(
          encryptedData: '',
          nonce: 'dGVzdF9ub25jZQ==',
          mac: 'dGVzdF9tYWM=',
          signature: 'dGVzdF9zaWduYXR1cmU=',
        );

        expect(
          () async => await CryptoEngine.decryptMessage(
            incompleteMessage,
            alice_encryptionPublicKey,
            alice_signingPublicKey,
          ),
          throwsException,
        );
      });
    });

    group('Performance and Edge Cases', () {
      test('should handle large messages efficiently', () async {
        // Create a large message (1MB)
        final largeMessage = 'x' * (1024 * 1024);
        
        final stopwatch = Stopwatch()..start();
        
        final sharedSecret = await X25519().sharedSecretKey(
          keyPair: alice_encryptionKeyPair,
          remotePublicKey: bob_encryptionPublicKey,
        );
        
        final sharedSecretBytes = await sharedSecret.extractBytes();
        final secretKey = SecretKey(sharedSecretBytes);
        
        final chacha20 = Chacha20.poly1305Aead();
        final messageBytes = utf8.encode(largeMessage);
        final secretBox = await chacha20.encrypt(messageBytes, secretKey: secretKey);
        
        stopwatch.stop();
        
        expect(secretBox.cipherText.length, greaterThan(1024 * 1024));
        expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // Should complete within 5 seconds
      });

      test('should handle repeated encryption/decryption cycles', () async {
        final testMessage = 'Repeated operation test message';
        
        for (int i = 0; i < 10; i++) {
          final sharedSecret = await X25519().sharedSecretKey(
            keyPair: alice_encryptionKeyPair,
            remotePublicKey: bob_encryptionPublicKey,
          );
          
          final sharedSecretBytes = await sharedSecret.extractBytes();
          final secretKey = SecretKey(sharedSecretBytes);
          
          final chacha20 = Chacha20.poly1305Aead();
          final messageBytes = utf8.encode(testMessage);
          final secretBox = await chacha20.encrypt(messageBytes, secretKey: secretKey);
          
          final decryptedBytes = await chacha20.decrypt(secretBox, secretKey: secretKey);
          final decryptedMessage = utf8.decode(decryptedBytes);
          
          expect(decryptedMessage, equals(testMessage));
        }
      });

      test('should maintain cryptographic properties with edge case strings', () async {
        final edgeCases = [
          '',  // Empty string - should be handled by validation
          ' ',  // Single space
          '\n\r\t',  // Whitespace characters
          '🔐🚀📱💻🌟',  // Emojis
          'a' * 10000,  // Very long string
          '\x00\x01\x02\x03',  // Control characters
        ];

        for (final testCase in edgeCases) {
          if (testCase.isEmpty) continue; // Skip empty string as it's validated

          final hash1 = await CryptoEngine.hashData(testCase);
          final hash2 = await CryptoEngine.hashData(testCase);
          
          expect(hash1, equals(hash2), reason: 'Hash should be deterministic for: "$testCase"');
          expect(hash1, isNotEmpty, reason: 'Hash should not be empty for: "$testCase"');
        }
      });
    });
  });
}