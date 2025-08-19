import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'key_manager.dart';

class EncryptedMessage {
  final String encryptedData; // base64(cipherText)
  final String nonce; // base64(nonce)
  final String mac; // base64(auth tag)
  final String signature; // base64(Ed25519 over cipherText)
  
  EncryptedMessage({
    required this.encryptedData,
    required this.nonce,
    required this.mac,
    required this.signature,
  });
  
  Map<String, dynamic> toJson() => {
    'encryptedData': encryptedData,
    'nonce': nonce,
    'mac': mac,
    'signature': signature,
  };
  
  factory EncryptedMessage.fromJson(Map<String, dynamic> json) => EncryptedMessage(
    encryptedData: json['encryptedData'],
    nonce: json['nonce'],
    mac: json['mac'] ?? '',
    signature: json['signature'],
  );
}

class CryptoEngine {
  static final _chacha20 = Chacha20.poly1305Aead();
  static final _ed25519 = Ed25519();
  static final _x25519 = X25519();
  
  /// Шифрует сообщение для получателя
  static Future<EncryptedMessage> encryptMessage(
    String message,
    SimplePublicKey recipientEncryptionKey,
  ) async {
    try {
      print('INFO CryptoEngine.encryptMessage: Начало шифрования сообщения');
      
      // Получаем наши ключи
      final ourEncryptionKeyPair = await KeyManager.getEncryptionKeyPair();
      final ourSigningKeyPair = await KeyManager.getSigningKeyPair();
      
      if (ourEncryptionKeyPair == null || ourSigningKeyPair == null) {
        throw Exception('Ключи пользователя не найдены');
      }
      
      print('INFO CryptoEngine.encryptMessage: Ключи получены');
      
      // Выполняем ECDH для получения общего секрета
      final sharedSecret = await _x25519.sharedSecretKey(
        keyPair: ourEncryptionKeyPair,
        remotePublicKey: recipientEncryptionKey,
      );
      
      // Извлекаем байты общего секрета
      final sharedSecretBytes = await sharedSecret.extractBytes();
      print('INFO CryptoEngine.encryptMessage: Общий секрет создан');
      
      // Создаем ключ для симметричного шифрования
      final secretKey = SecretKey(sharedSecretBytes);
      
      // Шифруем сообщение
      final messageBytes = utf8.encode(message);
      final secretBox = await _chacha20.encrypt(
        messageBytes,
        secretKey: secretKey,
      );
      
      print('INFO CryptoEngine.encryptMessage: Сообщение зашифровано');
      
      // Подписываем зашифрованные данные
      final signature = await _ed25519.sign(
        secretBox.cipherText,
        keyPair: ourSigningKeyPair,
      );
      
      print('INFO CryptoEngine.encryptMessage: Подпись создана');
      
      return EncryptedMessage(
        encryptedData: base64Encode(secretBox.cipherText),
        nonce: base64Encode(secretBox.nonce),
        mac: base64Encode(secretBox.mac.bytes),
        signature: base64Encode(signature.bytes),
      );
    } catch (e, stackTrace) {
      print('ERROR CryptoEngine.encryptMessage: Ошибка шифрования сообщения: $e');
      print('STACK: $stackTrace');
      throw Exception('Ошибка шифрования сообщения: $e');
    }
  }
  
