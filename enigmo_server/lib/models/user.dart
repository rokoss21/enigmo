import 'dart:convert';

/// Модель пользователя на сервере
class User {
  final String id;
  final String publicSigningKey;
  final String publicEncryptionKey;
  final DateTime lastSeen;
  final bool isOnline;
  final String? nickname;

  User({
    required this.id,
    required this.publicSigningKey,
    required this.publicEncryptionKey,
    required this.lastSeen,
    this.isOnline = false,
    this.nickname,
  });

  /// Создает пользователя из JSON
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      publicSigningKey: json['publicSigningKey'] as String,
      publicEncryptionKey: json['publicEncryptionKey'] as String,
      lastSeen: DateTime.parse(json['lastSeen'] as String),
      isOnline: json['isOnline'] as bool? ?? false,
      nickname: json['nickname'] as String?,
    );
  }

  /// Конвертирует пользователя в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'publicSigningKey': publicSigningKey,
      'publicEncryptionKey': publicEncryptionKey,
      'lastSeen': lastSeen.toIso8601String(),
      'isOnline': isOnline,
      'nickname': nickname,
    };
  }

  /// Создает копию пользователя с обновленными полями
  User copyWith({
    String? id,
    String? publicSigningKey,
    String? publicEncryptionKey,
    DateTime? lastSeen,
    bool? isOnline,
    String? nickname,
  }) {
    return User(
      id: id ?? this.id,
      publicSigningKey: publicSigningKey ?? this.publicSigningKey,
      publicEncryptionKey: publicEncryptionKey ?? this.publicEncryptionKey,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
      nickname: nickname ?? this.nickname,
    );
  }

  @override
  String toString() {
    return 'User(id: $id, nickname: $nickname, isOnline: $isOnline)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is User && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}