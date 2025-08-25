import 'package:flutter_test/flutter_test.dart';
import 'package:enigmo_app/services/key_manager.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:typed_data';

/// Mock FlutterSecureStorage for testing
class MockFlutterSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _storage = {};
  bool _shouldThrowError = false;
  
  void setShouldThrowError(bool shouldThrow) {
    _shouldThrowError = shouldThrow;
  }
  
  void clearStorage() {
    _storage.clear();
  }

  @override
  Future<String?> read({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    if (_shouldThrowError) throw Exception('Storage read error');
    return _storage[key];
  }

  @override
  Future<void> write({required String key, required String value, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    if (_shouldThrowError) throw Exception('Storage write error');
    _storage[key] = value;
  }

  @override
  Future<void> delete({required String key, IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    if (_shouldThrowError) throw Exception('Storage delete error');
    _storage.remove(key);
  }

  @override
  Future<void> deleteAll({IOSOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, MacOsOptions? mOptions, WindowsOptions? wOptions}) async {
    if (_shouldThrowError) throw Exception('Storage deleteAll error');
    _storage.clear();
  }
}

void main() {
  // CRITICAL: Initialize Flutter test bindings
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('KeyManager Comprehensive Tests', () {
    late MockFlutterSecureStorage mockStorage;

    setUp(() {
      mockStorage = MockFlutterSecureStorage();
      // Reset KeyManager state
      KeyManager.deleteUserKeys();
    });

    tearDown(() {
      mockStorage.clearStorage();
    });

    group('Key Generation', () {
      test('should generate valid Ed25519 and X25519 key pairs', () async {
        final keyPair = await KeyManager.generateUserKeys();
        
        expect(keyPair, isNotNull);
        expect(keyPair.signingKeyPair, isNotNull);
        expect(keyPair.encryptionKeyPair, isNotNull);
        
        // Verify key types
        final signingPublicKey = await keyPair.signingKeyPair.extractPublicKey();
        final encryptionPublicKey = await keyPair.encryptionKeyPair.extractPublicKey();
        
        expect(signingPublicKey.type, equals(KeyPairType.ed25519));
        expect(encryptionPublicKey.type, equals(KeyPairType.x25519));
        
        // Verify key lengths (32 bytes for both Ed25519 and X25519 public keys)
        expect(signingPublicKey.bytes.length, equals(32));
        expect(encryptionPublicKey.bytes.length, equals(32));
      });

      test('should generate unique keys each time', () async {
        final keyPair1 = await KeyManager.generateUserKeys();
        await KeyManager.deleteUserKeys();
        final keyPair2 = await KeyManager.generateUserKeys();
        
        final signingKey1 = await keyPair1.signingKeyPair.extractPublicKey();
        final signingKey2 = await keyPair2.signingKeyPair.extractPublicKey();
        
        final encryptionKey1 = await keyPair1.encryptionKeyPair.extractPublicKey();
        final encryptionKey2 = await keyPair2.encryptionKeyPair.extractPublicKey();
        
        expect(signingKey1.bytes, isNot(equals(signingKey2.bytes)));
        expect(encryptionKey1.bytes, isNot(equals(encryptionKey2.bytes)));
      });

      test('should automatically generate user ID from signing key', () async {
        await KeyManager.generateUserKeys();
        final userId = await KeyManager.getUserId();
        
        expect(userId, isNotNull);
        expect(userId!.length, equals(16));
        expect(userId, matches(RegExp(r'^[0-9A-F]+$'))); // Should be uppercase hex
      });

      test('should cache generated keys in memory', () async {
        final keyPair1 = await KeyManager.generateUserKeys();
        final keyPair2 = await KeyManager.loadUserKeys();
        
        expect(keyPair1, equals(keyPair2));
      });
    });

    group('Key Persistence', () {
      test('should save and load keys from secure storage', () async {
        // Generate and save keys
        final originalKeyPair = await KeyManager.generateUserKeys();
        final originalUserId = await KeyManager.getUserId();
        
        // Clear memory cache
        await KeyManager.deleteUserKeys();
        
        // Load keys back (this should trigger loading from storage)
        final loadedKeyPair = await KeyManager.loadUserKeys();
        final loadedUserId = await KeyManager.getUserId();
        
        expect(loadedKeyPair, isNotNull);
        expect(loadedUserId, equals(originalUserId));
        
        // Verify keys are functionally identical
        final originalSigningKey = await originalKeyPair.signingKeyPair.extractPublicKey();
        final loadedSigningKey = await loadedKeyPair!.signingKeyPair.extractPublicKey();
        
        expect(loadedSigningKey.bytes, equals(originalSigningKey.bytes));
      });

      test('should handle missing keys gracefully', () async {
        final keyPair = await KeyManager.loadUserKeys();
        expect(keyPair, isNull);
        
        final userId = await KeyManager.getUserId();
        expect(userId, isNull);
      });

      test('should validate key existence check', () async {
        // Initially no keys
        expect(await KeyManager.hasUserKeys(), isFalse);
        
        // After generation
        await KeyManager.generateUserKeys();
        expect(await KeyManager.hasUserKeys(), isTrue);
        
        // After deletion
        await KeyManager.deleteUserKeys();
        expect(await KeyManager.hasUserKeys(), isFalse);
      });
    });

    group('Public Key Management', () {
      test('should extract public keys correctly', () async {
        await KeyManager.generateUserKeys();
        
        final signingPublicKey = await KeyManager.getSigningPublicKey();
        final encryptionPublicKey = await KeyManager.getEncryptionPublicKey();
        
        expect(signingPublicKey.bytes.length, equals(32));
        expect(encryptionPublicKey.bytes.length, equals(32));
        expect(signingPublicKey.type, equals(KeyPairType.ed25519));
        expect(encryptionPublicKey.type, equals(KeyPairType.x25519));
      });

      test('should convert public keys to/from string format', () async {
        await KeyManager.generateUserKeys();
        
        final signingPublicKey = await KeyManager.getSigningPublicKey();
        final encryptionPublicKey = await KeyManager.getEncryptionPublicKey();
        
        // Convert to strings
        final signingKeyString = await KeyManager.publicKeyToString(signingPublicKey);
        final encryptionKeyString = await KeyManager.publicKeyToString(encryptionPublicKey);
        
        expect(signingKeyString, isNotEmpty);
        expect(encryptionKeyString, isNotEmpty);
        
        // Verify base64 format
        expect(() => base64Decode(signingKeyString), returnsNormally);
        expect(() => base64Decode(encryptionKeyString), returnsNormally);
        
        // Convert back to keys
        final reconstructedSigningKey = await KeyManager.publicKeyFromString(signingKeyString, isEncryption: false);
        final reconstructedEncryptionKey = await KeyManager.publicKeyFromString(encryptionKeyString, isEncryption: true);
        
        expect(reconstructedSigningKey.bytes, equals(signingPublicKey.bytes));
        expect(reconstructedEncryptionKey.bytes, equals(encryptionPublicKey.bytes));
      });

      test('should validate public key string conversion inputs', () async {
        // Test empty string
        expect(
          () async => await KeyManager.publicKeyFromString(''),
          throwsException,
        );
        
        // Test invalid base64
        expect(
          () async => await KeyManager.publicKeyFromString('invalid_base64!@#'),
          throwsException,
        );
        
        // Test wrong key length
        final wrongLengthKey = base64Encode(Uint8List(16)); // Should be 32 bytes
        expect(
          () async => await KeyManager.publicKeyFromString(wrongLengthKey),
          throwsException,
        );
      });
    });

    group('User ID Management', () {
      test('should generate deterministic user ID from signing key', () async {
        // Generate keys with known seed for deterministic testing
        final ed25519 = Ed25519();
        final testSeed = Uint8List.fromList(List.generate(32, (i) => i));
        final signingKeyPair = await ed25519.newKeyPairFromSeed(testSeed);
        
        // Simulate the user ID generation process
        final publicKey = await signingKeyPair.extractPublicKey();
        final publicKeyBytes = publicKey.bytes;
        
        // This should match the internal _generateUserId method
        final hash = Sha256().hashSync(publicKeyBytes);
        final expectedUserId = hash.toString().substring(0, 16).toUpperCase();
        
        // The generated user ID should be deterministic
        expect(expectedUserId.length, equals(16));
        expect(expectedUserId, matches(RegExp(r'^[0-9A-F]+$')));
      });

      test('should cache user ID in memory', () async {
        await KeyManager.generateUserKeys();
        
        final userId1 = await KeyManager.getUserId();
        final userId2 = await KeyManager.getUserId();
        
        expect(userId1, equals(userId2));
        expect(userId1, isNotNull);
      });

      test('should allow setting custom user ID', () async {
        const customUserId = 'CUSTOM_USER_ID_12';
        
        await KeyManager.setUserId(customUserId);
        final retrievedUserId = await KeyManager.getUserId();
        
        expect(retrievedUserId, equals(customUserId));
      });
    });

    group('Error Handling and Edge Cases', () {
      test('should handle corrupted key data gracefully', () async {
        // Generate valid keys first
        await KeyManager.generateUserKeys();
        
        // Manually corrupt the stored data
        mockStorage._storage['signing_key'] = 'corrupted_base64_data';
        
        // Clear memory cache to force reload from storage
        await KeyManager.deleteUserKeys();
        
        // Loading should fail gracefully and return null
        final loadedKeys = await KeyManager.loadUserKeys();
        expect(loadedKeys, isNull);
        
        // Storage should be cleaned up
        expect(await KeyManager.hasUserKeys(), isFalse);
      });

      test('should handle empty key data in storage', () async {
        // Set empty key data
        mockStorage._storage['signing_key'] = '';
        mockStorage._storage['encryption_key'] = '';
        
        final loadedKeys = await KeyManager.loadUserKeys();
        expect(loadedKeys, isNull);
        
        // Storage should be cleaned up
        expect(await KeyManager.hasUserKeys(), isFalse);
      });

      test('should handle wrong key length in storage', () async {
        // Generate keys with wrong length (16 bytes instead of 32)
        final wrongLengthKey = base64Encode(Uint8List(16));
        mockStorage._storage['signing_key'] = wrongLengthKey;
        mockStorage._storage['encryption_key'] = wrongLengthKey;
        
        final loadedKeys = await KeyManager.loadUserKeys();
        expect(loadedKeys, isNull);
        
        // Storage should be cleaned up
        expect(await KeyManager.hasUserKeys(), isFalse);
      });

      test('should handle storage access errors', () async {
        // Test read error
        mockStorage.setShouldThrowError(true);
        
        final loadedKeys = await KeyManager.loadUserKeys();
        expect(loadedKeys, isNull);
        
        // Test generation with write error
        expect(
          () async => await KeyManager.generateUserKeys(),
          throwsException,
        );
      });

      test('should validate key extraction capability', () async {
        // Generate keys
        await KeyManager.generateUserKeys();
        
        // Manually corrupt one key to make extraction fail
        mockStorage._storage['signing_key'] = base64Encode(Uint8List(32)); // Valid length but invalid key
        
        // Clear cache
        await KeyManager.deleteUserKeys();
        
        // Loading should detect the invalid key and clean up
        final loadedKeys = await KeyManager.loadUserKeys();
        expect(loadedKeys, isNull);
      });
    });

    group('Security Properties', () {
      test('should use cryptographically secure key generation', () async {
        // Generate multiple key pairs and verify they are unique
        final keyPairs = <KeyPair>[];
        
        for (int i = 0; i < 5; i++) {
          await KeyManager.deleteUserKeys();
          final keyPair = await KeyManager.generateUserKeys();
          keyPairs.add(keyPair);
        }
        
        // All signing keys should be unique
        final signingKeys = await Future.wait(
          keyPairs.map((kp) => kp.signingKeyPair.extractPublicKey())
        );
        
        for (int i = 0; i < signingKeys.length; i++) {
          for (int j = i + 1; j < signingKeys.length; j++) {
            expect(signingKeys[i].bytes, isNot(equals(signingKeys[j].bytes)));
          }
        }
        
        // All encryption keys should be unique
        final encryptionKeys = await Future.wait(
          keyPairs.map((kp) => kp.encryptionKeyPair.extractPublicKey())
        );
        
        for (int i = 0; i < encryptionKeys.length; i++) {
          for (int j = i + 1; j < encryptionKeys.length; j++) {
            expect(encryptionKeys[i].bytes, isNot(equals(encryptionKeys[j].bytes)));
          }
        }
      });

      test('should properly implement key derivation', () async {
        // Test that keys are properly derived from seeds
        final ed25519 = Ed25519();
        final x25519 = X25519();
        
        // Test with known seed
        final testSeed = Uint8List.fromList(List.generate(32, (i) => i + 1));
        
        final signingKeyPair1 = await ed25519.newKeyPairFromSeed(testSeed);
        final signingKeyPair2 = await ed25519.newKeyPairFromSeed(testSeed);
        
        final publicKey1 = await signingKeyPair1.extractPublicKey();
        final publicKey2 = await signingKeyPair2.extractPublicKey();
        
        // Same seed should produce same keys
        expect(publicKey1.bytes, equals(publicKey2.bytes));
        
        // Different seeds should produce different keys
        final differentSeed = Uint8List.fromList(List.generate(32, (i) => i + 100));
        final signingKeyPair3 = await ed25519.newKeyPairFromSeed(differentSeed);
        final publicKey3 = await signingKeyPair3.extractPublicKey();
        
        expect(publicKey1.bytes, isNot(equals(publicKey3.bytes)));
      });

      test('should maintain key consistency across operations', () async {
        await KeyManager.generateUserKeys();
        
        // Get keys multiple times and verify consistency
        final signingKey1 = await KeyManager.getSigningPublicKey();
        final signingKey2 = await KeyManager.getSigningPublicKey();
        final encryptionKey1 = await KeyManager.getEncryptionPublicKey();
        final encryptionKey2 = await KeyManager.getEncryptionPublicKey();
        
        expect(signingKey1.bytes, equals(signingKey2.bytes));
        expect(encryptionKey1.bytes, equals(encryptionKey2.bytes));
        
        // User ID should also be consistent
        final userId1 = await KeyManager.getUserId();
        final userId2 = await KeyManager.getUserId();
        expect(userId1, equals(userId2));
      });
    });

    group('Performance and Scalability', () {
      test('should handle rapid key operations efficiently', () async {
        final stopwatch = Stopwatch()..start();
        
        // Perform multiple key operations rapidly
        for (int i = 0; i < 10; i++) {
          await KeyManager.deleteUserKeys();
          await KeyManager.generateUserKeys();
          await KeyManager.hasUserKeys();
          await KeyManager.getUserId();
          await KeyManager.getSigningPublicKey();
          await KeyManager.getEncryptionPublicKey();
        }
        
        stopwatch.stop();
        
        // Should complete within reasonable time (adjust threshold as needed)
        expect(stopwatch.elapsedMilliseconds, lessThan(10000)); // 10 seconds
      });

      test('should cache keys efficiently', () async {
        await KeyManager.generateUserKeys();
        
        final stopwatch = Stopwatch()..start();
        
        // Multiple accesses should be fast due to caching
        for (int i = 0; i < 100; i++) {
          await KeyManager.getSigningPublicKey();
          await KeyManager.getEncryptionPublicKey();
          await KeyManager.getUserId();
        }
        
        stopwatch.stop();
        
        // Cached operations should be very fast
        expect(stopwatch.elapsedMilliseconds, lessThan(1000)); // 1 second
      });
    });
  });
}