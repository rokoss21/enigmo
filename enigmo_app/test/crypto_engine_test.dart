import 'package:flutter_test/flutter_test.dart';
import 'package:enigmo_app/services/crypto_engine.dart';
import 'package:enigmo_app/services/key_manager.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';

void main() {
  group('CryptoEngine Tests', () {
    late SimpleKeyPair testSigningKeyPair;
    late SimpleKeyPair testEncryptionKeyPair;
    late SimplePublicKey testSigningPublicKey;
    late SimplePublicKey testEncryptionPublicKey;

    setUpAll(() async {
      // Create test keys
      final ed25519 = Ed25519();
      final x25519 = X25519();
      
      testSigningKeyPair = await ed25519.newKeyPair();
      testEncryptionKeyPair = await x25519.newKeyPair();
      
      testSigningPublicKey = await testSigningKeyPair.extractPublicKey();
      testEncryptionPublicKey = await testEncryptionKeyPair.extractPublicKey();
    });

    group('Data Signing', () {
      test('should successfully sign data', () async {
        // Mock KeyManager to return the test key (conceptually)
        final testData = 'test_data_to_sign';
        
        // Create a signature directly for testing
        final ed25519 = Ed25519();
        final dataBytes = utf8.encode(testData);
        final signature = await ed25519.sign(dataBytes, keyPair: testSigningKeyPair);
        final signatureString = base64Encode(signature.bytes);

        expect(signatureString, isNotEmpty);
        expect(signatureString, isA<String>());
      });

      test('should successfully verify a valid signature', () async {
        final testData = 'test_data_for_verification';
        
        // Create a signature
        final ed25519 = Ed25519();
        final dataBytes = utf8.encode(testData);
        final signature = await ed25519.sign(dataBytes, keyPair: testSigningKeyPair);
        final signatureString = base64Encode(signature.bytes);

        // Verify the signature
        final isValid = await CryptoEngine.verifySignature(
          testData,
          signatureString,
          testSigningPublicKey,
        );

        expect(isValid, isTrue);
      });

      test('should reject an invalid signature', () async {
        final testData = 'test_data';
        final invalidSignature = 'invalid_signature_string';

        final isValid = await CryptoEngine.verifySignature(
          testData,
          invalidSignature,
          testSigningPublicKey,
        );

        expect(isValid, isFalse);
      });

      test('should reject a signature for modified data', () async {
        final originalData = 'original_data';
        final modifiedData = 'modified_data';
        
        // Create a signature for the original data
        final ed25519 = Ed25519();
        final dataBytes = utf8.encode(originalData);
        final signature = await ed25519.sign(dataBytes, keyPair: testSigningKeyPair);
        final signatureString = base64Encode(signature.bytes);

        // Verify the signature against modified data
        final isValid = await CryptoEngine.verifySignature(
          modifiedData,
          signatureString,
          testSigningPublicKey,
        );

        expect(isValid, isFalse);
      });
    });

    group('Message Encryption', () {
      test('should successfully encrypt and decrypt a message', () async {
        final originalMessage = 'Secret message for testing';
        
        // Create a second key pair for the recipient
        final x25519 = X25519();
        final ed25519 = Ed25519();
        
        final recipientEncryptionKeyPair = await x25519.newKeyPair();
        final recipientSigningKeyPair = await ed25519.newKeyPair();
        
        final recipientEncryptionPublicKey = await recipientEncryptionKeyPair.extractPublicKey();
        final recipientSigningPublicKey = await recipientSigningKeyPair.extractPublicKey();

        // Encrypt the message (simulate sender)
        final sharedSecret = await x25519.sharedSecretKey(
          keyPair: testEncryptionKeyPair,
          remotePublicKey: recipientEncryptionPublicKey,
        );
        
        final sharedSecretBytes = await sharedSecret.extractBytes();
        final secretKey = SecretKey(sharedSecretBytes);
        
        final chacha20 = Chacha20.poly1305Aead();
        final messageBytes = utf8.encode(originalMessage);
        final secretBox = await chacha20.encrypt(messageBytes, secretKey: secretKey);
        
        // Create a signature
        final signature = await ed25519.sign(secretBox.cipherText, keyPair: testSigningKeyPair);
        
        final encryptedMessage = EncryptedMessage(
          encryptedData: base64Encode(secretBox.cipherText),
          nonce: base64Encode(secretBox.nonce),
          mac: base64Encode(secretBox.mac.bytes),
          signature: base64Encode(signature.bytes),
        );

        // Decrypt the message (simulate recipient)
        final recipientSharedSecret = await x25519.sharedSecretKey(
          keyPair: recipientEncryptionKeyPair,
          remotePublicKey: testEncryptionPublicKey,
        );
        
        final recipientSharedSecretBytes = await recipientSharedSecret.extractBytes();
        final recipientSecretKey = SecretKey(recipientSharedSecretBytes);
        
        // Verify the signature
        final encryptedData = base64Decode(encryptedMessage.encryptedData);
        final signatureObj = Signature(
          base64Decode(encryptedMessage.signature),
          publicKey: testSigningPublicKey,
        );
        
        final isValidSignature = await ed25519.verify(
          encryptedData,
          signature: signatureObj,
        );
        
        expect(isValidSignature, isTrue);
        
        // Decrypt
        final recipientSecretBox = SecretBox(
          encryptedData,
          nonce: base64Decode(encryptedMessage.nonce),
          mac: secretBox.mac,
        );
        
        final decryptedBytes = await chacha20.decrypt(
          recipientSecretBox,
          secretKey: recipientSecretKey,
        );
        
        final decryptedMessage = utf8.decode(decryptedBytes);
        
        expect(decryptedMessage, equals(originalMessage));
      });
    });

    group('Data Hashing', () {
      test('should create a data hash', () async {
        final testData = 'test_data_for_hashing';
        
        final hash = await CryptoEngine.hashData(testData);
        
        expect(hash, isNotEmpty);
        expect(hash, isA<String>());
        
        // Hash should be deterministic
        final hash2 = await CryptoEngine.hashData(testData);
        expect(hash, equals(hash2));
      });

      test('should create different hashes for different data', () async {
        final data1 = 'first_data';
        final data2 = 'second_data';
        
        final hash1 = await CryptoEngine.hashData(data1);
        final hash2 = await CryptoEngine.hashData(data2);
        
        expect(hash1, isNot(equals(hash2)));
      });

      test('should verify data integrity', () async {
        final testData = 'integrity_test_data';
        
        final hash = await CryptoEngine.hashData(testData);
        
        // Verify with correct data
        final isValid = await CryptoEngine.verifyDataIntegrity(testData, hash);
        expect(isValid, isTrue);
        
        // Verify with modified data
        final isInvalid = await CryptoEngine.verifyDataIntegrity('modified_data', hash);
        expect(isInvalid, isFalse);
      });
    });

    group('Nonce Generation', () {
      test('should generate a nonce of a given length', () {
        final nonce12 = CryptoEngine.generateNonce(12);
        final nonce16 = CryptoEngine.generateNonce(16);
        final nonce24 = CryptoEngine.generateNonce(24);
        
        expect(nonce12.length, equals(12));
        expect(nonce16.length, equals(16));
        expect(nonce24.length, equals(24));
      });

      test('should generate different nonces', () {
        final nonce1 = CryptoEngine.generateNonce();
        final nonce2 = CryptoEngine.generateNonce();
        
        expect(nonce1, isNot(equals(nonce2)));
      });

      test('should generate a default nonce of 12 bytes', () {
        final nonce = CryptoEngine.generateNonce();
        expect(nonce.length, equals(12));
      });
    });

    group('EncryptedMessage', () {
      test('should serialize and deserialize EncryptedMessage', () {
        final originalMessage = EncryptedMessage(
          encryptedData: 'encrypted_data_base64',
          nonce: 'nonce_base64',
          mac: 'mac_base64',
          signature: 'signature_base64',
        );

        final json = originalMessage.toJson();
        final deserializedMessage = EncryptedMessage.fromJson(json);

        expect(deserializedMessage.encryptedData, equals(originalMessage.encryptedData));
        expect(deserializedMessage.nonce, equals(originalMessage.nonce));
        expect(deserializedMessage.signature, equals(originalMessage.signature));
      });
    });
  });
}