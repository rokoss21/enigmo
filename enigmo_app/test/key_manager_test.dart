import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';

void main() {
  // Инициализируем Flutter binding для тестов
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('KeyManager Crypto Tests', () {
    group('Криптографические операции', () {
      test('должен генерировать Ed25519 ключи для подписи', () async {
        final ed25519 = Ed25519();
        final keyPair = await ed25519.newKeyPair();
        final publicKey = await keyPair.extractPublicKey();
        
        expect(keyPair, isNotNull);
        expect(publicKey, isNotNull);
        expect(publicKey.bytes, isNotEmpty);
        expect(publicKey.bytes.length, equals(32)); // Ed25519 public key size
      });

      test('должен генерировать X25519 ключи для шифрования', () async {
        final x25519 = X25519();
        final keyPair = await x25519.newKeyPair();
        final publicKey = await keyPair.extractPublicKey();
        
        expect(keyPair, isNotNull);
        expect(publicKey, isNotNull);
        expect(publicKey.bytes, isNotEmpty);
        expect(publicKey.bytes.length, equals(32)); // X25519 public key size
      });

      test('должен конвертировать ключи в base64 и обратно', () async {
        final ed25519 = Ed25519();
        final keyPair = await ed25519.newKeyPair();
        final publicKey = await keyPair.extractPublicKey();
        
        // Конвертируем в base64
        final keyString = base64Encode(publicKey.bytes);
        expect(keyString, isNotEmpty);
        
        // Конвертируем обратно
        final restoredBytes = base64Decode(keyString);
        expect(restoredBytes, equals(publicKey.bytes));
      });

      test('должен создавать детерминированные ключи из seed', () async {
        final ed25519 = Ed25519();
        final seed = List.generate(32, (i) => i + 1);
        
        final keyPair1 = await ed25519.newKeyPairFromSeed(seed);
        final keyPair2 = await ed25519.newKeyPairFromSeed(seed);
        
        final publicKey1 = await keyPair1.extractPublicKey();
        final publicKey2 = await keyPair2.extractPublicKey();
        
        expect(publicKey1.bytes, equals(publicKey2.bytes));
      });

      test('должен генерировать разные ключи для разных seed', () async {
        final ed25519 = Ed25519();
        final seed1 = List.generate(32, (i) => i + 1);
        final seed2 = List.generate(32, (i) => i + 2);
        
        final keyPair1 = await ed25519.newKeyPairFromSeed(seed1);
        final keyPair2 = await ed25519.newKeyPairFromSeed(seed2);
        
        final publicKey1 = await keyPair1.extractPublicKey();
        final publicKey2 = await keyPair2.extractPublicKey();
        
        expect(publicKey1.bytes, isNot(equals(publicKey2.bytes)));
      });

      test('должен создавать userId из публичного ключа', () async {
        final ed25519 = Ed25519();
        final keyPair = await ed25519.newKeyPair();
        final publicKey = await keyPair.extractPublicKey();
        
        // Имитируем создание userId из ключа (как в KeyManager)
        final keyString = base64Encode(publicKey.bytes);
        final hash = await Sha256().hash(utf8.encode(keyString));
        final userId = base64Encode(hash.bytes).substring(0, 16);
        
        expect(userId, isNotNull);
        expect(userId.length, equals(16));
      });

      test('должен создавать одинаковые userId для одинаковых ключей', () async {
        final ed25519 = Ed25519();
        final seed = List.generate(32, (i) => i + 1);
        
        final keyPair1 = await ed25519.newKeyPairFromSeed(seed);
        final keyPair2 = await ed25519.newKeyPairFromSeed(seed);
        
        final publicKey1 = await keyPair1.extractPublicKey();
        final publicKey2 = await keyPair2.extractPublicKey();
        
        final keyString1 = base64Encode(publicKey1.bytes);
        final keyString2 = base64Encode(publicKey2.bytes);
        
        final hash1 = await Sha256().hash(utf8.encode(keyString1));
        final hash2 = await Sha256().hash(utf8.encode(keyString2));
        
        final userId1 = base64Encode(hash1.bytes).substring(0, 16);
        final userId2 = base64Encode(hash2.bytes).substring(0, 16);
        
        expect(userId1, equals(userId2));
      });

      test('должен создавать разные userId для разных ключей', () async {
        final ed25519 = Ed25519();
        
        final keyPair1 = await ed25519.newKeyPair();
        final keyPair2 = await ed25519.newKeyPair();
        
        final publicKey1 = await keyPair1.extractPublicKey();
        final publicKey2 = await keyPair2.extractPublicKey();
        
        final keyString1 = base64Encode(publicKey1.bytes);
        final keyString2 = base64Encode(publicKey2.bytes);
        
        final hash1 = await Sha256().hash(utf8.encode(keyString1));
        final hash2 = await Sha256().hash(utf8.encode(keyString2));
        
        final userId1 = base64Encode(hash1.bytes).substring(0, 16);
        final userId2 = base64Encode(hash2.bytes).substring(0, 16);
        
        expect(userId1, isNot(equals(userId2)));
      });

      test('должен работать с X25519 ключами для шифрования', () async {
        final x25519 = X25519();
        
        final aliceKeyPair = await x25519.newKeyPair();
        final bobKeyPair = await x25519.newKeyPair();
        
        final alicePublicKey = await aliceKeyPair.extractPublicKey();
        final bobPublicKey = await bobKeyPair.extractPublicKey();
        
        // Alice создает общий секрет с Bob
        final aliceSharedSecret = await x25519.sharedSecretKey(
          keyPair: aliceKeyPair,
          remotePublicKey: bobPublicKey,
        );
        
        // Bob создает общий секрет с Alice
        final bobSharedSecret = await x25519.sharedSecretKey(
          keyPair: bobKeyPair,
          remotePublicKey: alicePublicKey,
        );
        
        final aliceSecretBytes = await aliceSharedSecret.extractBytes();
        final bobSecretBytes = await bobSharedSecret.extractBytes();
        
        expect(aliceSecretBytes, equals(bobSecretBytes));
      });

      test('должен проверять валидность Ed25519 подписей', () async {
        final ed25519 = Ed25519();
        final keyPair = await ed25519.newKeyPair();
        final publicKey = await keyPair.extractPublicKey();
        
        final message = 'test message';
        final messageBytes = utf8.encode(message);
        
        final signature = await ed25519.sign(messageBytes, keyPair: keyPair);
        
        final isValid = await ed25519.verify(
          messageBytes,
          signature: signature,
        );
        
        expect(isValid, isTrue);
      });
    });
  });
}