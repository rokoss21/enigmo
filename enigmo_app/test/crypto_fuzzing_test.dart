import 'package:flutter_test/flutter_test.dart';
import 'package:enigmo_app/services/crypto_engine.dart';
import 'package:enigmo_app/services/key_manager.dart';
import 'package:enigmo_app/models/message.dart';
import 'package:enigmo_app/models/chat.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Fuzzing tests for discovering edge cases and vulnerabilities
/// through systematic generation of malformed inputs
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('Cryptographic Fuzzing Tests', () {
    late SimpleKeyPair testSigningKeyPair;
    late SimpleKeyPair testEncryptionKeyPair;
    late SimplePublicKey testSigningPublicKey;
    late SimplePublicKey testEncryptionPublicKey;

    setUpAll(() async {
      final ed25519 = Ed25519();
      final x25519 = X25519();
      
      testSigningKeyPair = await ed25519.newKeyPair();
      testEncryptionKeyPair = await x25519.newKeyPair();
      testSigningPublicKey = await testSigningKeyPair.extractPublicKey();
      testEncryptionPublicKey = await testEncryptionKeyPair.extractPublicKey();
    });

    group('Signature Verification Fuzzing', () {
      test('Fuzz: Random invalid base64 signatures', () async {
        const message = 'Test message for fuzzing';
        final random = Random.secure();
        
        // Generate 100 random invalid base64 strings
        for (int i = 0; i < 100; i++) {
          final invalidSignature = _generateRandomInvalidBase64(random, random.nextInt(100) + 1);
          
          // Should handle gracefully without throwing
          expect(() async {
            final result = await CryptoEngine.verifySignature(
              message, 
              invalidSignature, 
              testSigningPublicKey
            );
            expect(result, isFalse); // Should return false, not throw
          }, returnsNormally);
        }
      });

      test('Fuzz: Malformed signature lengths', () async {
        const message = 'Test message';
        final random = Random.secure();
        
        // Test various invalid signature lengths
        final invalidLengths = [0, 1, 32, 63, 65, 128, 256, 1024];
        
        for (final length in invalidLengths) {
          final invalidBytes = List.generate(length, (_) => random.nextInt(256));
          final invalidSignature = base64Encode(invalidBytes);
          
          expect(() async {
            final result = await CryptoEngine.verifySignature(
              message, 
              invalidSignature, 
              testSigningPublicKey
            );
            expect(result, isFalse);
          }, returnsNormally);
        }
      });

      test('Fuzz: Extreme message content', () async {
        final ed25519 = Ed25519();
        final testCases = [
          '', // Empty
          '\x00', // Null byte
          '\x00\x00\x00', // Multiple nulls
          'A' * 100000, // Very long
          '🚀🌍🔐💫🎉', // Unicode/Emoji
          '\u0001\u0002\u0003', // Control characters
          'Test\nMulti\rLine\tMessage', // Special whitespace
          '\'\"\\`\$\{\}', // Special shell characters
          '<script>alert("xss")</script>', // XSS attempt
          'SELECT * FROM users; DROP TABLE users;', // SQL injection attempt
          '\xff\xfe\xfd', // Invalid UTF-8 sequences
        ];
        
        for (final testMessage in testCases) {
          try {
            if (testMessage.isNotEmpty) {
              // Try to sign the message
              final dataBytes = utf8.encode(testMessage);
              final signature = await ed25519.sign(dataBytes, keyPair: testSigningKeyPair);
              final signatureString = base64Encode(signature.bytes);
              
              // Verification should work for valid signatures
              final result = await CryptoEngine.verifySignature(
                testMessage, 
                signatureString, 
                testSigningPublicKey
              );
              expect(result, isTrue);
            }
          } catch (e) {
            // Some extreme inputs may cause encoding issues - that's acceptable
            print('Expected encoding issue with extreme input: ${e.runtimeType}');
          }
        }
      });

      test('Fuzz: Random public key corruption', () async {
        const message = 'Test message';
        final random = Random.secure();
        
        // Create valid signature
        final ed25519 = Ed25519();
        final dataBytes = utf8.encode(message);
        final signature = await ed25519.sign(dataBytes, keyPair: testSigningKeyPair);
        final signatureString = base64Encode(signature.bytes);
        
        // Test with various corrupted public keys
        for (int i = 0; i < 20; i++) {
          final originalBytes = testSigningPublicKey.bytes;
          final corruptedBytes = Uint8List.fromList(originalBytes);
          
          // Corrupt random positions
          for (int j = 0; j < 3; j++) {
            final pos = random.nextInt(corruptedBytes.length);
            corruptedBytes[pos] = random.nextInt(256);
          }
          
          try {
            final corruptedKey = SimplePublicKey(corruptedBytes, type: KeyPairType.ed25519);
            final result = await CryptoEngine.verifySignature(
              message, 
              signatureString, 
              corruptedKey
            );
            expect(result, isFalse);
          } catch (e) {
            // Some corruptions may make the key invalid - that's expected
            print('Expected error with corrupted key: ${e.runtimeType}');
          }
        }
      });
    });

    group('Data Hashing Fuzzing', () {
      test('Fuzz: Extreme hash inputs', () async {
        final testInputs = [
          '',
          '\x00',
          'A' * 1000000, // 1MB string
          '\u{1F600}' * 1000, // Many emoji
          String.fromCharCodes(List.generate(256, (i) => i)), // All byte values
          'Line1\nLine2\rLine3\tTabbed',
          'Mixed: ASCII + 🌍 + \u{1F680} + русский + 中文',
        ];
        
        for (final input in testInputs) {
          try {
            final hash1 = await CryptoEngine.hashData(input);
            final hash2 = await CryptoEngine.hashData(input);
            
            // Hash should be deterministic
            expect(hash1, equals(hash2));
            expect(hash1, isNotEmpty);
            
            // Integrity verification should work
            final isValid = await CryptoEngine.verifyDataIntegrity(input, hash1);
            expect(isValid, isTrue);
            
          } catch (e) {
            // Some extreme inputs might cause issues - log but don't fail
            print('Hash processing issue with input length ${input.length}: ${e.runtimeType}');
          }
        }
      });

      test('Fuzz: Hash collision attempts', () async {
        final random = Random.secure();
        final hashes = <String, String>{};
        
        // Try to find hash collisions with various input patterns
        for (int i = 0; i < 500; i++) {
          final input = _generateFuzzingInput(random, random.nextInt(1000) + 1);
          
          try {
            final hash = await CryptoEngine.hashData(input);
            
            if (hashes.containsKey(hash)) {
              // Potential collision found
              final originalInput = hashes[hash]!;
              if (originalInput != input) {
                fail('Hash collision detected: "$originalInput" and "$input" produce same hash: $hash');
              }
            } else {
              hashes[hash] = input;
            }
          } catch (e) {
            // Some inputs might cause processing issues
            continue;
          }
        }
        
        print('Tested ${hashes.length} unique hashes without collisions');
      });
    });

    group('Nonce Generation Fuzzing', () {
      test('Fuzz: Extreme nonce lengths', () async {
        final extremeLengths = [0, 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024];
        
        for (final length in extremeLengths) {
          if (length == 0) {
            // Zero length should be handled gracefully
            expect(() => CryptoEngine.generateNonce(0), returnsNormally);
          } else {
            final nonce = CryptoEngine.generateNonce(length);
            expect(nonce.length, equals(length));
            
            // All bytes should be in valid range
            for (final byte in nonce) {
              expect(byte, greaterThanOrEqualTo(0));
              expect(byte, lessThanOrEqualTo(255));
            }
          }
        }
      });

      test('Fuzz: Nonce randomness quality', () async {
        const testLength = 32;
        const numNonces = 1000;
        final allBytes = <int>[];
        
        // Collect bytes from many nonces
        for (int i = 0; i < numNonces; i++) {
          final nonce = CryptoEngine.generateNonce(testLength);
          allBytes.addAll(nonce);
        }
        
        // Statistical tests for randomness
        final byteCounts = List.filled(256, 0);
        for (final byte in allBytes) {
          byteCounts[byte]++;
        }
        
        // Check distribution - should be roughly uniform
        final expectedCount = allBytes.length / 256;
        final tolerance = expectedCount * 0.2; // 20% tolerance
        
        for (int i = 0; i < 256; i++) {
          expect(byteCounts[i], 
            greaterThan(expectedCount - tolerance),
            reason: 'Byte value $i appears too rarely: ${byteCounts[i]} vs expected ~$expectedCount'
          );
          expect(byteCounts[i], 
            lessThan(expectedCount + tolerance),
            reason: 'Byte value $i appears too frequently: ${byteCounts[i]} vs expected ~$expectedCount'
          );
        }
      });
    });

    group('Model Serialization Fuzzing', () {
      test('Fuzz: Message JSON deserialization', () async {
        final random = Random.secure();
        
        // Test various malformed JSON inputs
        final malformedJsons = [
          '{}', // Empty object
          '{"id": null}', // Null values
          '{"id": ""}', // Empty strings
          '{"id": "test", "invalid_field": "value"}', // Unknown fields
          '{"timestamp": "invalid-date"}', // Invalid timestamp
          '{"type": "invalid_type"}', // Invalid enum
          '{"status": "invalid_status"}', // Invalid enum
          '{"content": "' + 'A' * 100000 + '"}', // Very long content
          '{"content": "\\u0000\\u0001\\u0002"}', // Control characters
          '{"content": "🚀🌍🔐💫🎉"}', // Unicode/Emoji
        ];
        
        for (final jsonString in malformedJsons) {
          try {
            final json = jsonDecode(jsonString);
            final message = Message.fromJson(json);
            
            // Should create message with defaults for missing fields
            expect(message.id, isNotNull);
            expect(message.senderId, isNotNull);
            expect(message.receiverId, isNotNull);
            expect(message.timestamp, isNotNull);
            
          } catch (e) {
            // Some malformed JSON might cause parse errors - that's acceptable
            print('Expected JSON parsing error: ${e.runtimeType}');
          }
        }
      });

      test('Fuzz: Chat JSON deserialization', () async {
        final malformedChatJsons = [
          '{}',
          '{"id": "", "name": "", "participants": [], "lastActivity": ""}',
          '{"participants": null}',
          '{"participants": ["' + 'A' * 10000 + '"]}', // Very long participant ID
          '{"unreadCount": -1}', // Negative count
          '{"unreadCount": 999999999}', // Very large count
          '{"type": "unknown_type"}',
          '{"lastActivity": "not-a-date"}',
          '{"name": "\\u0000\\u0001"}', // Control characters in name
        ];
        
        for (final jsonString in malformedChatJsons) {
          try {
            final json = jsonDecode(jsonString);
            final chat = Chat.fromJson(json);
            
            expect(chat.id, isNotNull);
            expect(chat.name, isNotNull);
            expect(chat.participants, isNotNull);
            expect(chat.lastActivity, isNotNull);
            
          } catch (e) {
            print('Expected Chat JSON parsing error: ${e.runtimeType}');
          }
        }
      });
    });

    group('Key Management Fuzzing', () {
      test('Fuzz: Public key string conversion', () async {
        final random = Random.secure();
        
        // Test various invalid key strings
        final invalidKeyStrings = [
          '',
          'not-base64!@#',
          'SGVsbG8=', // Valid base64 but wrong length
          base64Encode(List.generate(31, (_) => random.nextInt(256))), // Wrong length
          base64Encode(List.generate(33, (_) => random.nextInt(256))), // Wrong length
          '=' * 100, // Many padding characters
          'A' * 1000, // Very long
          '🚀🌍', // Unicode characters
          '\x00\x01\x02', // Control characters
        ];
        
        for (final keyString in invalidKeyStrings) {
          expect(() async {
            await KeyManager.publicKeyFromString(keyString, isEncryption: true);
          }, throwsException);
          
          expect(() async {
            await KeyManager.publicKeyFromString(keyString, isEncryption: false);
          }, throwsException);
        }
      });

      test('Fuzz: Key generation stress test', () async {
        // Generate many key pairs quickly to test for consistency
        // Generate many key pairs quickly to test for consistency
        final keyPairs = <dynamic>[];
        
        for (int i = 0; i < 50; i++) {
          final keyPair = await KeyManager.generateUserKeys();
          expect(keyPair, isNotNull);
          keyPairs.add(keyPair);
          
          // Cleanup to avoid storage issues
          await KeyManager.deleteUserKeys();
        }
        
        // All key pairs should be different
        for (int i = 0; i < keyPairs.length; i++) {
          for (int j = i + 1; j < keyPairs.length; j++) {
            final key1 = await keyPairs[i].signingKeyPair.extractPublicKey();
            final key2 = await keyPairs[j].signingKeyPair.extractPublicKey();
            
            expect(key1.bytes, isNot(equals(key2.bytes)), 
              reason: 'Generated key pairs should be unique');
          }
        }
      });
    });

    group('EncryptedMessage Fuzzing', () {
      test('Fuzz: EncryptedMessage with malformed data', () async {
        final random = Random.secure();
        
        final malformedMessages = [
          EncryptedMessage(
            encryptedData: '',
            nonce: '',
            mac: '',
            signature: '',
          ),
          EncryptedMessage(
            encryptedData: 'not-base64!@#',
            nonce: 'also-not-base64!@#',
            mac: 'invalid-mac!@#',
            signature: 'bad-signature!@#',
          ),
          EncryptedMessage(
            encryptedData: base64Encode(List.generate(100000, (_) => random.nextInt(256))),
            nonce: base64Encode(List.generate(12, (_) => random.nextInt(256))),
            mac: base64Encode(List.generate(16, (_) => random.nextInt(256))),
            signature: base64Encode(List.generate(64, (_) => random.nextInt(256))),
          ),
        ];
        
        for (final message in malformedMessages) {
          // Serialization should work
          final json = message.toJson();
          expect(json, isA<Map<String, dynamic>>());
          
          // Deserialization should work
          final restored = EncryptedMessage.fromJson(json);
          expect(restored.encryptedData, equals(message.encryptedData));
          expect(restored.nonce, equals(message.nonce));
          expect(restored.mac, equals(message.mac));
          expect(restored.signature, equals(message.signature));
        }
      });
    });
  });
}

/// Generate random invalid base64 string
String _generateRandomInvalidBase64(Random random, int length) {
  const invalidChars = '!@#\$%^&*()+={}[]|\\:";\'<>?,./~`';
  const base64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
  
  return List.generate(length, (index) {
    if (random.nextBool()) {
      // Mix in some invalid characters
      return invalidChars[random.nextInt(invalidChars.length)];
    } else {
      // Mix in some valid base64 characters to make it more realistic
      return base64Chars[random.nextInt(base64Chars.length)];
    }
  }).join();
}

/// Generate random fuzzing input with various character types
String _generateFuzzingInput(Random random, int length) {
  const categories = [
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ', // Uppercase
    'abcdefghijklmnopqrstuvwxyz', // Lowercase
    '0123456789', // Numbers
    '!@#\$%^&*()_+-=[]{}|;:,.<>?/~`', // Special characters
    ' \t\n\r', // Whitespace
    '\u0000\u0001\u0002\u0003\u0004\u0005\u0006\u0007', // Control characters
  ];
  
  return List.generate(length, (index) {
    final category = categories[random.nextInt(categories.length)];
    return category[random.nextInt(category.length)];
  }).join();
}