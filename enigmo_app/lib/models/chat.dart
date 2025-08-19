import 'message.dart';

class Chat {
  final String id;
  final String name;
  final String? avatarUrl;
  final List<String> participants;
  final Message? lastMessage;
  final int unreadCount;
  final DateTime lastActivity;
  final ChatType type;
  final bool isOnline;

  Chat({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.participants,
    this.lastMessage,
    this.unreadCount = 0,
    required this.lastActivity,
    this.type = ChatType.direct,
    this.isOnline = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatarUrl': avatarUrl,
      'participants': participants,
      'lastMessage': lastMessage?.toJson(),
      'unreadCount': unreadCount,
      'lastActivity': lastActivity.toIso8601String(),
      'type': type.toString(),
      'isOnline': isOnline,
    };
  }

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'],
      name: json['name'],
      avatarUrl: json['avatarUrl'],
      participants: List<String>.from(json['participants']),
      lastMessage: json['lastMessage'] != null
          ? Message.fromJson(json['lastMessage'])
          : null,
      unreadCount: json['unreadCount'] ?? 0,
      lastActivity: DateTime.parse(json['lastActivity']),
      type: ChatType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => ChatType.direct,
      ),
      isOnline: json['isOnline'] ?? false,
    );
  }

  Chat copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    List<String>? participants,
    Message? lastMessage,
    int? unreadCount,
    DateTime? lastActivity,
    ChatType? type,
    bool? isOnline,
  }) {
    return Chat(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      participants: participants ?? this.participants,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      lastActivity: lastActivity ?? this.lastActivity,
      type: type ?? this.type,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}

enum ChatType {
  direct,
  group,
  channel,
}