  /// Расшифровывает сообщение от отправителя
  static Future<String> decryptMessage(
    EncryptedMessage encryptedMessage,
    SimplePublicKey senderEncryptionKey,
    SimplePublicKey senderSigningKey,
  ) async {
    try {
      // Получаем наш ключ для расшифровки
      final ourEncryptionKeyPair = await KeyManager.getEncryptionKeyPair();
      
      // Выполняем ECDH для получения общего секрета
      final sharedSecret = await _x25519.sharedSecretKey(
        keyPair: ourEncryptionKeyPair,
        remotePublicKey: senderEncryptionKey,
      );
      
      // Извлекаем байты общего секрета
      final sharedSecretBytes = await sharedSecret.extractBytes();
      
      // Создаем ключ для симметричного расшифровки
      final secretKey = SecretKey(sharedSecretBytes);
      
      // Проверяем подпись
      final encryptedData = base64Decode(encryptedMessage.encryptedData);
      final signature = Signature(
        base64Decode(encryptedMessage.signature),
        publicKey: senderSigningKey,
      );
      
      final isValidSignature = await _ed25519.verify(
        encryptedData,
        signature: signature,
      );
      
      if (!isValidSignature) {
        throw Exception('Неверная подпись сообщения');
      }
      
      // Расшифровываем сообщение
      final secretBox = SecretBox(
        encryptedData,
        nonce: base64Decode(encryptedMessage.nonce),
        mac: (encryptedMessage.mac.isEmpty)
            ? Mac.empty
            : Mac(base64Decode(encryptedMessage.mac)),
      );
      
      final decryptedBytes = await _chacha20.decrypt(
        secretBox,
        secretKey: secretKey,
      );
      
      return utf8.decode(decryptedBytes);
    } catch (e) {
      throw Exception('Ошибка расшифровки сообщения: $e');
    }
  }
  
  /// Подписывает данные нашим приватным ключом
  static Future<String> signData(String data) async {
    try {
      print('INFO CryptoEngine.signData: Подписание данных');
      
      final signingKeyPair = await KeyManager.getSigningKeyPair();
      if (signingKeyPair == null) {
        throw Exception('Ключ подписи не найден');
      }
      
      final dataBytes = utf8.encode(data);
      print('INFO CryptoEngine.signData: Данные для подписи подготовлены (${dataBytes.length} байт)');
      
      final signature = await _ed25519.sign(
        dataBytes,
        keyPair: signingKeyPair,
      );
      
      final signatureString = base64Encode(signature.bytes);
      print('INFO CryptoEngine.signData: Подпись создана успешно');
      
      return signatureString;
    } catch (e, stackTrace) {
      print('ERROR CryptoEngine.signData: Ошибка подписи данных: $e');
      print('STACK: $stackTrace');
      throw Exception('Ошибка подписи данных: $e');
    }
  }
  
  /// Проверяет подпись данных
  static Future<bool> verifySignature(
    String data,
    String signatureString,
    SimplePublicKey signingPublicKey,
  ) async {
    try {
      print('INFO CryptoEngine.verifySignature: Проверка подписи');
      
      final dataBytes = utf8.encode(data);
      final signatureBytes = base64Decode(signatureString);
      
      print('INFO CryptoEngine.verifySignature: Данные подготовлены (${dataBytes.length} байт данных, ${signatureBytes.length} байт подписи)');
      
      final signature = Signature(
        signatureBytes,
        publicKey: signingPublicKey,
      );
      
      final isValid = await _ed25519.verify(
        dataBytes,
        signature: signature,
      );
      
      print('INFO CryptoEngine.verifySignature: Результат проверки подписи: ${isValid ? "валидна" : "невалидна"}');
      
      return isValid;
    } catch (e, stackTrace) {
      print('ERROR CryptoEngine.verifySignature: Ошибка проверки подписи: $e');
      print('STACK: $stackTrace');
      return false;
    }
  }
  
  /// Генерирует случайный nonce для дополнительной безопасности
  static List<int> generateNonce([int length = 12]) {
    final random = Random.secure();
    return List.generate(length, (_) => random.nextInt(256));
  }
  
  /// Хеширует данные с помощью SHA-256
  static Future<String> hashData(String data) async {
    final sha256Hash = Sha256();
    final dataBytes = utf8.encode(data);
    final hash = await sha256Hash.hash(dataBytes);
    return base64Encode(hash.bytes);
  }
  
  /// Проверяет целостность данных по хешу
  static Future<bool> verifyDataIntegrity(String data, String expectedHash) async {
    final actualHash = await hashData(data);
    return actualHash == expectedHash;
  }
}