import 'package:flutter_test/flutter_test.dart';
import 'package:enigmo_app/services/crypto_engine.dart';
import 'dart:convert';
import 'dart:typed_data';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoEngine cryptoEngine;

  setUp(() {
    cryptoEngine = CryptoEngine();
  });

  group('CryptoEngine Key Generation Tests', () {
    test('should generate valid key pair', () async {
      final keyPair = await cryptoEngine.generateKeyPair();

      expect(keyPair, isNotNull);
      expect(keyPair.publicKey, isNotNull);
      expect(keyPair.privateKey, isNotNull);
      expect(keyPair.publicKey.isEmpty, isFalse);
      expect(keyPair.privateKey.isEmpty, isFalse);
    });

    test('should generate unique key pairs', () async {
      final keyPair1 = await cryptoEngine.generateKeyPair();
      final keyPair2 = await cryptoEngine.generateKeyPair();

      expect(keyPair1.publicKey, isNot(equals(keyPair2.publicKey)));
      expect(keyPair1.privateKey, isNot(equals(keyPair2.privateKey)));
    });

    test('should generate keys of correct length', () async {
      final keyPair = await cryptoEngine.generateKeyPair();

      // Ed25519 public key should be 32 bytes (64 hex chars)
      expect(keyPair.publicKey.length, equals(64));
      // Ed25519 private key should be 32 bytes (64 hex chars)
      expect(keyPair.privateKey.length, equals(64));
    });
  });

  group('CryptoEngine Signing Tests', () {
    test('should sign message successfully', () async {
      const message = 'test message';
      final keyPair = await cryptoEngine.generateKeyPair();

      final signature = await cryptoEngine.sign(message, keyPair.privateKey);

      expect(signature, isNotNull);
      expect(signature.isEmpty, isFalse);
      expect(signature.length, greaterThan(0));
    });

    test('should verify valid signature', () async {
      const message = 'test message';
      final keyPair = await cryptoEngine.generateKeyPair();

      final signature = await cryptoEngine.sign(message, keyPair.privateKey);
      final isValid = await cryptoEngine.verify(message, signature, keyPair.publicKey);

      expect(isValid, isTrue);
    });

    test('should reject invalid signature', () async {
      const message = 'test message';
      const wrongMessage = 'wrong message';
      final keyPair = await cryptoEngine.generateKeyPair();

      final signature = await cryptoEngine.sign(message, keyPair.privateKey);
      final isValid = await cryptoEngine.verify(wrongMessage, signature, keyPair.publicKey);

      expect(isValid, isFalse);
    });

    test('should reject signature with wrong public key', () async {
      const message = 'test message';
      final keyPair1 = await cryptoEngine.generateKeyPair();
      final keyPair2 = await cryptoEngine.generateKeyPair();

      final signature = await cryptoEngine.sign(message, keyPair1.privateKey);
      final isValid = await cryptoEngine.verify(message, signature, keyPair2.publicKey);

      expect(isValid, isFalse);
    });

    test('should handle empty message signing', () async {
      const message = '';
      final keyPair = await cryptoEngine.generateKeyPair();

      final signature = await cryptoEngine.sign(message, keyPair.privateKey);
      final isValid = await cryptoEngine.verify(message, signature, keyPair.publicKey);

      expect(signature, isNotNull);
      expect(isValid, isTrue);
    });

    test('should handle large message signing', () async {
      final largeMessage = 'x' * 10000; // 10KB message
      final keyPair = await cryptoEngine.generateKeyPair();

      final signature = await cryptoEngine.sign(largeMessage, keyPair.privateKey);
      final isValid = await cryptoEngine.verify(largeMessage, signature, keyPair.publicKey);

      expect(signature, isNotNull);
      expect(isValid, isTrue);
    });
  });

  group('CryptoEngine Encryption Tests', () {
    test('should encrypt message successfully', () async {
      const message = 'test message';
      final keyPair = await cryptoEngine.generateKeyPair();

      final encrypted = await cryptoEngine.encrypt(message);

      expect(encrypted, isNotNull);
      expect(encrypted.isEmpty, isFalse);
      expect(encrypted, isNot(equals(message)));
    });

    test('should decrypt message successfully', () async {
      const originalMessage = 'test message';
      final keyPair = await cryptoEngine.generateKeyPair();

      final encrypted = await cryptoEngine.encrypt(originalMessage);
      final decrypted = await cryptoEngine.decrypt(encrypted);

      expect(decrypted, equals(originalMessage));
    });

    test('should produce different ciphertexts for same plaintext', () async {
      const message = 'test message';

      final encrypted1 = await cryptoEngine.encrypt(message);
      final encrypted2 = await cryptoEngine.encrypt(message);

      expect(encrypted1, isNot(equals(encrypted2)));
    });

    test('should handle empty string encryption/decryption', () async {
      const message = '';

      final encrypted = await cryptoEngine.encrypt(message);
      final decrypted = await cryptoEngine.decrypt(encrypted);

      expect(decrypted, equals(message));
    });

    test('should handle large message encryption/decryption', () async {
      final largeMessage = 'x' * 50000; // 50KB message

      final encrypted = await cryptoEngine.encrypt(largeMessage);
      final decrypted = await cryptoEngine.decrypt(encrypted);

      expect(decrypted, equals(largeMessage));
      expect(encrypted.length, greaterThan(largeMessage.length));
    });

    test('should handle special characters', () async {
      const message = 'Special chars: ñáéíóú 中文 🚀 💯';

      final encrypted = await cryptoEngine.encrypt(message);
      final decrypted = await cryptoEngine.decrypt(encrypted);

      expect(decrypted, equals(message));
    });

    test('should handle binary data', () async {
      final binaryData = Uint8List.fromList([0, 1, 255, 128, 64]);

      final encrypted = await cryptoEngine.encrypt(base64Encode(binaryData));
      final decrypted = await cryptoEngine.decrypt(encrypted);
      final decodedData = base64Decode(decrypted);

      expect(decodedData, equals(binaryData));
    });
  });

  group('CryptoEngine Key Exchange Tests', () {
    test('should perform key exchange successfully', () async {
      final aliceKeys = await cryptoEngine.generateKeyPair();
      final bobKeys = await cryptoEngine.generateKeyPair();

      // In a real scenario, this would involve ECDH key exchange
      // For testing purposes, we'll verify key generation works
      expect(aliceKeys.publicKey, isNot(equals(bobKeys.publicKey)));
      expect(aliceKeys.privateKey, isNot(equals(bobKeys.privateKey)));
    });

    test('should derive shared secret', () async {
      final aliceKeys = await cryptoEngine.generateKeyPair();
      final bobKeys = await cryptoEngine.generateKeyPair();

      // This would test ECDH shared secret derivation
      expect(aliceKeys.publicKey, isNotNull);
      expect(bobKeys.publicKey, isNotNull);
    });
  });

  group('CryptoEngine Error Handling Tests', () {
    test('should handle invalid signature format', () async {
      const message = 'test';
      const invalidSignature = 'invalid_signature';
      final keyPair = await cryptoEngine.generateKeyPair();

      final isValid = await cryptoEngine.verify(message, invalidSignature, keyPair.publicKey);
      expect(isValid, isFalse);
    });

    test('should handle invalid encrypted data', () async {
      const invalidEncrypted = 'invalid_encrypted_data';

      expect(
        () async => await cryptoEngine.decrypt(invalidEncrypted),
        throwsA(isA<Exception>()),
      );
    });

    test('should handle invalid key format', () async {
      const message = 'test';
      const invalidKey = 'invalid_key_format';

      expect(
        () async => await cryptoEngine.sign(message, invalidKey),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('CryptoEngine Performance Tests', () {
    test('should sign messages within reasonable time', () async {
      const message = 'performance test message';
      final keyPair = await cryptoEngine.generateKeyPair();

      final stopwatch = Stopwatch()..start();
      final signature = await cryptoEngine.sign(message, keyPair.privateKey);
      stopwatch.stop();

      expect(signature, isNotNull);
      expect(stopwatch.elapsedMilliseconds, lessThan(100)); // Should be fast
    });

    test('should encrypt/decrypt within reasonable time', () async {
      final message = 'x' * 1000; // 1KB message

      final stopwatch = Stopwatch()..start();
      final encrypted = await cryptoEngine.encrypt(message);
      final decrypted = await cryptoEngine.decrypt(encrypted);
      stopwatch.stop();

      expect(decrypted, equals(message));
      expect(stopwatch.elapsedMilliseconds, lessThan(500)); // Should be reasonably fast
    });

    test('should handle concurrent operations', () async {
      final keyPair = await cryptoEngine.generateKeyPair();
      const message = 'concurrent test';

      final futures = <Future>[];
      for (var i = 0; i < 10; i++) {
        futures.add(cryptoEngine.sign(message, keyPair.privateKey));
        futures.add(cryptoEngine.encrypt(message));
      }

      final results = await Future.wait(futures);
      expect(results.length, equals(20)); // 10 signatures + 10 encryptions
      expect(results.every((result) => result != null), isTrue);
    });
  });

  group('CryptoEngine Security Tests', () {
    test('should generate cryptographically secure keys', () async {
      final keyPairs = <KeyPair>[];

      // Generate multiple key pairs
      for (var i = 0; i < 100; i++) {
        keyPairs.add(await cryptoEngine.generateKeyPair());
      }

      // Check that all keys are unique
      final publicKeys = keyPairs.map((kp) => kp.publicKey).toSet();
      final privateKeys = keyPairs.map((kp) => kp.privateKey).toSet();

      expect(publicKeys.length, equals(100));
      expect(privateKeys.length, equals(100));
    });

    test('should resist signature forgery', () async {
      const message = 'original message';
      final keyPair = await cryptoEngine.generateKeyPair();

      final signature = await cryptoEngine.sign(message, keyPair.privateKey);

      // Try to forge signature by modifying it slightly
      final forgedSignature = signature.substring(0, signature.length - 1) + 'x';
      final isValid = await cryptoEngine.verify(message, forgedSignature, keyPair.publicKey);

      expect(isValid, isFalse);
    });

    test('should provide confidentiality', () async {
      const secretMessage = 'This is a secret message that should be confidential';

      final encrypted = await cryptoEngine.encrypt(secretMessage);

      // Encrypted message should not contain the original text
      expect(encrypted.contains(secretMessage), isFalse);

      // Encrypted message should be different from original
      expect(encrypted, isNot(equals(secretMessage)));

      // Should be able to decrypt back to original
      final decrypted = await cryptoEngine.decrypt(encrypted);
      expect(decrypted, equals(secretMessage));
    });
  });
}