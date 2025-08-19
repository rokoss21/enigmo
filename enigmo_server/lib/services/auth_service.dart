import '../models/user.dart';
import 'user_manager.dart';
import 'package:cryptography/cryptography.dart';
import 'dart:convert';

/// Сервис аутентификации пользователей
class AuthService {
  final UserManager _userManager;

  AuthService(this._userManager);

  /// Аутентифицирует пользователя по токену (упрощенный путь)
  User? authenticateUserByToken(String token) {
    return _userManager.getUserByToken(token);
  }

  /// Проверяет валидность токена
  bool isValidToken(String token) {
    return _userManager.getUserByToken(token) != null;
  }

  /// Генерирует новый токен для пользователя
  String generateToken(String userId) {
    // Простая генерация токена (в реальном приложении должна быть более безопасной)
    return 'token_${userId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Проверяет подпись Ed25519 для строки timestamp пользователем userId
  /// Возвращает true, если подпись валидна.
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

  /// Современная аутентификация: проверка валидности подписи и актуальности timestamp
  /// timestamp должен быть не старше 5 минут.
  Future<bool> authenticateUser(
    String userId,
    String signatureBase64,
    String timestamp,
  ) async {
    // Проверяем, что пользователь существует
    final user = _userManager.getUser(userId);
    if (user == null) return false;

    // Проверка свежести timestamp (±5 минут допускаем только в прошлое)
    try {
      final ts = DateTime.parse(timestamp);
      final now = DateTime.now();
      if (now.difference(ts) > const Duration(minutes: 5)) {
        return false;
      }
    } catch (_) {
      return false;
    }

    // Проверяем подпись
    final ok = await verifySignature(userId, timestamp, signatureBase64);
    if (!ok) return false;

    // Помечаем пользователя как прошедшего аутентификацию (онлайн)
    await _userManager.authenticateUser(userId);
    return true;
  }

  /// Можно ли аутентифицировать пользователя (существует ли он)
  Future<bool> canAuthenticate(String userId) async {
    return _userManager.getUser(userId) != null;
  }
}