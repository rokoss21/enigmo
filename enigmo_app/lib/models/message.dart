class Message {
  final String id;
  final String senderId;
  final String receiverId;
  final String content;
  final DateTime timestamp;
  final MessageType type;
  final MessageStatus status;
  final bool isEncrypted;

  Message({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.timestamp,
    this.type = MessageType.text,
    this.status = MessageStatus.sent,
    this.isEncrypted = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'type': type.toString(),
      'status': status.toString(),
      'isEncrypted': isEncrypted,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    // Support both plaintext 'content' (client) and 'encryptedContent' (server)
    final rawContent = json['content'] ?? json['encryptedContent'] ?? '';

    // Normalize enum string values: accept either 'MessageType.text' or just 'text'
    String _normalizeEnumName(dynamic value, String fallback) {
      final s = value?.toString() ?? fallback;
      final parts = s.split('.');
      return parts.isNotEmpty ? parts.last : fallback;
    }

    // Normalize type name and map server-specific to client enum names
    String typeName = _normalizeEnumName(json['type'], 'text');
    if (typeName == 'voice') typeName = 'audio';

    // Normalize status name; map server 'pending' to client 'sending'
    String statusName = _normalizeEnumName(json['status'], 'sent');
    if (statusName == 'pending') statusName = 'sending';

    return Message(
      id: json['id'],
      senderId: json['senderId'],
      receiverId: json['receiverId'],
      content: rawContent,
      timestamp: DateTime.parse(json['timestamp']),
      type: MessageType.values.firstWhere(
        (e) => e.name == typeName,
        orElse: () => MessageType.text,
      ),
      status: MessageStatus.values.firstWhere(
        (e) => e.name == statusName,
        orElse: () => MessageStatus.sent,
      ),
      isEncrypted: json['isEncrypted'] ?? (json['encryptedContent'] != null),
    );
  }
}

enum MessageType {
  text,
  image,
  audio,
  video,
  file,
}

enum MessageStatus {
  sending,
  sent,
  delivered,
  read,
  failed,
}