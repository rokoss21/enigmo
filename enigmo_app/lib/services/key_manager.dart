import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'crypto_engine.dart';

// In-memory storage for development (fallback when Keychain is not available)
class _InMemoryStorage {
  static final Map<String, String> _storage = {};

  static Future<void> write(String key, String value) async {
    _storage[key] = value;
  }

  static Future<String?> read(String key) async {
    return _storage[key];
  }

  static Future<void> delete(String key) async {
    _storage.remove(key);
  }

  static Future<void> deleteAll() async {
    _storage.clear();
  }
}

class KeyManager {
  static const String _userIdKey = 'user_id';
  static const String _signingPrivateKey = 'signing_private_key';
  static const String _encryptionPrivateKey = 'encryption_private_key';
  static const String _signingPublicKey = 'signing_public_key';
  static const String _encryptionPublicKey = 'encryption_public_key';
  static const String _signingKeyKey = 'signing_key';
  static const String _encryptionKeyKey = 'encryption_key';

  static final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static String? _userId;
  static KeyPair? _currentKeyPair;

  static Future<String?> _read(String key) async {
    return await _InMemoryStorage.read(key);
  }

  static Future<void> _write(String key, String value) async {
    await _InMemoryStorage.write(key, value);
  }

  static Future<void> _delete(String key) async {
    await _InMemoryStorage.delete(key);
  }

  static Future<void> _deleteAll() async {
    await _InMemoryStorage.deleteAll();
  }

  /// Generate new user keys
  static Future<UserKeys?> generateUserKeys() async {
    try {
      print('INFO KeyManager.generateUserKeys: Generating new user keys');

      // Generate Ed25519 key pair for signing
      final signingKeyPair = await Ed25519().newKeyPair();
      final signingPrivateKey = await signingKeyPair.extractPrivateKeyBytes();
      final signingPublicKey = await signingKeyPair.extractPublicKey();

      // Generate X25519 key pair for encryption
      final encryptionKeyPair = await X25519().newKeyPair();
      final encryptionPrivateKey = await encryptionKeyPair.extractPrivateKeyBytes();
      final encryptionPublicKey = await encryptionKeyPair.extractPublicKey();

      final userKeys = UserKeys(
        signingKeyPair: signingKeyPair,
        encryptionKeyPair: encryptionKeyPair,
        signingPrivateKey: Uint8List.fromList(signingPrivateKey),
        encryptionPrivateKey: Uint8List.fromList(encryptionPrivateKey),
        signingPublicKey: signingPublicKey,
        encryptionPublicKey: encryptionPublicKey,
      );

      // Save keys to storage
      await _saveKeysToStorage(userKeys);

      print('INFO KeyManager.generateUserKeys: Keys generated and saved successfully');
      return userKeys;
    } catch (e, stackTrace) {
      print('ERROR KeyManager.generateUserKeys: Error generating keys: $e');
      print('STACK: $stackTrace');
      return null;
    }
  }

  /// Load user keys from storage
  static Future<UserKeys?> loadUserKeys() async {
    try {
      print('INFO KeyManager.loadUserKeys: Loading user keys from storage');

      // Load private keys from storage
      final signingPrivateKeyStr = await _read(_signingPrivateKey);
      final encryptionPrivateKeyStr = await _read(_encryptionPrivateKey);
      final signingPublicKeyStr = await _read(_signingPublicKey);
      final encryptionPublicKeyStr = await _read(_encryptionPublicKey);

      if (signingPrivateKeyStr == null ||
          encryptionPrivateKeyStr == null ||
          signingPublicKeyStr == null ||
          encryptionPublicKeyStr == null) {
        print('INFO KeyManager.loadUserKeys: No keys found in storage');
        return null;
      }

      // Decode keys from base64
      final signingPrivateKey = base64Decode(signingPrivateKeyStr);
      final encryptionPrivateKey = base64Decode(encryptionPrivateKeyStr);
      final signingPublicKey = await publicKeyFromString(signingPublicKeyStr, isEncryption: false);
      final encryptionPublicKey = await publicKeyFromString(encryptionPublicKeyStr, isEncryption: true);

      // Recreate key pairs
      final signingKeyPair = await Ed25519().newKeyPairFromSeed(signingPrivateKey);
      final encryptionKeyPair = await X25519().newKeyPairFromSeed(encryptionPrivateKey);

      final userKeys = UserKeys(
        signingKeyPair: signingKeyPair,
        encryptionKeyPair: encryptionKeyPair,
        signingPrivateKey: Uint8List.fromList(signingPrivateKey),
        encryptionPrivateKey: Uint8List.fromList(encryptionPrivateKey),
        signingPublicKey: signingPublicKey,
        encryptionPublicKey: encryptionPublicKey,
      );

      print('INFO KeyManager.loadUserKeys: Keys loaded successfully');
      return userKeys;
    } catch (e, stackTrace) {
      print('ERROR KeyManager.loadUserKeys: Error loading keys: $e');
      print('STACK: $stackTrace');
      return null;
    }
  }

