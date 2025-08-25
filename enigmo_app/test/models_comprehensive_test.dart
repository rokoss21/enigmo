import 'package:flutter_test/flutter_test.dart';
import 'package:enigmo_app/models/chat.dart';
import 'package:enigmo_app/models/message.dart';

void main() {
  group('Message Model Tests', () {
    group('Message Creation and Properties', () {
      test('should create a message with all properties', () {
        final timestamp = DateTime.now();
        final message = Message(
          id: 'msg_123',
          senderId: 'user_1',
          receiverId: 'user_2',
          content: 'Hello World',
          timestamp: timestamp,
          type: MessageType.text,
          status: MessageStatus.sent,
          isEncrypted: true,
        );

        expect(message.id, equals('msg_123'));
        expect(message.senderId, equals('user_1'));
        expect(message.receiverId, equals('user_2'));
        expect(message.content, equals('Hello World'));
        expect(message.timestamp, equals(timestamp));
        expect(message.type, equals(MessageType.text));
        expect(message.status, equals(MessageStatus.sent));
        expect(message.isEncrypted, isTrue);
      });

      test('should create a message with default values', () {
        final timestamp = DateTime.now();
        final message = Message(
          id: 'msg_456',
          senderId: 'user_1',
          receiverId: 'user_2',
          content: 'Default message',
          timestamp: timestamp,
        );

        expect(message.type, equals(MessageType.text));
        expect(message.status, equals(MessageStatus.sent));
        expect(message.isEncrypted, isTrue);
      });
    });

    group('Message Serialization', () {
      test('should serialize to JSON correctly', () {
        final timestamp = DateTime.parse('2024-01-01T12:00:00.000Z');
        final message = Message(
          id: 'msg_json',
          senderId: 'sender_1',
          receiverId: 'receiver_1',
          content: 'JSON test message',
          timestamp: timestamp,
          type: MessageType.image,
          status: MessageStatus.delivered,
          isEncrypted: false,
        );

        final json = message.toJson();

        expect(json['id'], equals('msg_json'));
        expect(json['senderId'], equals('sender_1'));
        expect(json['receiverId'], equals('receiver_1'));
        expect(json['content'], equals('JSON test message'));
        expect(json['timestamp'], equals('2024-01-01T12:00:00.000Z'));
        expect(json['type'], equals('MessageType.image'));
        expect(json['status'], equals('MessageStatus.delivered'));
        expect(json['isEncrypted'], equals(false));
      });

      test('should deserialize from JSON correctly', () {
        final json = {
          'id': 'msg_deserialize',
          'senderId': 'sender_2',
          'receiverId': 'receiver_2',
          'content': 'Deserialized message',
          'timestamp': '2024-01-02T12:00:00.000Z',
          'type': 'MessageType.audio',
          'status': 'MessageStatus.read',
          'isEncrypted': true,
        };

        final message = Message.fromJson(json);

        expect(message.id, equals('msg_deserialize'));
        expect(message.senderId, equals('sender_2'));
        expect(message.receiverId, equals('receiver_2'));
        expect(message.content, equals('Deserialized message'));
        expect(message.timestamp, equals(DateTime.parse('2024-01-02T12:00:00.000Z')));
        expect(message.type, equals(MessageType.audio));
        expect(message.status, equals(MessageStatus.read));
        expect(message.isEncrypted, isTrue);
      });

      test('should handle server-style JSON with encryptedContent', () {
        final json = {
          'id': 'msg_server',
          'senderId': 'sender_3',
          'receiverId': 'receiver_3',
          'encryptedContent': 'Encrypted server message',
          'timestamp': '2024-01-03T12:00:00.000Z',
          'type': 'voice',
          'status': 'pending',
          'isEncrypted': true,
        };

        final message = Message.fromJson(json);

        expect(message.content, equals('Encrypted server message'));
        expect(message.type, equals(MessageType.audio)); // voice -> audio
        expect(message.status, equals(MessageStatus.sending)); // pending -> sending
        expect(message.isEncrypted, isTrue);
      });

      test('should handle missing optional fields', () {
        final json = {
          'id': 'msg_minimal',
          'senderId': 'sender_4',
          'receiverId': 'receiver_4',
          'timestamp': '2024-01-04T12:00:00.000Z',
        };

        final message = Message.fromJson(json);

        expect(message.content, equals(''));
        expect(message.type, equals(MessageType.text));
        expect(message.status, equals(MessageStatus.sent));
        expect(message.isEncrypted, isFalse);
      });

      test('should normalize enum values correctly', () {
        final json = {
          'id': 'msg_enum',
          'senderId': 'sender_5',
          'receiverId': 'receiver_5',
          'content': 'Enum test',
          'timestamp': '2024-01-05T12:00:00.000Z',
          'type': 'video',
          'status': 'failed',
        };

        final message = Message.fromJson(json);

        expect(message.type, equals(MessageType.video));
        expect(message.status, equals(MessageStatus.failed));
      });
    });

    group('Message Types and Status', () {
      test('should support all message types', () {
        final types = [
          MessageType.text,
          MessageType.image,
          MessageType.audio,
          MessageType.video,
          MessageType.file,
        ];

        for (final type in types) {
          final message = Message(
            id: 'msg_${type.name}',
            senderId: 'sender',
            receiverId: 'receiver',
            content: 'Test content',
            timestamp: DateTime.now(),
            type: type,
          );
          expect(message.type, equals(type));
        }
      });

      test('should support all message statuses', () {
        final statuses = [
          MessageStatus.sending,
          MessageStatus.sent,
          MessageStatus.delivered,
          MessageStatus.read,
          MessageStatus.failed,
        ];

        for (final status in statuses) {
          final message = Message(
            id: 'msg_${status.name}',
            senderId: 'sender',
            receiverId: 'receiver',
            content: 'Test content',
            timestamp: DateTime.now(),
            status: status,
          );
          expect(message.status, equals(status));
        }
      });
    });

    group('Edge Cases and Validation', () {
      test('should handle empty content', () {
        final message = Message(
          id: 'msg_empty',
          senderId: 'sender',
          receiverId: 'receiver',
          content: '',
          timestamp: DateTime.now(),
        );

        expect(message.content, equals(''));
      });

      test('should handle very long content', () {
        final longContent = 'A' * 10000;
        final message = Message(
          id: 'msg_long',
          senderId: 'sender',
          receiverId: 'receiver',
          content: longContent,
          timestamp: DateTime.now(),
        );

        expect(message.content.length, equals(10000));
      });

      test('should handle special characters in content', () {
        const specialContent = 'Special: @#%^&*()_+-=[]{}|;:,.<>?/~`';
        final message = Message(
          id: 'msg_special',
          senderId: 'sender',
          receiverId: 'receiver',
          content: specialContent,
          timestamp: DateTime.now(),
        );

        expect(message.content, equals(specialContent));
      });

      test('should handle Unicode and emoji content', () {
        const unicodeContent = 'Hello 🌍 世界 🚀 Привет मुझे';
        final message = Message(
          id: 'msg_unicode',
          senderId: 'sender',
          receiverId: 'receiver',
          content: unicodeContent,
          timestamp: DateTime.now(),
        );

        expect(message.content, equals(unicodeContent));
      });
    });
  });

  group('Chat Model Tests', () {
    group('Chat Creation and Properties', () {
      test('should create a chat with all properties', () {
        final lastActivity = DateTime.now();
        final lastMessage = Message(
          id: 'last_msg',
          senderId: 'user_1',
          receiverId: 'user_2',
          content: 'Last message',
          timestamp: lastActivity,
        );

        final chat = Chat(
          id: 'chat_123',
          name: 'Test Chat',
          avatarUrl: 'https://example.com/avatar.jpg',
          participants: ['user_1', 'user_2'],
          lastMessage: lastMessage,
          unreadCount: 5,
          lastActivity: lastActivity,
          type: ChatType.group,
          isOnline: true,
        );

        expect(chat.id, equals('chat_123'));
        expect(chat.name, equals('Test Chat'));
        expect(chat.avatarUrl, equals('https://example.com/avatar.jpg'));
        expect(chat.participants, equals(['user_1', 'user_2']));
        expect(chat.lastMessage, equals(lastMessage));
        expect(chat.unreadCount, equals(5));
        expect(chat.lastActivity, equals(lastActivity));
        expect(chat.type, equals(ChatType.group));
        expect(chat.isOnline, isTrue);
      });

      test('should create a chat with default values', () {
        final lastActivity = DateTime.now();
        final chat = Chat(
          id: 'chat_456',
          name: 'Default Chat',
          participants: ['user_1'],
          lastActivity: lastActivity,
        );

        expect(chat.avatarUrl, isNull);
        expect(chat.lastMessage, isNull);
        expect(chat.unreadCount, equals(0));
        expect(chat.type, equals(ChatType.direct));
        expect(chat.isOnline, isFalse);
      });
    });

    group('Chat Serialization', () {
      test('should serialize to JSON correctly', () {
        final lastActivity = DateTime.parse('2024-01-01T12:00:00.000Z');
        final lastMessage = Message(
          id: 'last_msg_json',
          senderId: 'user_1',
          receiverId: 'user_2',
          content: 'Last message content',
          timestamp: lastActivity,
        );

        final chat = Chat(
          id: 'chat_json',
          name: 'JSON Chat',
          avatarUrl: 'https://example.com/avatar.jpg',
          participants: ['user_1', 'user_2', 'user_3'],
          lastMessage: lastMessage,
          unreadCount: 3,
          lastActivity: lastActivity,
          type: ChatType.channel,
          isOnline: true,
        );

        final json = chat.toJson();

        expect(json['id'], equals('chat_json'));
        expect(json['name'], equals('JSON Chat'));
        expect(json['avatarUrl'], equals('https://example.com/avatar.jpg'));
        expect(json['participants'], equals(['user_1', 'user_2', 'user_3']));
        expect(json['lastMessage'], isA<Map>());
        expect(json['unreadCount'], equals(3));
        expect(json['lastActivity'], equals('2024-01-01T12:00:00.000Z'));
        expect(json['type'], equals('ChatType.channel'));
        expect(json['isOnline'], equals(true));
      });

      test('should deserialize from JSON correctly', () {
        final json = {
          'id': 'chat_deserialize',
          'name': 'Deserialized Chat',
          'avatarUrl': 'https://example.com/avatar2.jpg',
          'participants': ['user_1', 'user_2'],
          'lastMessage': {
            'id': 'last_msg_deserialize',
            'senderId': 'user_1',
            'receiverId': 'user_2',
            'content': 'Last message',
            'timestamp': '2024-01-02T12:00:00.000Z',
          },
          'unreadCount': 7,
          'lastActivity': '2024-01-02T12:00:00.000Z',
          'type': 'ChatType.group',
          'isOnline': false,
        };

        final chat = Chat.fromJson(json);

        expect(chat.id, equals('chat_deserialize'));
        expect(chat.name, equals('Deserialized Chat'));
        expect(chat.avatarUrl, equals('https://example.com/avatar2.jpg'));
        expect(chat.participants, equals(['user_1', 'user_2']));
        expect(chat.lastMessage, isNotNull);
        expect(chat.lastMessage!.content, equals('Last message'));
        expect(chat.unreadCount, equals(7));
        expect(chat.lastActivity, equals(DateTime.parse('2024-01-02T12:00:00.000Z')));
        expect(chat.type, equals(ChatType.group));
        expect(chat.isOnline, isFalse);
      });

      test('should handle missing optional fields in JSON', () {
        final json = {
          'id': 'chat_minimal',
          'name': 'Minimal Chat',
          'participants': ['user_1'],
          'lastActivity': '2024-01-03T12:00:00.000Z',
        };

        final chat = Chat.fromJson(json);

        expect(chat.avatarUrl, isNull);
        expect(chat.lastMessage, isNull);
        expect(chat.unreadCount, equals(0));
        expect(chat.type, equals(ChatType.direct));
        expect(chat.isOnline, isFalse);
      });

      test('should handle unknown chat type gracefully', () {
        final json = {
          'id': 'chat_unknown_type',
          'name': 'Unknown Type Chat',
          'participants': ['user_1'],
          'lastActivity': '2024-01-04T12:00:00.000Z',
          'type': 'ChatType.unknown',
        };

        final chat = Chat.fromJson(json);

        expect(chat.type, equals(ChatType.direct)); // fallback to direct
      });
    });

    group('Chat Types', () {
      test('should support all chat types', () {
        final types = [ChatType.direct, ChatType.group, ChatType.channel];

        for (final type in types) {
          final chat = Chat(
            id: 'chat_${type.name}',
            name: 'Test Chat',
            participants: ['user_1'],
            lastActivity: DateTime.now(),
            type: type,
          );
          expect(chat.type, equals(type));
        }
      });
    });

    group('Chat CopyWith', () {
      test('should copy chat with modified properties', () {
        final originalChat = Chat(
          id: 'original_chat',
          name: 'Original Name',
          participants: ['user_1'],
          lastActivity: DateTime.now(),
          unreadCount: 5,
          isOnline: false,
        );

        final modifiedChat = originalChat.copyWith(
          name: 'Modified Name',
          unreadCount: 10,
          isOnline: true,
        );

        expect(modifiedChat.id, equals('original_chat')); // unchanged
        expect(modifiedChat.name, equals('Modified Name')); // changed
        expect(modifiedChat.participants, equals(['user_1'])); // unchanged
        expect(modifiedChat.unreadCount, equals(10)); // changed
        expect(modifiedChat.isOnline, isTrue); // changed
      });

      test('should copy chat without changes when no parameters provided', () {
        final originalChat = Chat(
          id: 'copy_test_chat',
          name: 'Copy Test',
          participants: ['user_1'],
          lastActivity: DateTime.now(),
        );

        final copiedChat = originalChat.copyWith();

        expect(copiedChat.id, equals(originalChat.id));
        expect(copiedChat.name, equals(originalChat.name));
        expect(copiedChat.participants, equals(originalChat.participants));
        expect(copiedChat.lastActivity, equals(originalChat.lastActivity));
      });
    });

    group('Edge Cases and Validation', () {
      test('should handle empty participants list', () {
        final chat = Chat(
          id: 'chat_empty_participants',
          name: 'Empty Participants Chat',
          participants: [],
          lastActivity: DateTime.now(),
        );

        expect(chat.participants, isEmpty);
      });

      test('should handle very long participant lists', () {
        final manyParticipants = List.generate(1000, (i) => 'user_$i');
        final chat = Chat(
          id: 'chat_many_participants',
          name: 'Many Participants Chat',
          participants: manyParticipants,
          lastActivity: DateTime.now(),
        );

        expect(chat.participants.length, equals(1000));
      });

      test('should handle special characters in chat name', () {
        const specialName = 'Special Chat: @#%^&*()_+-=[]{}|;:,.<>?/~`';
        final chat = Chat(
          id: 'chat_special_name',
          name: specialName,
          participants: ['user_1'],
          lastActivity: DateTime.now(),
        );

        expect(chat.name, equals(specialName));
      });

      test('should handle Unicode and emoji in chat name', () {
        const unicodeName = '🚀 Chat 世界 Группа 📱';
        final chat = Chat(
          id: 'chat_unicode_name',
          name: unicodeName,
          participants: ['user_1'],
          lastActivity: DateTime.now(),
        );

        expect(chat.name, equals(unicodeName));
      });

      test('should handle negative unread count', () {
        final chat = Chat(
          id: 'chat_negative_unread',
          name: 'Negative Unread Chat',
          participants: ['user_1'],
          lastActivity: DateTime.now(),
          unreadCount: -5,
        );

        expect(chat.unreadCount, equals(-5)); // Model should accept any int
      });

      test('should handle very large unread count', () {
        final chat = Chat(
          id: 'chat_large_unread',
          name: 'Large Unread Chat',
          participants: ['user_1'],
          lastActivity: DateTime.now(),
          unreadCount: 999999,
        );

        expect(chat.unreadCount, equals(999999));
      });
    });
  });
}