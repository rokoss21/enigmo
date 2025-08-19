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
  
  /// Генерирует новую пару ключей для пользователя
  static Future<KeyPair> generateUserKeys() async {
    // Ed25519 для цифровых подписей
    final ed25519 = Ed25519();
    final signingKeyPair = await ed25519.newKeyPair();
    
    // X25519 для шифрования (ECDH)
    final x25519 = X25519();
    final encryptionKeyPair = await x25519.newKeyPair();
    
    final keyPair = KeyPair(
      signingKeyPair: signingKeyPair,
      encryptionKeyPair: encryptionKeyPair,
    );
    
    // Сохраняем ключи в безопасном хранилище
    await _saveKeyPair(keyPair);
    
    _currentKeyPair = keyPair;
    
    // Генерируем и сохраняем ID пользователя
    final userId = await _generateUserId(signingKeyPair);
    await _storage.write(key: _userIdKey, value: userId);
    _userId = userId;
    
    return keyPair;
  }
  
  /// Загружает существующие ключи из хранилища
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
      
      // Восстанавливаем ключи из сохраненных данных
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
      
      // Загружаем ID пользователя
      _userId = await _storage.read(key: _userIdKey);
      
      return _currentKeyPair;
    } catch (e) {
      print('Ошибка загрузки ключей: $e');
      return null;
    }
  }
  
  /// Возвращает ID пользователя (первые 16 символов от публичного ключа)
  static Future<String?> getUserId() async {
    if (_userId != null) {
      print('Возвращаем кэшированный userId: $_userId');
      return _userId!;
    }
    
    _userId = await _storage.read(key: _userIdKey);
    print('Загружен userId из хранилища: $_userId');
    
    return _userId;
  }
  
  /// Получает публичный ключ для шифрования
  static Future<SimplePublicKey> getEncryptionPublicKey() async {
    final keyPair = await loadUserKeys() ?? await generateUserKeys();
    return await keyPair.encryptionKeyPair.extractPublicKey();
  }
  
  /// Получает публичный ключ для подписи
  static Future<SimplePublicKey> getSigningPublicKey() async {
    final keyPair = await loadUserKeys() ?? await generateUserKeys();
    return await keyPair.signingKeyPair.extractPublicKey();
  }
  
  /// Получает приватный ключ для расшифровки
  static Future<SimpleKeyPair> getEncryptionKeyPair() async {
    final keyPair = await loadUserKeys() ?? await generateUserKeys();
    return keyPair.encryptionKeyPair;
  }
  
  /// Получает приватный ключ для подписи
  static Future<SimpleKeyPair> getSigningKeyPair() async {
    final keyPair = await loadUserKeys() ?? await generateUserKeys();
    return keyPair.signingKeyPair;
  }
  
  /// Проверяет, существуют ли ключи пользователя
  static Future<bool> hasUserKeys() async {
    final signingKey = await _storage.read(key: _signingKeyKey);
    final encryptionKey = await _storage.read(key: _encryptionKeyKey);
    return signingKey != null && encryptionKey != null;
  }
  
  /// Устанавливает ID пользователя (например, после регистрации)
  static Future<void> setUserId(String userId) async {
    print('Сохраняем userId в KeyManager: $userId');
    await _storage.write(key: _userIdKey, value: userId);
    _userId = userId;
    print('userId успешно сохранен в хранилище');
  }
  
  /// Удаляет все ключи пользователя (для сброса)
  static Future<void> deleteUserKeys() async {
    await _storage.delete(key: _signingKeyKey);
    await _storage.delete(key: _encryptionKeyKey);
    await _storage.delete(key: _userIdKey);
    _currentKeyPair = null;
    _userId = null;
  }
  
  /// Сохраняет пару ключей в безопасном хранилище
  static Future<void> _saveKeyPair(KeyPair keyPair) async {
    // Извлекаем seed для сохранения (более компактно чем весь ключ)
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
  
  /// Генерирует ID пользователя из публичного ключа
  static Future<String> _generateUserId(SimpleKeyPair signingKeyPair) async {
    final publicKey = await signingKeyPair.extractPublicKey();
    final publicKeyBytes = publicKey.bytes;
    
    // Хешируем публичный ключ и берем первые 16 символов
    final hash = sha256.convert(publicKeyBytes);
    final hashHex = hash.toString();
    
    return hashHex.substring(0, 16).toUpperCase();
  }
  
  /// Конвертирует публичный ключ в строку для передачи
  static Future<String> publicKeyToString(SimplePublicKey publicKey) async {
    final bytes = publicKey.bytes;
    return base64Encode(bytes);
  }
  
  /// Конвертирует строку обратно в публичный ключ
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