  /// Save user ID
  static Future<void> setUserId(String userId) async {
    try {
      await _write(_userIdKey, userId);
      print('INFO KeyManager.setUserId: User ID saved: $userId');
    } catch (e) {
      print('ERROR KeyManager.setUserId: Error saving user ID: $e');
      throw Exception('Failed to save user ID');
    }
  }

  /// Get user ID
  static Future<String?> getUserId() async {
    try {
      final userId = await _read(_userIdKey);
      print('INFO KeyManager.getUserId: Retrieved user ID: $userId');
      return userId;
    } catch (e) {
      print('ERROR KeyManager.getUserId: Error retrieving user ID: $e');
      return null;
    }
  }

  /// Delete all user keys and data
  static Future<void> deleteUserKeys() async {
    try {
      await _deleteAll();
      print('INFO KeyManager.deleteUserKeys: All keys and data deleted');
    } catch (e) {
      print('ERROR KeyManager.deleteUserKeys: Error deleting keys: $e');
      throw Exception('Failed to delete user keys');
    }
  }

  /// Save keys to storage
  static Future<void> _saveKeysToStorage(UserKeys userKeys) async {
    try {
      // Save private keys as base64
      await _write(
        _signingPrivateKey,
        base64Encode(userKeys.signingPrivateKey),
      );
      await _write(
        _encryptionPrivateKey,
        base64Encode(userKeys.encryptionPrivateKey),
      );

      // Save public keys as base64
      await _write(
        _signingPublicKey,
        await publicKeyToString(userKeys.signingPublicKey),
      );
      await _write(
        _encryptionPublicKey,
        await publicKeyToString(userKeys.encryptionPublicKey),
      );

      print('INFO KeyManager._saveKeysToStorage: Keys saved to storage');
    } catch (e) {
      print('ERROR KeyManager._saveKeysToStorage: Error saving keys: $e');
      throw Exception('Failed to save keys to storage');
    }
  }

  /// Convert public key to string
  static Future<String> publicKeyToString(SimplePublicKey publicKey) async {
    final bytes = publicKey.bytes;
    return base64Encode(bytes);
  }

  /// Convert string to public key
  static Future<SimplePublicKey> publicKeyFromString(String keyStr, {required bool isEncryption}) async {
    final bytes = base64Decode(keyStr);
    if (isEncryption) {
      return SimplePublicKey(bytes, type: KeyPairType.x25519);
    } else {
      return SimplePublicKey(bytes, type: KeyPairType.ed25519);
    }
  }

  /// Get signing key pair
  static Future<SimpleKeyPair?> getSigningKeyPair() async {
    final keys = await loadUserKeys();
    return keys?.signingKeyPair;
  }

  /// Get encryption key pair
  static Future<SimpleKeyPair?> getEncryptionKeyPair() async {
    final keys = await loadUserKeys();
    return keys?.encryptionKeyPair;
  }
}

class UserKeys {
  final SimpleKeyPair signingKeyPair;
  final SimpleKeyPair encryptionKeyPair;
  final Uint8List signingPrivateKey;
  final Uint8List encryptionPrivateKey;
  final SimplePublicKey signingPublicKey;
  final SimplePublicKey encryptionPublicKey;

  UserKeys({
    required this.signingKeyPair,
    required this.encryptionKeyPair,
    required this.signingPrivateKey,
    required this.encryptionPrivateKey,
    required this.signingPublicKey,
    required this.encryptionPublicKey,
  });
}

class KeyPair {
  final SimpleKeyPair signingKeyPair;
  final SimpleKeyPair encryptionKeyPair;

  KeyPair({
    required this.signingKeyPair,
    required this.encryptionKeyPair,
  });
}