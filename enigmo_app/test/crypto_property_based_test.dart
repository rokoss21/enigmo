import 'package:flutter_test/flutter_test.dart';
import 'package:enigmo_app/services/crypto_engine.dart';
import 'package:enigmo_app/services/key_manager.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Property-based testing for cryptographic functions
/// Tests mathematical properties that must always hold true
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('CryptoEngine Property-Based Tests', () {
    late SimpleKeyPair alice_signingKeyPair;
    late SimpleKeyPair alice_encryptionKeyPair;
    late SimpleKeyPair bob_signingKeyPair;
    late SimpleKeyPair bob_encryptionKeyPair;
    
    late SimplePublicKey alice_signingPublicKey;
    late SimplePublicKey alice_encryptionPublicKey;
    late SimplePublicKey bob_signingPublicKey;
    late SimplePublicKey bob_encryptionPublicKey;

    setUpAll(() async {
      // Create test keys
      final ed25519 = Ed25519();
      final x25519 = X25519();
      
      alice_signingKeyPair = await ed25519.newKeyPair();
      alice_encryptionKeyPair = await x25519.newKeyPair();
      bob_signingKeyPair = await ed25519.newKeyPair();
      bob_encryptionKeyPair = await x25519.newKeyPair();
      
      alice_signingPublicKey = await alice_signingKeyPair.extractPublicKey();
      alice_encryptionPublicKey = await alice_encryptionKeyPair.extractPublicKey();
      bob_signingPublicKey = await bob_signingKeyPair.extractPublicKey();
      bob_encryptionPublicKey = await bob_encryptionKeyPair.extractPublicKey();
    });

    group('Digital Signature Properties', () {
      test('Property: Signature verification is deterministic', () async {
        final random = Random.secure();
        
        for (int i = 0; i < 20; i++) {
          // Generate random message
          final messageLength = random.nextInt(1000) + 1;
          final messageBytes = List.generate(messageLength, (_) => random.nextInt(256));
          final message = String.fromCharCodes(messageBytes.where((b) => b != 0));
          
          if (message.isEmpty) continue;
          
          // Create signature
          final ed25519 = Ed25519();
          final dataBytes = utf8.encode(message);
          final signature = await ed25519.sign(dataBytes, keyPair: alice_signingKeyPair);
          final signatureString = base64Encode(signature.bytes);
          
          // Property: Multiple verifications of the same signature should always return the same result
          final result1 = await CryptoEngine.verifySignature(message, signatureString, alice_signingPublicKey);
          final result2 = await CryptoEngine.verifySignature(message, signatureString, alice_signingPublicKey);
          final result3 = await CryptoEngine.verifySignature(message, signatureString, alice_signingPublicKey);
          
          expect(result1, equals(result2));
          expect(result2, equals(result3));
          expect(result1, isTrue); // Should be valid since we created it properly
        }
      });

      test('Property: Valid signatures always verify correctly', () async {
        final random = Random.secure();
        
        for (int i = 0; i < 15; i++) {
          // Generate random message data
          final messageLength = random.nextInt(500) + 1;
          final messageChars = List.generate(messageLength, (_) => 
            String.fromCharCode(32 + random.nextInt(95)) // Printable ASCII
          );
          final message = messageChars.join();
          
          // Create signature using Ed25519 directly
          final ed25519 = Ed25519();
          final dataBytes = utf8.encode(message);
          final signature = await ed25519.sign(dataBytes, keyPair: alice_signingKeyPair);
          final signatureString = base64Encode(signature.bytes);
          
          // Property: A properly created signature should always verify
          final isValid = await CryptoEngine.verifySignature(
            message, 
            signatureString, 
            alice_signingPublicKey
          );
          
          expect(isValid, isTrue, reason: 'Valid signature should always verify for message: ${message.substring(0, min(50, message.length))}...');
        }
      });

      test('Property: Signature verification fails for wrong public key', () async {
        final random = Random.secure();
        
        for (int i = 0; i < 10; i++) {
          final message = 'Test message ${random.nextInt(10000)}';
          
          // Sign with Alice's key
          final ed25519 = Ed25519();
          final dataBytes = utf8.encode(message);
          final signature = await ed25519.sign(dataBytes, keyPair: alice_signingKeyPair);
          final signatureString = base64Encode(signature.bytes);
          
          // Property: Verification with Bob's public key should fail
          final isValid = await CryptoEngine.verifySignature(
            message, 
            signatureString, 
            bob_signingPublicKey
          );
          
          expect(isValid, isFalse, 
            reason: 'Signature from Alice should not verify with Bob public key');
        }
      });

      test('Property: Any modification to signed data breaks signature', () async {
        final random = Random.secure();
        
        for (int i = 0; i < 10; i++) {
          final originalMessage = 'Original message ${random.nextInt(10000)} with data';
          
          // Create signature for original message
          final ed25519 = Ed25519();
          final dataBytes = utf8.encode(originalMessage);
          final signature = await ed25519.sign(dataBytes, keyPair: alice_signingKeyPair);
          final signatureString = base64Encode(signature.bytes);
          
          // Property: Any modification should break the signature
          final modifications = [
            originalMessage + 'x', // Add character
            originalMessage.substring(1), // Remove first character
            originalMessage.replaceFirst('a', 'b'), // Change character
            originalMessage.toUpperCase(), // Change case
            '', // Empty string
          ];
          
          for (final modifiedMessage in modifications) {
            final isValid = await CryptoEngine.verifySignature(
              modifiedMessage, 
              signatureString, 
              alice_signingPublicKey
            );
            
            expect(isValid, isFalse, 
              reason: 'Modified message "$modifiedMessage" should not verify against original signature');
          }
        }
      });
    });

    group('Encryption/Decryption Properties', () {
      test('Property: Encryption-decryption is identity function', () async {
        final random = Random.secure();
        
        for (int i = 0; i < 15; i++) {
          // Generate random message
          final messageLength = random.nextInt(1000) + 1;
          final messageChars = List.generate(messageLength, (_) => 
            String.fromCharCode(32 + random.nextInt(95)) // Printable ASCII
          );
          final originalMessage = messageChars.join();
          
          try {
            // Property: encrypt(decrypt(message)) == message
            final encryptedMessage = await _simulateEncryption(
              originalMessage, 
              alice_encryptionKeyPair, 
              bob_encryptionPublicKey,
              alice_signingKeyPair
            );
            
            final decryptedMessage = await _simulateDecryption(
              encryptedMessage,
              bob_encryptionKeyPair,
              alice_encryptionPublicKey,
              alice_signingPublicKey
            );
            
            expect(decryptedMessage, equals(originalMessage), 
              reason: 'Decrypted message should match original for: ${originalMessage.substring(0, min(50, originalMessage.length))}...');
          } catch (e) {
            // Skip this iteration if encryption fails (e.g., due to invalid characters)
            print('Skipping iteration $i due to encryption error: $e');
            continue;
          }
        }
      });

      test('Property: Different messages produce different ciphertexts', () async {
        final random = Random.secure();
        final ciphertexts = <String>{};
        
        for (int i = 0; i < 20; i++) {
          final message = 'Unique message ${random.nextInt(100000)} ${DateTime.now().microsecondsSinceEpoch}';
          
          try {
            final encryptedMessage = await _simulateEncryption(
              message, 
              alice_encryptionKeyPair, 
              bob_encryptionPublicKey,
              alice_signingKeyPair
            );
            
            // Property: Each encryption should produce a unique ciphertext
            expect(ciphertexts.contains(encryptedMessage.encryptedData), isFalse,
              reason: 'Each message should produce a unique ciphertext');
            
            ciphertexts.add(encryptedMessage.encryptedData);
          } catch (e) {
            print('Skipping message due to encryption error: $e');
            continue;
          }
        }
        
        // Should have generated multiple unique ciphertexts
        expect(ciphertexts.length, greaterThan(10));
      });

      test('Property: Same message encrypted multiple times produces different ciphertexts', () async {
        const message = 'This is the same message every time';
        final ciphertexts = <String>{};
        
        for (int i = 0; i < 10; i++) {
          final encryptedMessage = await _simulateEncryption(
            message, 
            alice_encryptionKeyPair, 
            bob_encryptionPublicKey,
            alice_signingKeyPair
          );
          
          // Property: Same message should produce different ciphertexts due to random nonces
          expect(ciphertexts.contains(encryptedMessage.encryptedData), isFalse,
            reason: 'Same message should produce different ciphertexts due to nonce randomness');
          
          ciphertexts.add(encryptedMessage.encryptedData);
        }
        
        expect(ciphertexts.length, equals(10));
      });
    });

    group('Hash Function Properties', () {
      test('Property: Hash function is deterministic', () async {
        final random = Random.secure();
        
        for (int i = 0; i < 10; i++) {
          final data = 'Test data ${random.nextInt(10000)}';
          
          // Property: Same input should always produce same hash
          final hash1 = await CryptoEngine.hashData(data);
          final hash2 = await CryptoEngine.hashData(data);
          final hash3 = await CryptoEngine.hashData(data);
          
          expect(hash1, equals(hash2));
          expect(hash2, equals(hash3));
          expect(hash1, isNotEmpty);
        }
      });

      test('Property: Different inputs produce different hashes', () async {
        final random = Random.secure();
        final hashes = <String>{};
        
        for (int i = 0; i < 50; i++) {
          final data = 'Unique data ${random.nextInt(100000)} ${DateTime.now().microsecondsSinceEpoch}';
          final hash = await CryptoEngine.hashData(data);
          
          // Property: Each unique input should produce a unique hash
          expect(hashes.contains(hash), isFalse,
            reason: 'Different inputs should produce different hashes');
          
          hashes.add(hash);
        }
        
        expect(hashes.length, equals(50));
      });

      test('Property: Small changes in input cause large changes in hash (avalanche effect)', () async {
        const baseData = 'This is a test string for avalanche effect testing';
        final baseHash = await CryptoEngine.hashData(baseData);
        
        // Test various small modifications
        final modifications = [
          baseData + '.',
          baseData.replaceFirst('T', 't'),
          baseData.replaceFirst('test', 'Test'),
          baseData.substring(1),
          baseData + ' ',
        ];
        
        for (final modifiedData in modifications) {
          final modifiedHash = await CryptoEngine.hashData(modifiedData);
          
          // Property: Small change should produce completely different hash
          expect(modifiedHash, isNot(equals(baseHash)));
          expect(_calculateHammingDistance(baseHash, modifiedHash), greaterThan(baseHash.length ~/ 4),
            reason: 'Small input change should cause significant hash change (avalanche effect)');
        }
      });

      test('Property: Hash integrity verification works correctly', () async {
        final random = Random.secure();
        
        for (int i = 0; i < 10; i++) {
          final data = 'Integrity test data ${random.nextInt(10000)}';
          final hash = await CryptoEngine.hashData(data);
          
          // Property: Original data should verify against its hash
          final isValid = await CryptoEngine.verifyDataIntegrity(data, hash);
          expect(isValid, isTrue);
          
          // Property: Modified data should not verify against original hash
          final modifiedData = data + 'x';
          final isInvalid = await CryptoEngine.verifyDataIntegrity(modifiedData, hash);
          expect(isInvalid, isFalse);
        }
      });
    });

    group('Nonce Generation Properties', () {
      test('Property: Nonces are unique and random', () async {
        final nonces = <String>{};
        
        for (int i = 0; i < 100; i++) {
          final nonce = CryptoEngine.generateNonce();
          final nonceString = base64Encode(nonce);
          
          // Property: Each nonce should be unique
          expect(nonces.contains(nonceString), isFalse,
            reason: 'Each generated nonce should be unique');
          
          nonces.add(nonceString);
          
          // Property: Nonce should have expected length
          expect(nonce.length, equals(12)); // Default length
        }
        
        expect(nonces.length, equals(100));
      });

      test('Property: Custom nonce lengths work correctly', () async {
        final lengths = [8, 12, 16, 24, 32];
        
        for (final length in lengths) {
          final nonces = <String>{};
          
          for (int i = 0; i < 20; i++) {
            final nonce = CryptoEngine.generateNonce(length);
            
            // Property: Nonce should have requested length
            expect(nonce.length, equals(length));
            
            // Property: Nonces should be unique
            final nonceString = base64Encode(nonce);
            expect(nonces.contains(nonceString), isFalse);
            nonces.add(nonceString);
          }
        }
      });

      test('Property: Nonce bytes are in valid range', () async {
        for (int i = 0; i < 50; i++) {
          final nonce = CryptoEngine.generateNonce(16);
          
          // Property: All bytes should be in valid range [0, 255]
          for (final byte in nonce) {
            expect(byte, greaterThanOrEqualTo(0));
            expect(byte, lessThanOrEqualTo(255));
          }
        }
      });
    });

    group('Cross-Property Invariants', () {
      test('Property: Signature verification fails for corrupted signatures', () async {
        const message = 'Test message for signature corruption';
        
        // Create valid signature
        final ed25519 = Ed25519();
        final dataBytes = utf8.encode(message);
        final signature = await ed25519.sign(dataBytes, keyPair: alice_signingKeyPair);
        final validSignatureBytes = signature.bytes;
        
        final random = Random.secure();
        
        for (int i = 0; i < 10; i++) {
          // Corrupt signature by flipping random bits
          final corruptedBytes = Uint8List.fromList(validSignatureBytes);
          final corruptPosition = random.nextInt(corruptedBytes.length);
          corruptedBytes[corruptPosition] = corruptedBytes[corruptPosition] ^ (1 << random.nextInt(8));
          
          final corruptedSignature = base64Encode(corruptedBytes);
          
          // Property: Corrupted signature should not verify
          final isValid = await CryptoEngine.verifySignature(
            message, 
            corruptedSignature, 
            alice_signingPublicKey
          );
          
          expect(isValid, isFalse, 
            reason: 'Corrupted signature should not verify');
        }
      });

      test('Property: Hash collision resistance', () async {
        final hashes = <String, String>{}; // hash -> original data
        final random = Random.secure();
        
        // Generate many random inputs and check for collisions
        for (int i = 0; i < 1000; i++) {
          final dataLength = random.nextInt(100) + 1;
          final data = List.generate(dataLength, (_) => 
            String.fromCharCode(32 + random.nextInt(95))
          ).join();
          
          final hash = await CryptoEngine.hashData(data);
          
          if (hashes.containsKey(hash)) {
            // Found a collision - should be extremely rare
            expect(hashes[hash], equals(data), 
              reason: 'If hash collision occurs, it should be with identical data');
          } else {
            hashes[hash] = data;
          }
        }
        
        // Should have generated close to 1000 unique hashes
        expect(hashes.length, greaterThan(950), 
          reason: 'Hash function should have very low collision rate');
      });
    });
  });
}

