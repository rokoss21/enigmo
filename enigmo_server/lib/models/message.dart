import 'dart:convert';

/// Типы сообщений
enum MessageType {
  text,
  image,
  file,
  voice,
  video,
  system,
}

/// Статус доставки сообщения
enum DeliveryStatus {
  pending,
  sent,
  delivered,
  read,
  failed,
}

/// Модель сообщения на сервере
class ServerMessage {
  final String id;
  final String senderId;
  final String receiverId;
  final String encryptedContent;
  final String signature;
  final MessageType type;
  final DateTime timestamp;
  final DeliveryStatus status;
  final Map<String, dynamic>? metadata;

  ServerMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.encryptedContent,
    required this.signature,
    required this.type,
    required this.timestamp,
    this.status = DeliveryStatus.pending,
    this.metadata,
  });

  /// Создает сообщение из JSON
  factory ServerMessage.fromJson(Map<String, dynamic> json) {
    return ServerMessage(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      receiverId: json['receiverId'] as String,
      encryptedContent: json['encryptedContent'] as String,
      signature: json['signature'] as String,
      type: MessageType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MessageType.text,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: DeliveryStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DeliveryStatus.pending,
      ),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Конвертирует сообщение в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'encryptedContent': encryptedContent,
      'signature': signature,
      'type': type.name,
      'timestamp': timestamp.toIso8601String(),
      'status': status.name,
      'metadata': metadata,
    };
  }

  /// Создает копию сообщения с обновленным статусом
  ServerMessage copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? encryptedContent,
    String? signature,
    MessageType? type,
    DateTime? timestamp,
    DeliveryStatus? status,
    Map<String, dynamic>? metadata,
  }) {
    return ServerMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      encryptedContent: encryptedContent ?? this.encryptedContent,
      signature: signature ?? this.signature,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() {
    return 'ServerMessage(id: $id, from: $senderId, to: $receiverId, status: $status)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ServerMessage && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}