import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';

class KeyPair {
  final SimpleKeyPair signingKeyPair;
  final SimpleKeyPair encryptionKeyPair;
  
  KeyPair({
    required this.signingKeyPair,
    required this.encryptionKeyPair,
  });
}

class KeyManager {
  static const _storage = FlutterSecureStorage();
  static const String _signingKeyKey = 'signing_key';
  static const String _encryptionKeyKey = 'encryption_key';
  static const String _userIdKey = 'user_id';
  
  static KeyPair? _currentKeyPair;
  static String? _userId;
  
  /// Generates a new key pair for the user
  static Future<KeyPair> generateUserKeys() async {
    // Ed25519 for digital signatures
    final ed25519 = Ed25519();
    final signingKeyPair = await ed25519.newKeyPair();
    
    // X25519 for encryption (ECDH)
    final x25519 = X25519();
    final encryptionKeyPair = await x25519.newKeyPair();
    
    final keyPair = KeyPair(
      signingKeyPair: signingKeyPair,
      encryptionKeyPair: encryptionKeyPair,
    );
    
    // Save keys to secure storage
    await _saveKeyPair(keyPair);
    
    _currentKeyPair = keyPair;
    
    // Generate and store the user ID
    final userId = await _generateUserId(signingKeyPair);
    await _storage.write(key: _userIdKey, value: userId);
    _userId = userId;
    
    return keyPair;
  }
  
  /// Loads existing keys from storage
  static Future<KeyPair?> loadUserKeys() async {
    if (_currentKeyPair != null) {
      return _currentKeyPair;
    }
    
    try {
      final signingKeyData = await _storage.read(key: _signingKeyKey);
      final encryptionKeyData = await _storage.read(key: _encryptionKeyKey);
      
      if (signingKeyData == null || encryptionKeyData == null) {
        return null;
      }
      
      // Restore keys from saved data
      final ed25519 = Ed25519();
      final signingKeyPair = await ed25519.newKeyPairFromSeed(
        base64Decode(signingKeyData),
      );
      
      final x25519 = X25519();
      final encryptionKeyPair = await x25519.newKeyPairFromSeed(
        base64Decode(encryptionKeyData),
      );
      
      _currentKeyPair = KeyPair(
        signingKeyPair: signingKeyPair,
        encryptionKeyPair: encryptionKeyPair,
      );
      
      // Load user ID
      _userId = await _storage.read(key: _userIdKey);
      
      return _currentKeyPair;
    } catch (e) {
      print('Error loading keys: $e');
      return null;
    }
  }
  
  /// Returns the user ID (first 16 characters from the public key hash)
  static Future<String?> getUserId() async {
    if (_userId != null) {
      print('Returning cached userId: $_userId');
      return _userId!;
    }
    
    _userId = await _storage.read(key: _userIdKey);
    print('Loaded userId from storage: $_userId');
    
    return _userId;
  }
  
  /// Gets the public key for encryption
  static Future<SimplePublicKey> getEncryptionPublicKey() async {
    final keyPair = await loadUserKeys() ?? await generateUserKeys();
    return await keyPair.encryptionKeyPair.extractPublicKey();
  }
  
  /// Gets the public key for signing
  static Future<SimplePublicKey> getSigningPublicKey() async {
    final keyPair = await loadUserKeys() ?? await generateUserKeys();
    return await keyPair.signingKeyPair.extractPublicKey();
  }
  
  /// Gets the private key for decryption
  static Future<SimpleKeyPair> getEncryptionKeyPair() async {
    final keyPair = await loadUserKeys() ?? await generateUserKeys();
    return keyPair.encryptionKeyPair;
  }
  
  /// Gets the private key for signing
  static Future<SimpleKeyPair> getSigningKeyPair() async {
    final keyPair = await loadUserKeys() ?? await generateUserKeys();
    return keyPair.signingKeyPair;
  }
  
  /// Checks whether the user keys exist
  static Future<bool> hasUserKeys() async {
    final signingKey = await _storage.read(key: _signingKeyKey);
    final encryptionKey = await _storage.read(key: _encryptionKeyKey);
    return signingKey != null && encryptionKey != null;
  }
  
  /// Sets the user ID (e.g., after registration)
  static Future<void> setUserId(String userId) async {
    print('Saving userId in KeyManager: $userId');
    await _storage.write(key: _userIdKey, value: userId);
    _userId = userId;
    print('userId successfully saved to storage');
  }
  
  /// Deletes all user keys (for reset)
  static Future<void> deleteUserKeys() async {
    await _storage.delete(key: _signingKeyKey);
    await _storage.delete(key: _encryptionKeyKey);
    await _storage.delete(key: _userIdKey);
    _currentKeyPair = null;
    _userId = null;
  }
  
  /// Saves the key pair to secure storage
  static Future<void> _saveKeyPair(KeyPair keyPair) async {
    // Extract seed/private bytes for storage (more compact than full key)
    final signingKeyBytes = await keyPair.signingKeyPair.extractPrivateKeyBytes();
    final encryptionKeyBytes = await keyPair.encryptionKeyPair.extractPrivateKeyBytes();
    
    await _storage.write(
      key: _signingKeyKey,
      value: base64Encode(signingKeyBytes),
    );
    
    await _storage.write(
      key: _encryptionKeyKey,
      value: base64Encode(encryptionKeyBytes),
    );
  }
  
  /// Generates a user ID from the public key
  static Future<String> _generateUserId(SimpleKeyPair signingKeyPair) async {
    final publicKey = await signingKeyPair.extractPublicKey();
    final publicKeyBytes = publicKey.bytes;
    
    // Hash the public key and take the first 16 characters
    final hash = sha256.convert(publicKeyBytes);
    final hashHex = hash.toString();
    
    return hashHex.substring(0, 16).toUpperCase();
  }
  
  /// Converts a public key to a string for transfer
  static Future<String> publicKeyToString(SimplePublicKey publicKey) async {
    final bytes = publicKey.bytes;
    return base64Encode(bytes);
  }
  
  /// Converts a string back to a public key
  static Future<SimplePublicKey> publicKeyFromString(String keyString, {bool isEncryption = true}) async {
    final bytes = base64Decode(keyString);
    
    if (isEncryption) {
      final x25519 = X25519();
      return SimplePublicKey(bytes, type: KeyPairType.x25519);
    } else {
      final ed25519 = Ed25519();
      return SimplePublicKey(bytes, type: KeyPairType.ed25519);
    }
  }
}