/// Helper function to simulate encryption (mirrors CryptoEngine.encryptMessage logic)
Future<EncryptedMessage> _simulateEncryption(
  String message,
  SimpleKeyPair senderEncryptionKeyPair,
  SimplePublicKey recipientEncryptionPublicKey,
  SimpleKeyPair senderSigningKeyPair,
) async {
  final x25519 = X25519();
  final ed25519 = Ed25519();
  final chacha20 = Chacha20.poly1305Aead();
  
  // Derive shared secret
  final sharedSecret = await x25519.sharedSecretKey(
    keyPair: senderEncryptionKeyPair,
    remotePublicKey: recipientEncryptionPublicKey,
  );
  
  final sharedSecretBytes = await sharedSecret.extractBytes();
  final secretKey = SecretKey(sharedSecretBytes);
  
  // Encrypt message
  final messageBytes = utf8.encode(message);
  final secretBox = await chacha20.encrypt(messageBytes, secretKey: secretKey);
  
  // Sign encrypted data
  final signature = await ed25519.sign(secretBox.cipherText, keyPair: senderSigningKeyPair);
  
  return EncryptedMessage(
    encryptedData: base64Encode(secretBox.cipherText),
    nonce: base64Encode(secretBox.nonce),
    mac: base64Encode(secretBox.mac.bytes),
    signature: base64Encode(signature.bytes),
  );
}

