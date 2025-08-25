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
      
      // Validate stored data
      if (signingKeyData.isEmpty || encryptionKeyData.isEmpty) {
        print('ERROR KeyManager.loadUserKeys: Empty key data found in storage');
        await deleteUserKeys(); // Clean up corrupted data
        return null;
      }
      
      // Restore keys from saved data
      final ed25519 = Ed25519();
      late final List<int> signingKeyBytes;
      
      try {
        signingKeyBytes = base64Decode(signingKeyData);
      } catch (e) {
        print('ERROR KeyManager.loadUserKeys: Invalid base64 signing key data: $e');
        await deleteUserKeys(); // Clean up corrupted data
        return null;
      }
      
      if (signingKeyBytes.length != 32) {
        print('ERROR KeyManager.loadUserKeys: Invalid signing key length: ${signingKeyBytes.length}');
        await deleteUserKeys(); // Clean up corrupted data
        return null;
      }
      
      final signingKeyPair = await ed25519.newKeyPairFromSeed(signingKeyBytes);
      
      final x25519 = X25519();
      late final List<int> encryptionKeyBytes;
      
      try {
        encryptionKeyBytes = base64Decode(encryptionKeyData);
      } catch (e) {
        print('ERROR KeyManager.loadUserKeys: Invalid base64 encryption key data: $e');
        await deleteUserKeys(); // Clean up corrupted data
        return null;
      }
      
      if (encryptionKeyBytes.length != 32) {
        print('ERROR KeyManager.loadUserKeys: Invalid encryption key length: ${encryptionKeyBytes.length}');
        await deleteUserKeys(); // Clean up corrupted data
        return null;
      }
      
      final encryptionKeyPair = await x25519.newKeyPairFromSeed(encryptionKeyBytes);
      
      _currentKeyPair = KeyPair(
        signingKeyPair: signingKeyPair,
        encryptionKeyPair: encryptionKeyPair,
      );
      
      // Load user ID
      _userId = await _storage.read(key: _userIdKey);
      
      // Validate that keys can extract public keys properly
      try {
        await _currentKeyPair!.signingKeyPair.extractPublicKey();
        await _currentKeyPair!.encryptionKeyPair.extractPublicKey();
      } catch (e) {
        print('ERROR KeyManager.loadUserKeys: Failed to extract public keys: $e');
        await deleteUserKeys(); // Clean up corrupted data
        _currentKeyPair = null;
        return null;
      }
      
      return _currentKeyPair;
    } catch (e) {
      print('ERROR KeyManager.loadUserKeys: Error loading keys: $e');
      await deleteUserKeys(); // Clean up potentially corrupted data
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
    try {
      // Validate input
      if (keyString.isEmpty) {
        throw Exception('Key string cannot be empty');
      }
      
      final bytes = base64Decode(keyString);
      
      // Validate key length
      if (bytes.length != 32) {
        throw Exception('Invalid key length: ${bytes.length}. Expected 32 bytes.');
      }
      
      if (isEncryption) {
        return SimplePublicKey(bytes, type: KeyPairType.x25519);
      } else {
        return SimplePublicKey(bytes, type: KeyPairType.ed25519);
      }
    } catch (e) {
      throw Exception('Failed to parse public key: $e');
    }
  }
}