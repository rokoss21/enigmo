import '../models/user.dart';
import 'user_manager.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';
import 'dart:math';

/// User authentication service
class AuthService {
  final UserManager _userManager;

  AuthService(this._userManager);

  /// Authenticates a user by token (simplified path)
  User? authenticateUserByToken(String token) {
    return _userManager.getUserByToken(token);
  }

  /// Checks token validity
  bool isValidToken(String token) {
    return _userManager.getUserByToken(token) != null;
  }

  /// Generates a new token for a user
  String generateToken(String userId) {
    // Ensure uniqueness with microsecond precision and random component
    final now = DateTime.now();
    final timestamp = now.microsecondsSinceEpoch.toString();
    final random = Random().nextInt(1000000).toString().padLeft(6, '0');
    return 'token_${userId}_${timestamp}_$random';
  }

  /// Verifies Ed25519 signature for the timestamp string by the user with userId.
  /// Returns true if the signature is valid.
  Future<bool> verifySignature(
    String userId,
    String timestamp,
    String signatureBase64,
  ) async {
    final user = _userManager.getUser(userId);
    if (user == null || user.publicSigningKey.isEmpty) {
      return false;
    }

    try {
      final publicKeyBytes = base64Decode(user.publicSigningKey);
      final signatureBytes = base64Decode(signatureBase64);
      final message = utf8.encode(timestamp);

      final algorithm = Ed25519();
      final publicKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519);
      final signature = Signature(signatureBytes, publicKey: publicKey);

      return await algorithm.verify(message, signature: signature);
    } catch (_) {
      return false;
    }
  }

  /// Modern authentication: verify signature validity and timestamp freshness.
  /// The timestamp must be no older than 5 minutes.
  Future<bool> authenticateUser(
    String userId,
    String signatureBase64,
    String timestamp,
  ) async {
    // Ensure the user exists
    final user = _userManager.getUser(userId);
    if (user == null) return false;

    // Check timestamp freshness (allow only up to 5 minutes in the past)
    try {
      final ts = DateTime.parse(timestamp);
      final now = DateTime.now();
      if (now.difference(ts) > const Duration(minutes: 5)) {
        return false;
      }
    } catch (_) {
      return false;
    }

    // Verify signature
    final ok = await verifySignature(userId, timestamp, signatureBase64);
    if (!ok) return false;

    // Mark the user as authenticated (online)
    await _userManager.authenticateUser(userId);
    return true;
  }

  /// Checks if the user can be authenticated (i.e., exists)
  Future<bool> canAuthenticate(String userId) async {
    return _userManager.getUser(userId) != null;
  }
}