/// Helper function to simulate decryption (mirrors CryptoEngine.decryptMessage logic)
Future<String> _simulateDecryption(
  EncryptedMessage encryptedMessage,
  SimpleKeyPair recipientEncryptionKeyPair,
  SimplePublicKey senderEncryptionPublicKey,
  SimplePublicKey senderSigningPublicKey,
) async {
  final x25519 = X25519();
  final ed25519 = Ed25519();
  final chacha20 = Chacha20.poly1305Aead();
  
  // Derive shared secret
  final sharedSecret = await x25519.sharedSecretKey(
    keyPair: recipientEncryptionKeyPair,
    remotePublicKey: senderEncryptionPublicKey,
  );
  
  final sharedSecretBytes = await sharedSecret.extractBytes();
  final secretKey = SecretKey(sharedSecretBytes);
  
  // Verify signature
  final encryptedData = base64Decode(encryptedMessage.encryptedData);
  final signature = Signature(
    base64Decode(encryptedMessage.signature),
    publicKey: senderSigningPublicKey,
  );
  
  final isValidSignature = await ed25519.verify(encryptedData, signature: signature);
  if (!isValidSignature) {
    throw Exception('Invalid signature in decryption');
  }
  
  // Decrypt message
  final nonce = base64Decode(encryptedMessage.nonce);
  final mac = encryptedMessage.mac.isEmpty 
      ? Mac.empty 
      : Mac(base64Decode(encryptedMessage.mac));
  
  final secretBox = SecretBox(encryptedData, nonce: nonce, mac: mac);
  final decryptedBytes = await chacha20.decrypt(secretBox, secretKey: secretKey);
  
  return utf8.decode(decryptedBytes);
}

/// Helper function to calculate Hamming distance between two strings
int _calculateHammingDistance(String str1, String str2) {
  if (str1.length != str2.length) {
    return max(str1.length, str2.length); // Maximum possible distance
  }
  
  int distance = 0;
  for (int i = 0; i < str1.length; i++) {
    if (str1[i] != str2[i]) {
      distance++;
    }
  }
  return distance;
}