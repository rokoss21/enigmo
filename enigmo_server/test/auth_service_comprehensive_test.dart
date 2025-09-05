import 'package:test/test.dart';
import 'package:enigmo_server/services/auth_service.dart';
import 'package:enigmo_server/services/user_manager.dart';
import 'package:enigmo_server/models/user.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';

void main() {
  group('AuthService Comprehensive Tests', () {
    late AuthService authService;
    late UserManager userManager;
    late SimpleKeyPair testSigningKeyPair;
    late SimplePublicKey testSigningPublicKey;

    setUpAll(() async {
      // Create test keys
      final ed25519 = Ed25519();
      testSigningKeyPair = await ed25519.newKeyPair();
      testSigningPublicKey = await testSigningKeyPair.extractPublicKey();
    });

    setUp(() {
      userManager = UserManager();
      authService = AuthService(userManager);
    });

    group('Token Management', () {
      test('should generate valid token for user', () {
        const userId = 'test_user_123';
        final token = authService.generateToken(userId);
        
        expect(token, isNotEmpty);
        expect(token, startsWith('token_'));
        expect(token, contains(userId));
      });

      test('should generate unique tokens for same user', () {
        const userId = 'test_user_456';
        final token1 = authService.generateToken(userId);
        final token2 = authService.generateToken(userId);
        
        expect(token1, isNot(equals(token2)));
      });

      test('should generate different tokens for different users', () {
        final token1 = authService.generateToken('user_1');
        final token2 = authService.generateToken('user_2');
        
        expect(token1, isNot(equals(token2)));
      });

      test('should validate existing token', () async {
        const userId = 'token_test_user';
        
        // Register user first
        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );
        
        final token = authService.generateToken(userId);
        final isValid = authService.isValidToken(token);
        
        expect(isValid, isTrue);
      });

      test('should reject invalid token', () {
        const invalidToken = 'invalid_token_format';
        final isValid = authService.isValidToken(invalidToken);
        
        expect(isValid, isFalse);
      });

      test('should reject token for non-existent user', () {
        final timestamp = DateTime.now().microsecondsSinceEpoch;
        const randomPart = '654321';
        final token = 'token_nonexistent_user_${timestamp}_${randomPart}';
        final isValid = authService.isValidToken(token);

        expect(isValid, isFalse);
      });

      test('should reject expired token', () async {
        const userId = 'expired_token_user';

        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );

        final oldTimestamp = DateTime.now()
            .subtract(const Duration(hours: 2))
            .microsecondsSinceEpoch;
        const randomPart = '123456';
        final expiredToken = 'token_${userId}_${oldTimestamp}_${randomPart}';

        final isValid = authService.isValidToken(expiredToken);

        expect(isValid, isFalse);
      });

      test('should reject token without random component', () async {
        const userId = 'no_random_user';

        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );

        final timestamp = DateTime.now().microsecondsSinceEpoch;
        final token = 'token_${userId}_${timestamp}';
        final isValid = authService.isValidToken(token);

        expect(isValid, isFalse);
      });

      test('should reject token with non-numeric random part', () async {
        const userId = 'nonnumeric_random_user';

        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );

        final timestamp = DateTime.now().microsecondsSinceEpoch;
        const randomPart = 'abcdef';
        final token = 'token_${userId}_${timestamp}_${randomPart}';
        final isValid = authService.isValidToken(token);

        expect(isValid, isFalse);
      });

      test('should authenticate user by valid token', () async {
        const userId = 'auth_by_token_user';
        
        // Register user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );
        
        final token = authService.generateToken(userId);
        final user = authService.authenticateUserByToken(token);
        
        expect(user, isNotNull);
        expect(user!.id, equals(userId));
      });

      test('should return null for invalid token authentication', () {
        const invalidToken = 'definitely_invalid_token';
        final user = authService.authenticateUserByToken(invalidToken);
        
        expect(user, isNull);
      });
    });

    group('Signature Verification', () {
      test('should verify valid Ed25519 signature', () async {
        const userId = 'signature_test_user';
        const timestamp = '2024-01-01T12:00:00.000Z';
        
        // Register user with test public key
        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );
        
        // Create signature for timestamp
        final ed25519 = Ed25519();
        final message = utf8.encode(timestamp);
        final signature = await ed25519.sign(message, keyPair: testSigningKeyPair);
        final signatureBase64 = base64Encode(signature.bytes);
        
        final isValid = await authService.verifySignature(
          userId,
          timestamp,
          signatureBase64,
        );
        
        expect(isValid, isTrue);
      });

      test('should reject invalid signature', () async {
        const userId = 'invalid_signature_user';
        const timestamp = '2024-01-01T12:00:00.000Z';
        const invalidSignature = 'definitely_not_a_valid_signature';
        
        // Register user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );
        
        final isValid = await authService.verifySignature(
          userId,
          timestamp,
          invalidSignature,
        );
        
        expect(isValid, isFalse);
      });

      test('should reject signature for non-existent user', () async {
        const userId = 'nonexistent_user';
        const timestamp = '2024-01-01T12:00:00.000Z';
        const signature = 'some_signature';
        
        final isValid = await authService.verifySignature(
          userId,
          timestamp,
          signature,
        );
        
        expect(isValid, isFalse);
      });

      test('should reject signature with empty public key', () async {
        const userId = 'empty_key_user';
        const timestamp = '2024-01-01T12:00:00.000Z';
        const signature = 'some_signature';
        
        // Register user with empty public key
        await userManager.registerUser(
          id: userId,
          publicSigningKey: '',
          publicEncryptionKey: 'test_encryption_key',
        );
        
        final isValid = await authService.verifySignature(
          userId,
          timestamp,
          signature,
        );
        
        expect(isValid, isFalse);
      });

      test('should handle malformed base64 in public key', () async {
        const userId = 'malformed_key_user';
        const timestamp = '2024-01-01T12:00:00.000Z';
        const signature = 'some_signature';
        
        // Register user with malformed public key
        await userManager.registerUser(
          id: userId,
          publicSigningKey: 'not_valid_base64!@#',
          publicEncryptionKey: 'test_encryption_key',
        );
        
        final isValid = await authService.verifySignature(
          userId,
          timestamp,
          signature,
        );
        
        expect(isValid, isFalse);
      });

      test('should handle malformed base64 in signature', () async {
        const userId = 'malformed_signature_user';
        const timestamp = '2024-01-01T12:00:00.000Z';
        const signature = 'not_valid_base64!@#';
        
        // Register user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );
        
        final isValid = await authService.verifySignature(
          userId,
          timestamp,
          signature,
        );
        
        expect(isValid, isFalse);
      });

      test('should reject signature for tampered message', () async {
        const userId = 'tampered_message_user';
        const originalTimestamp = '2024-01-01T12:00:00.000Z';
        const tamperedTimestamp = '2024-01-01T13:00:00.000Z';
        
        // Register user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );
        
        // Create signature for original timestamp
        final ed25519 = Ed25519();
        final message = utf8.encode(originalTimestamp);
        final signature = await ed25519.sign(message, keyPair: testSigningKeyPair);
        final signatureBase64 = base64Encode(signature.bytes);
        
        // Try to verify with tampered timestamp
        final isValid = await authService.verifySignature(
          userId,
          tamperedTimestamp,
          signatureBase64,
        );
        
        expect(isValid, isFalse);
      });
    });

    group('Full Authentication Flow', () {
      test('should authenticate user with valid signature and fresh timestamp', () async {
        const userId = 'full_auth_user';
        
        // Register user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );
        
        // Create fresh timestamp and signature
        final timestamp = DateTime.now().toIso8601String();
        final ed25519 = Ed25519();
        final message = utf8.encode(timestamp);
        final signature = await ed25519.sign(message, keyPair: testSigningKeyPair);
        final signatureBase64 = base64Encode(signature.bytes);
        
        final success = await authService.authenticateUser(
          userId,
          signatureBase64,
          timestamp,
        );
        
        expect(success, isTrue);
        
        // User should be marked as online
        final user = userManager.getUser(userId);
        expect(user?.isOnline, isTrue);
      });

      test('should reject authentication with old timestamp', () async {
        const userId = 'old_timestamp_user';
        
        // Register user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );
        
        // Create old timestamp (6 minutes ago)
        final oldTimestamp = DateTime.now().subtract(const Duration(minutes: 6)).toIso8601String();
        final ed25519 = Ed25519();
        final message = utf8.encode(oldTimestamp);
        final signature = await ed25519.sign(message, keyPair: testSigningKeyPair);
        final signatureBase64 = base64Encode(signature.bytes);
        
        final success = await authService.authenticateUser(
          userId,
          signatureBase64,
          oldTimestamp,
        );
        
        expect(success, isFalse);
      });

      test('should accept authentication with timestamp within 5 minute window', () async {
        const userId = 'valid_window_user';
        
        // Register user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );
        
        // Create timestamp 4 minutes ago (within 5 minute window)
        final recentTimestamp = DateTime.now().subtract(const Duration(minutes: 4)).toIso8601String();
        final ed25519 = Ed25519();
        final message = utf8.encode(recentTimestamp);
        final signature = await ed25519.sign(message, keyPair: testSigningKeyPair);
        final signatureBase64 = base64Encode(signature.bytes);
        
        final success = await authService.authenticateUser(
          userId,
          signatureBase64,
          recentTimestamp,
        );
        
        expect(success, isTrue);
      });

      test('should reject authentication with malformed timestamp', () async {
        const userId = 'malformed_timestamp_user';
        const malformedTimestamp = 'not_a_valid_timestamp';
        
        // Register user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );
        
        final success = await authService.authenticateUser(
          userId,
          'any_signature',
          malformedTimestamp,
        );
        
        expect(success, isFalse);
      });

      test('should reject authentication for non-existent user', () async {
        const userId = 'nonexistent_auth_user';
        final timestamp = DateTime.now().toIso8601String();
        
        final success = await authService.authenticateUser(
          userId,
          'any_signature',
          timestamp,
        );
        
        expect(success, isFalse);
      });

      test('should reject authentication with invalid signature', () async {
        const userId = 'invalid_sig_auth_user';
        
        // Register user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );
        
        final timestamp = DateTime.now().toIso8601String();
        const invalidSignature = 'definitely_invalid_signature';
        
        final success = await authService.authenticateUser(
          userId,
          invalidSignature,
          timestamp,
        );
        
        expect(success, isFalse);
      });
    });

    group('User Existence Check', () {
      test('should confirm existing user can be authenticated', () async {
        const userId = 'existence_check_user';
        
        // Register user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );
        
        final canAuth = await authService.canAuthenticate(userId);
        expect(canAuth, isTrue);
      });

      test('should reject non-existent user for authentication check', () async {
        const userId = 'nonexistent_check_user';
        
        final canAuth = await authService.canAuthenticate(userId);
        expect(canAuth, isFalse);
      });
    });

    group('Edge Cases and Error Handling', () {
      test('should handle empty user ID', () async {
        final canAuth = await authService.canAuthenticate('');
        expect(canAuth, isFalse);
        
        final success = await authService.authenticateUser('', 'sig', 'timestamp');
        expect(success, isFalse);
      });

      test('should handle null-like values gracefully', () async {
        // Test with various problematic inputs
        expect(await authService.canAuthenticate('null'), isFalse);
        expect(await authService.canAuthenticate('undefined'), isFalse);
        
        final success = await authService.authenticateUser(
          'user',
          '',
          DateTime.now().toIso8601String(),
        );
        expect(success, isFalse);
      });

      test('should handle concurrent authentication attempts', () async {
        const userId = 'concurrent_auth_user';
        
        // Register user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );
        
        // Create multiple authentication attempts
        final futures = List.generate(10, (i) async {
          final timestamp = DateTime.now().toIso8601String();
          final ed25519 = Ed25519();
          final message = utf8.encode(timestamp);
          final signature = await ed25519.sign(message, keyPair: testSigningKeyPair);
          final signatureBase64 = base64Encode(signature.bytes);
          
          return authService.authenticateUser(userId, signatureBase64, timestamp);
        });
        
        final results = await Future.wait(futures);
        
        // All should succeed independently
        for (final result in results) {
          expect(result, isTrue);
        }
      });

      test('should handle very long user IDs', () async {
        final longUserId = 'a' * 1000;
        
        final canAuth = await authService.canAuthenticate(longUserId);
        expect(canAuth, isFalse);
      });

      test('should handle special characters in user ID', () async {
        const specialUserId = 'user@#\$%^&*()_+-=[]{}|;:,.<>?/~`';
        
        final canAuth = await authService.canAuthenticate(specialUserId);
        expect(canAuth, isFalse);
      });

      test('should handle future timestamp', () async {
        const userId = 'future_timestamp_user';
        
        // Register user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );
        
        // Create future timestamp
        final futureTimestamp = DateTime.now().add(const Duration(hours: 1)).toIso8601String();
        final ed25519 = Ed25519();
        final message = utf8.encode(futureTimestamp);
        final signature = await ed25519.sign(message, keyPair: testSigningKeyPair);
        final signatureBase64 = base64Encode(signature.bytes);
        
        final success = await authService.authenticateUser(
          userId,
          signatureBase64,
          futureTimestamp,
        );
        
        // Future timestamps should be accepted (client/server time differences)
        expect(success, isTrue);
      });
    });

    group('Performance and Stress Testing', () {
      test('should handle high volume of signature verifications', () async {
        const userId = 'performance_user';
        
        // Register user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );
        
        final stopwatch = Stopwatch()..start();
        
        // Perform many signature verifications
        for (int i = 0; i < 100; i++) {
          final timestamp = DateTime.now().toIso8601String();
          final ed25519 = Ed25519();
          final message = utf8.encode(timestamp);
          final signature = await ed25519.sign(message, keyPair: testSigningKeyPair);
          final signatureBase64 = base64Encode(signature.bytes);
          
          final isValid = await authService.verifySignature(
            userId,
            timestamp,
            signatureBase64,
          );
          
          expect(isValid, isTrue);
        }
        
        stopwatch.stop();
        
        // Should complete within reasonable time (10 seconds for 100 verifications)
        expect(stopwatch.elapsedMilliseconds, lessThan(10000));
      });

      test('should maintain accuracy under concurrent load', () async {
        const userId = 'concurrent_load_user';
        
        // Register user
        await userManager.registerUser(
          id: userId,
          publicSigningKey: base64Encode(testSigningPublicKey.bytes),
          publicEncryptionKey: 'test_encryption_key',
        );
        
        // Create concurrent verification tasks
        final futures = List.generate(50, (i) async {
          final timestamp = DateTime.now().toIso8601String();
          final ed25519 = Ed25519();
          final message = utf8.encode(timestamp);
          final signature = await ed25519.sign(message, keyPair: testSigningKeyPair);
          final signatureBase64 = base64Encode(signature.bytes);
          
          return authService.verifySignature(userId, timestamp, signatureBase64);
        });
        
        final results = await Future.wait(futures);
        
        // All should be valid
        for (final result in results) {
          expect(result, isTrue);
        }
      });
    });
  });
}