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
      // Создаем тестовые ключи
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

    test('должен успешно проверить валидную подпись', () async {
      // Регистрируем тестового пользователя
      await userManager.registerUser(
        id: testUser.id,
        publicSigningKey: testUser.publicSigningKey,
        publicEncryptionKey: testUser.publicEncryptionKey,
        nickname: testUser.nickname,
      );

      // Создаем подпись
      final timestamp = DateTime.now().toIso8601String();
      final dataBytes = utf8.encode(timestamp);
      final signature = await Ed25519().sign(dataBytes, keyPair: testKeyPair);
      final signatureString = base64Encode(signature.bytes);

      // Проверяем подпись
      final isValid = await authService.verifySignature(
        testUser.id,
        timestamp,
        signatureString,
      );

      expect(isValid, isTrue);
    });

    test('должен отклонить неверную подпись', () async {
      // Регистрируем тестового пользователя
      await userManager.registerUser(
        id: testUser.id,
        publicSigningKey: testUser.publicSigningKey,
        publicEncryptionKey: testUser.publicEncryptionKey,
        nickname: testUser.nickname,
      );

      final timestamp = DateTime.now().toIso8601String();
      final invalidSignature = 'invalid_signature';

      // Проверяем неверную подпись
      final isValid = await authService.verifySignature(
        testUser.id,
        timestamp,
        invalidSignature,
      );

      expect(isValid, isFalse);
    });

    test('должен отклонить аутентификацию с устаревшим timestamp', () async {
      // Регистрируем тестового пользователя
      await userManager.registerUser(
        id: testUser.id,
        publicSigningKey: testUser.publicSigningKey,
        publicEncryptionKey: testUser.publicEncryptionKey,
        nickname: testUser.nickname,
      );

      // Создаем устаревший timestamp (6 минут назад)
      final oldTimestamp = DateTime.now()
          .subtract(const Duration(minutes: 6))
          .toIso8601String();
      
      final dataBytes = utf8.encode(oldTimestamp);
      final signature = await Ed25519().sign(dataBytes, keyPair: testKeyPair);
      final signatureString = base64Encode(signature.bytes);

      // Проверяем аутентификацию
      final isAuthenticated = await authService.authenticateUser(
        testUser.id,
        signatureString,
        oldTimestamp,
      );

      expect(isAuthenticated, isFalse);
    });

    test('должен успешно аутентифицировать пользователя с валидными данными', () async {
      // Регистрируем тестового пользователя
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

      // Проверяем аутентификацию
      final isAuthenticated = await authService.authenticateUser(
        testUser.id,
        signatureString,
        timestamp,
      );

      expect(isAuthenticated, isTrue);
    });

    test('должен отклонить аутентификацию несуществующего пользователя', () async {
      final timestamp = DateTime.now().toIso8601String();
      final dataBytes = utf8.encode(timestamp);
      final signature = await Ed25519().sign(dataBytes, keyPair: testKeyPair);
      final signatureString = base64Encode(signature.bytes);

      // Проверяем аутентификацию несуществующего пользователя
      final isAuthenticated = await authService.authenticateUser(
        'nonexistent_user',
        signatureString,
        timestamp,
      );

      expect(isAuthenticated, isFalse);
    });

    test('должен проверить возможность аутентификации', () async {
      // Регистрируем тестового пользователя
      await userManager.registerUser(
        id: testUser.id,
        publicSigningKey: testUser.publicSigningKey,
        publicEncryptionKey: testUser.publicEncryptionKey,
        nickname: testUser.nickname,
      );

      // Проверяем возможность аутентификации
      final canAuth = await authService.canAuthenticate(testUser.id);
      expect(canAuth, isTrue);

      // Проверяем для несуществующего пользователя
      final canAuthNonexistent = await authService.canAuthenticate('nonexistent');
      expect(canAuthNonexistent, isFalse);
    });
  });
}