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
  
  /// Encrypts a message for the recipient
  static Future<EncryptedMessage> encryptMessage(
    String message,
    SimplePublicKey recipientEncryptionKey,
  ) async {
    try {
      print('INFO CryptoEngine.encryptMessage: Start encrypting message');
      
      // Validate input parameters
      if (message.isEmpty) {
        throw Exception('Cannot encrypt empty message');
      }
      
      if (recipientEncryptionKey.bytes.isEmpty) {
        throw Exception('Invalid recipient encryption key');
      }
      
      // Get our keys
      final ourEncryptionKeyPair = await KeyManager.getEncryptionKeyPair();
      final ourSigningKeyPair = await KeyManager.getSigningKeyPair();
      
      if (ourEncryptionKeyPair == null || ourSigningKeyPair == null) {
        throw Exception('User keys not found - please initialize keys first');
      }
      
      print('INFO CryptoEngine.encryptMessage: Keys obtained');
      
      // Perform ECDH to derive a shared secret
      final sharedSecret = await _x25519.sharedSecretKey(
        keyPair: ourEncryptionKeyPair,
        remotePublicKey: recipientEncryptionKey,
      );
      
      // Extract bytes of the shared secret
      final sharedSecretBytes = await sharedSecret.extractBytes();
      if (sharedSecretBytes.length != 32) {
        throw Exception('Invalid shared secret length: ${sharedSecretBytes.length}');
      }
      
      print('INFO CryptoEngine.encryptMessage: Shared secret derived');
      
      // Create a key for symmetric encryption
      final secretKey = SecretKey(sharedSecretBytes);
      
      // Encrypt the message
      final messageBytes = utf8.encode(message);
      final secretBox = await _chacha20.encrypt(
        messageBytes,
        secretKey: secretKey,
      );
      
      // Validate encryption result
      if (secretBox.cipherText.isEmpty || secretBox.nonce.isEmpty) {
        throw Exception('Encryption failed - invalid ciphertext or nonce');
      }
      
      print('INFO CryptoEngine.encryptMessage: Message encrypted');
      
      // Sign the encrypted data
      final signature = await _ed25519.sign(
        secretBox.cipherText,
        keyPair: ourSigningKeyPair,
      );
      
      if (signature.bytes.length != 64) {
        throw Exception('Invalid signature length: ${signature.bytes.length}');
      }
      
      print('INFO CryptoEngine.encryptMessage: Signature created');
      
      return EncryptedMessage(
        encryptedData: base64Encode(secretBox.cipherText),
        nonce: base64Encode(secretBox.nonce),
        mac: base64Encode(secretBox.mac.bytes),
        signature: base64Encode(signature.bytes),
      );
    } catch (e, stackTrace) {
      print('ERROR CryptoEngine.encryptMessage: Error encrypting message: $e');
      print('STACK: $stackTrace');
      throw Exception('Message encryption error: $e');
    }
  }
  
  /// Decrypts a message from the sender
  static Future<String> decryptMessage(
    EncryptedMessage encryptedMessage,
    SimplePublicKey senderEncryptionKey,
    SimplePublicKey senderSigningKey,
  ) async {
    try {
      print('INFO CryptoEngine.decryptMessage: Starting decryption');
      
      // Validate input parameters
      if (encryptedMessage.encryptedData.isEmpty ||
          encryptedMessage.nonce.isEmpty ||
          encryptedMessage.signature.isEmpty) {
        throw Exception('Invalid encrypted message: missing required fields');
      }
      
      // Get our key for decryption
      final ourEncryptionKeyPair = await KeyManager.getEncryptionKeyPair();
      if (ourEncryptionKeyPair == null) {
        throw Exception('Encryption key pair not found');
      }
      
      // Perform ECDH to derive a shared secret
      final sharedSecret = await _x25519.sharedSecretKey(
        keyPair: ourEncryptionKeyPair,
        remotePublicKey: senderEncryptionKey,
      );
      
      // Extract bytes of the shared secret
      final sharedSecretBytes = await sharedSecret.extractBytes();
      print('INFO CryptoEngine.decryptMessage: Shared secret derived');
      
      // Create a key for symmetric decryption
      final secretKey = SecretKey(sharedSecretBytes);
      
      // Verify signature first
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
        throw Exception('Invalid message signature - message may be tampered');
      }
      
      print('INFO CryptoEngine.decryptMessage: Signature verified successfully');
      
      // Decrypt the message with proper MAC handling
      final nonce = base64Decode(encryptedMessage.nonce);
      final mac = encryptedMessage.mac.isEmpty 
          ? Mac.empty 
          : Mac(base64Decode(encryptedMessage.mac));
      
      final secretBox = SecretBox(
        encryptedData,
        nonce: nonce,
        mac: mac,
      );
      
      final decryptedBytes = await _chacha20.decrypt(
        secretBox,
        secretKey: secretKey,
      );
      
      final decryptedMessage = utf8.decode(decryptedBytes);
      print('INFO CryptoEngine.decryptMessage: Message decrypted successfully');
      
      return decryptedMessage;
    } catch (e, stackTrace) {
      print('ERROR CryptoEngine.decryptMessage: Decryption failed: $e');
      print('STACK: $stackTrace');
      throw Exception('Message decryption error: $e');
    }
  }
  
  /// Signs data with our private key
  static Future<String> signData(String data) async {
    try {
      print('INFO CryptoEngine.signData: Signing data');
      
      // CRITICAL: Validate input data
      if (data.isEmpty) {
        throw Exception('Cannot sign empty data');
      }
      
      if (data.length > 1024 * 1024) { // 1MB limit
        throw Exception('Data too large for signing: ${data.length} bytes');
      }
      
      final signingKeyPair = await KeyManager.getSigningKeyPair();
      if (signingKeyPair == null) {
        throw Exception('Signing key not found');
      }
      
      final dataBytes = utf8.encode(data);
      print('INFO CryptoEngine.signData: Data prepared for signing (${dataBytes.length} bytes)');
      
      final signature = await _ed25519.sign(
        dataBytes,
        keyPair: signingKeyPair,
      );
      
      // Validate signature result
      if (signature.bytes.length != 64) {
        throw Exception('Invalid signature length: ${signature.bytes.length}');
      }
      
      final signatureString = base64Encode(signature.bytes);
      print('INFO CryptoEngine.signData: Signature created successfully');
      
      return signatureString;
    } catch (e, stackTrace) {
      print('ERROR CryptoEngine.signData: Error signing data: $e');
      print('STACK: $stackTrace');
      throw Exception('Data signing error: $e');
    }
  }
  
  /// Verifies the data signature
  static Future<bool> verifySignature(
    String data,
    String signatureString,
    SimplePublicKey signingPublicKey,
  ) async {
    try {
      print('INFO CryptoEngine.verifySignature: Verifying signature');
      
      // CRITICAL: Validate inputs to prevent attacks
      if (data.isEmpty) {
        print('ERROR CryptoEngine.verifySignature: Empty data provided');
        return false;
      }
      
      if (signatureString.isEmpty) {
        print('ERROR CryptoEngine.verifySignature: Empty signature provided');
        return false;
      }
      
      if (signingPublicKey.bytes.isEmpty) {
        print('ERROR CryptoEngine.verifySignature: Invalid public key provided');
        return false;
      }
      
      if (data.length > 1024 * 1024) { // 1MB limit
        print('ERROR CryptoEngine.verifySignature: Data too large: ${data.length} bytes');
        return false;
      }
      
      final dataBytes = utf8.encode(data);
      late final List<int> signatureBytes;
      
      try {
        signatureBytes = base64Decode(signatureString);
      } catch (e) {
        print('ERROR CryptoEngine.verifySignature: Invalid base64 signature: $e');
        return false;
      }
      
      // Validate signature length for Ed25519
      if (signatureBytes.length != 64) {
        print('ERROR CryptoEngine.verifySignature: Invalid signature length: ${signatureBytes.length}');
        return false;
      }
      
      // Validate public key length for Ed25519
      if (signingPublicKey.bytes.length != 32) {
        print('ERROR CryptoEngine.verifySignature: Invalid public key length: ${signingPublicKey.bytes.length}');
        return false;
      }
      
      print('INFO CryptoEngine.verifySignature: Data prepared (${dataBytes.length} bytes of data, ${signatureBytes.length} bytes of signature)');
      
      final signature = Signature(
        signatureBytes,
        publicKey: signingPublicKey,
      );
      
      final isValid = await _ed25519.verify(
        dataBytes,
        signature: signature,
      );
      
      print('INFO CryptoEngine.verifySignature: Verification result: ${isValid ? "valid" : "invalid"}');
      
      return isValid;
    } catch (e, stackTrace) {
      print('ERROR CryptoEngine.verifySignature: Error verifying signature: $e');
      print('STACK: $stackTrace');
      return false; // Always return false on any error for security
    }
  }
  
  /// Generates a random nonce for additional security
  static List<int> generateNonce([int length = 12]) {
    final random = Random.secure();
    return List.generate(length, (_) => random.nextInt(256));
  }
  
  /// Hashes data using SHA-256
  static Future<String> hashData(String data) async {
    final sha256Hash = Sha256();
    final dataBytes = utf8.encode(data);
    final hash = await sha256Hash.hash(dataBytes);
    return base64Encode(hash.bytes);
  }
  
  /// Verifies data integrity by comparing hashes
  static Future<bool> verifyDataIntegrity(String data, String expectedHash) async {
    final actualHash = await hashData(data);
    return actualHash == expectedHash;
  }
}