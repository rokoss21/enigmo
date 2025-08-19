import 'package:test/test.dart';
import 'package:enigmo_server/services/auth_service.dart';
import 'package:enigmo_server/services/user_manager.dart';
import 'package:enigmo_server/models/user.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';

void main() {
  group('AuthService Tests', () {
    late AuthService authService;
    late UserManager userManager;
    late User testUser;
    late SimpleKeyPair testKeyPair;

    setUpAll(() async {
      // Create test keys
      final ed25519 = Ed25519();
      testKeyPair = await ed25519.newKeyPair();
      final publicKey = await testKeyPair.extractPublicKey();
      final publicKeyString = base64Encode(publicKey.bytes);

      testUser = User(
        id: 'test_user_123',
        publicSigningKey: publicKeyString,
        publicEncryptionKey: 'test_encryption_key',
        lastSeen: DateTime.now(),
        nickname: 'Test User',
      );
    });

    setUp(() {
      userManager = UserManager();
      authService = AuthService(userManager);
    });

    test('should successfully verify a valid signature', () async {
      // Register the test user
      await userManager.registerUser(
        id: testUser.id,
        publicSigningKey: testUser.publicSigningKey,
        publicEncryptionKey: testUser.publicEncryptionKey,
        nickname: testUser.nickname,
      );

      // Create a signature
      final timestamp = DateTime.now().toIso8601String();
      final dataBytes = utf8.encode(timestamp);
      final signature = await Ed25519().sign(dataBytes, keyPair: testKeyPair);
      final signatureString = base64Encode(signature.bytes);

      // Verify the signature
      final isValid = await authService.verifySignature(
        testUser.id,
        timestamp,
        signatureString,
      );

      expect(isValid, isTrue);
    });

    test('should reject an invalid signature', () async {
      // Register the test user
      await userManager.registerUser(
        id: testUser.id,
        publicSigningKey: testUser.publicSigningKey,
        publicEncryptionKey: testUser.publicEncryptionKey,
        nickname: testUser.nickname,
      );

      final timestamp = DateTime.now().toIso8601String();
      final invalidSignature = 'invalid_signature';

      // Verify an invalid signature
      final isValid = await authService.verifySignature(
        testUser.id,
        timestamp,
        invalidSignature,
      );

      expect(isValid, isFalse);
    });

    test('should reject authentication with an outdated timestamp', () async {
      // Register the test user
      await userManager.registerUser(
        id: testUser.id,
        publicSigningKey: testUser.publicSigningKey,
        publicEncryptionKey: testUser.publicEncryptionKey,
        nickname: testUser.nickname,
      );

      // Create an outdated timestamp (6 minutes ago)
      final oldTimestamp = DateTime.now()
          .subtract(const Duration(minutes: 6))
          .toIso8601String();
      
      final dataBytes = utf8.encode(oldTimestamp);
      final signature = await Ed25519().sign(dataBytes, keyPair: testKeyPair);
      final signatureString = base64Encode(signature.bytes);

      // Check authentication
      final isAuthenticated = await authService.authenticateUser(
        testUser.id,
        signatureString,
        oldTimestamp,
      );

      expect(isAuthenticated, isFalse);
    });

    test('should authenticate a user with valid data', () async {
      // Register the test user
      await userManager.registerUser(
        id: testUser.id,
        publicSigningKey: testUser.publicSigningKey,
        publicEncryptionKey: testUser.publicEncryptionKey,
        nickname: testUser.nickname,
      );

      final timestamp = DateTime.now().toIso8601String();
      final dataBytes = utf8.encode(timestamp);
      final signature = await Ed25519().sign(dataBytes, keyPair: testKeyPair);
      final signatureString = base64Encode(signature.bytes);

      // Check authentication
      final isAuthenticated = await authService.authenticateUser(
        testUser.id,
        signatureString,
        timestamp,
      );

      expect(isAuthenticated, isTrue);
    });

    test('should reject authentication for a non-existent user', () async {
      final timestamp = DateTime.now().toIso8601String();
      final dataBytes = utf8.encode(timestamp);
      final signature = await Ed25519().sign(dataBytes, keyPair: testKeyPair);
      final signatureString = base64Encode(signature.bytes);

      // Check authentication for a non-existent user
      final isAuthenticated = await authService.authenticateUser(
        'nonexistent_user',
        signatureString,
        timestamp,
      );

      expect(isAuthenticated, isFalse);
    });

    test('should check the ability to authenticate', () async {
      // Register the test user
      await userManager.registerUser(
        id: testUser.id,
        publicSigningKey: testUser.publicSigningKey,
        publicEncryptionKey: testUser.publicEncryptionKey,
        nickname: testUser.nickname,
      );

      // Check the ability to authenticate
      final canAuth = await authService.canAuthenticate(testUser.id);
      expect(canAuth, isTrue);

      // Check for a non-existent user
      final canAuthNonexistent = await authService.canAuthenticate('nonexistent');
      expect(canAuthNonexistent, isFalse);
    });
  });
}