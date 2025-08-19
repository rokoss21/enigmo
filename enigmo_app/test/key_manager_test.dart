import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';

void main() {
  // Initialize Flutter binding for tests
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('KeyManager Crypto Tests', () {
    group('Cryptographic operations', () {
      test('should generate Ed25519 keys for signing', () async {
        final ed25519 = Ed25519();
        final keyPair = await ed25519.newKeyPair();
        final publicKey = await keyPair.extractPublicKey();
        
        expect(keyPair, isNotNull);
        expect(publicKey, isNotNull);
        expect(publicKey.bytes, isNotEmpty);
        expect(publicKey.bytes.length, equals(32)); // Ed25519 public key size
      });

      test('should generate X25519 keys for encryption', () async {
        final x25519 = X25519();
        final keyPair = await x25519.newKeyPair();
        final publicKey = await keyPair.extractPublicKey();
        
        expect(keyPair, isNotNull);
        expect(publicKey, isNotNull);
        expect(publicKey.bytes, isNotEmpty);
        expect(publicKey.bytes.length, equals(32)); // X25519 public key size
      });

      test('should convert keys to base64 and back', () async {
        final ed25519 = Ed25519();
        final keyPair = await ed25519.newKeyPair();
        final publicKey = await keyPair.extractPublicKey();
        
        // Convert to base64
        final keyString = base64Encode(publicKey.bytes);
        expect(keyString, isNotEmpty);
        
        // Convert back
        final restoredBytes = base64Decode(keyString);
        expect(restoredBytes, equals(publicKey.bytes));
      });

      test('should create deterministic keys from seed', () async {
        final ed25519 = Ed25519();
        final seed = List.generate(32, (i) => i + 1);
        
        final keyPair1 = await ed25519.newKeyPairFromSeed(seed);
        final keyPair2 = await ed25519.newKeyPairFromSeed(seed);
        
        final publicKey1 = await keyPair1.extractPublicKey();
        final publicKey2 = await keyPair2.extractPublicKey();
        
        expect(publicKey1.bytes, equals(publicKey2.bytes));
      });

      test('should generate different keys for different seeds', () async {
        final ed25519 = Ed25519();
        final seed1 = List.generate(32, (i) => i + 1);
        final seed2 = List.generate(32, (i) => i + 2);
        
        final keyPair1 = await ed25519.newKeyPairFromSeed(seed1);
        final keyPair2 = await ed25519.newKeyPairFromSeed(seed2);
        
        final publicKey1 = await keyPair1.extractPublicKey();
        final publicKey2 = await keyPair2.extractPublicKey();
        
        expect(publicKey1.bytes, isNot(equals(publicKey2.bytes)));
      });

      test('should create a userId from a public key', () async {
        final ed25519 = Ed25519();
        final keyPair = await ed25519.newKeyPair();
        final publicKey = await keyPair.extractPublicKey();
        
        // Simulate creating userId from a key (as in KeyManager)
        final keyString = base64Encode(publicKey.bytes);
        final hash = await Sha256().hash(utf8.encode(keyString));
        final userId = base64Encode(hash.bytes).substring(0, 16);
        
        expect(userId, isNotNull);
        expect(userId.length, equals(16));
      });

      test('should create the same userId for identical keys', () async {
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

      test('should create different userIds for different keys', () async {
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

      test('should work with X25519 keys for encryption', () async {
        final x25519 = X25519();
        
        final aliceKeyPair = await x25519.newKeyPair();
        final bobKeyPair = await x25519.newKeyPair();
        
        final alicePublicKey = await aliceKeyPair.extractPublicKey();
        final bobPublicKey = await bobKeyPair.extractPublicKey();
        
        // Alice creates a shared secret with Bob
        final aliceSharedSecret = await x25519.sharedSecretKey(
          keyPair: aliceKeyPair,
          remotePublicKey: bobPublicKey,
        );
        
        // Bob creates a shared secret with Alice
        final bobSharedSecret = await x25519.sharedSecretKey(
          keyPair: bobKeyPair,
          remotePublicKey: alicePublicKey,
        );
        
        final aliceSecretBytes = await aliceSharedSecret.extractBytes();
        final bobSecretBytes = await bobSharedSecret.extractBytes();
        
        expect(aliceSecretBytes, equals(bobSecretBytes));
      });

      test('should verify validity of Ed25519 signatures', () async {
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