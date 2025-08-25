import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enigmo_app/widgets/message_bubble.dart';
import 'package:enigmo_app/models/message.dart';

void main() {
  group('MessageBubble Widget Tests', () {
    group('Widget Creation and Basic Properties', () {
      testWidgets('should create MessageBubble widget', (WidgetTester tester) async {
        final message = Message(
          id: 'test_msg_1',
          senderId: 'user_1',
          receiverId: 'user_2',
          content: 'Test message',
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: true),
            ),
          ),
        );

        expect(find.byType(MessageBubble), findsOneWidget);
        expect(find.text('Test message'), findsOneWidget);
      });

      testWidgets('should display message content correctly', (WidgetTester tester) async {
        const testContent = 'Hello, this is a test message!';
        final message = Message(
          id: 'test_msg_2',
          senderId: 'user_1',
          receiverId: 'user_2',
          content: testContent,
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: false),
            ),
          ),
        );

        expect(find.text(testContent), findsOneWidget);
      });
    });

    group('Styling and Appearance', () {
      testWidgets('should apply correct styling for own messages (isMe: true)', (WidgetTester tester) async {
        final message = Message(
          id: 'my_msg',
          senderId: 'me',
          receiverId: 'other',
          content: 'My message',
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: true),
            ),
          ),
        );

        // Find the container with styling
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(MessageBubble),
            matching: find.byType(Container),
          ).first,
        );

        final decoration = container.decoration as BoxDecoration;
        expect(decoration.color, equals(Colors.white));
        expect(decoration.border?.top.color, equals(Colors.black));
      });

      testWidgets('should apply correct styling for other messages (isMe: false)', (WidgetTester tester) async {
        final message = Message(
          id: 'other_msg',
          senderId: 'other',
          receiverId: 'me',
          content: 'Other message',
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: false),
            ),
          ),
        );

        // Find the container with styling
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(MessageBubble),
            matching: find.byType(Container),
          ).first,
        );

        final decoration = container.decoration as BoxDecoration;
        expect(decoration.color, equals(Colors.black));
        expect(decoration.border?.top.color, equals(Colors.white));
      });

      testWidgets('should align own messages to the right', (WidgetTester tester) async {
        final message = Message(
          id: 'align_test_my',
          senderId: 'me',
          receiverId: 'other',
          content: 'Right aligned',
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: true),
            ),
          ),
        );

        final align = tester.widget<Align>(find.byType(Align));
        expect(align.alignment, equals(Alignment.centerRight));
      });

      testWidgets('should align other messages to the left', (WidgetTester tester) async {
        final message = Message(
          id: 'align_test_other',
          senderId: 'other',
          receiverId: 'me',
          content: 'Left aligned',
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: false),
            ),
          ),
        );

        final align = tester.widget<Align>(find.byType(Align));
        expect(align.alignment, equals(Alignment.centerLeft));
      });
    });

    group('Text Color and Readability', () {
      testWidgets('should use black text on white background for own messages', (WidgetTester tester) async {
        final message = Message(
          id: 'color_test_my',
          senderId: 'me',
          receiverId: 'other',
          content: 'Black text message',
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: true),
            ),
          ),
        );

        final textWidget = tester.widget<Text>(
          find.text('Black text message'),
        );
        expect(textWidget.style?.color, equals(Colors.black));
      });

      testWidgets('should use white text on black background for other messages', (WidgetTester tester) async {
        final message = Message(
          id: 'color_test_other',
          senderId: 'other',
          receiverId: 'me',
          content: 'White text message',
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: false),
            ),
          ),
        );

        final textWidget = tester.widget<Text>(
          find.text('White text message'),
        );
        expect(textWidget.style?.color, equals(Colors.white));
      });
    });

    group('Timestamp Display', () {
      testWidgets('should display formatted timestamp', (WidgetTester tester) async {
        final timestamp = DateTime(2024, 1, 1, 14, 30, 45);
        final message = Message(
          id: 'timestamp_test',
          senderId: 'user',
          receiverId: 'other',
          content: 'Timestamp test',
          timestamp: timestamp,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: true),
            ),
          ),
        );

        expect(find.text('14:30'), findsOneWidget);
      });

      testWidgets('should format timestamp with leading zeros', (WidgetTester tester) async {
        final timestamp = DateTime(2024, 1, 1, 9, 5, 0);
        final message = Message(
          id: 'timestamp_zero_test',
          senderId: 'user',
          receiverId: 'other',
          content: 'Zero padding test',
          timestamp: timestamp,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: false),
            ),
          ),
        );

        expect(find.text('09:05'), findsOneWidget);
      });

      testWidgets('should handle midnight timestamp', (WidgetTester tester) async {
        final timestamp = DateTime(2024, 1, 1, 0, 0, 0);
        final message = Message(
          id: 'midnight_test',
          senderId: 'user',
          receiverId: 'other',
          content: 'Midnight test',
          timestamp: timestamp,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: true),
            ),
          ),
        );

        expect(find.text('00:00'), findsOneWidget);
      });

      testWidgets('should handle late night timestamp', (WidgetTester tester) async {
        final timestamp = DateTime(2024, 1, 1, 23, 59, 59);
        final message = Message(
          id: 'late_night_test',
          senderId: 'user',
          receiverId: 'other',
          content: 'Late night test',
          timestamp: timestamp,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: false),
            ),
          ),
        );

        expect(find.text('23:59'), findsOneWidget);
      });
    });

    group('Message Status Icons', () {
      testWidgets('should show read status icon for own read messages', (WidgetTester tester) async {
        final message = Message(
          id: 'read_status_test',
          senderId: 'me',
          receiverId: 'other',
          content: 'Read message',
          timestamp: DateTime.now(),
          status: MessageStatus.read,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: true),
            ),
          ),
        );

        expect(find.byIcon(Icons.done_all), findsOneWidget);
      });

      testWidgets('should show sent status icon for own sent messages', (WidgetTester tester) async {
        final message = Message(
          id: 'sent_status_test',
          senderId: 'me',
          receiverId: 'other',
          content: 'Sent message',
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: true),
            ),
          ),
        );

        expect(find.byIcon(Icons.done), findsOneWidget);
      });

      testWidgets('should show delivered status icon for own delivered messages', (WidgetTester tester) async {
        final message = Message(
          id: 'delivered_status_test',
          senderId: 'me',
          receiverId: 'other',
          content: 'Delivered message',
          timestamp: DateTime.now(),
          status: MessageStatus.delivered,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: true),
            ),
          ),
        );

        expect(find.byIcon(Icons.done), findsOneWidget);
      });

      testWidgets('should not show status icons for other messages', (WidgetTester tester) async {
        final message = Message(
          id: 'other_status_test',
          senderId: 'other',
          receiverId: 'me',
          content: 'Other message',
          timestamp: DateTime.now(),
          status: MessageStatus.read,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: false),
            ),
          ),
        );

        expect(find.byIcon(Icons.done_all), findsNothing);
        expect(find.byIcon(Icons.done), findsNothing);
      });
    });

    group('Content Handling and Edge Cases', () {
      testWidgets('should handle empty message content', (WidgetTester tester) async {
        final message = Message(
          id: 'empty_content_test',
          senderId: 'user',
          receiverId: 'other',
          content: '',
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: true),
            ),
          ),
        );

        expect(find.byType(MessageBubble), findsOneWidget);
        expect(find.text(''), findsOneWidget);
      });

      testWidgets('should handle very long message content', (WidgetTester tester) async {
        final longContent = 'This is a very long message content that should wrap properly and not overflow the screen boundaries. ' * 5;
        final message = Message(
          id: 'long_content_test',
          senderId: 'user',
          receiverId: 'other',
          content: longContent,
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MessageBubble(message: message, isMe: false),
              ),
            ),
          ),
        );

        expect(find.byType(MessageBubble), findsOneWidget);
        expect(find.textContaining('This is a very long message'), findsOneWidget);
      });

      testWidgets('should handle special characters in message', (WidgetTester tester) async {
        const specialContent = 'Special chars: @#\$%^&*()_+-=[]{}|;:,.<>?/~`';
        final message = Message(
          id: 'special_chars_test',
          senderId: 'user',
          receiverId: 'other',
          content: specialContent,
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: true),
            ),
          ),
        );

        expect(find.text(specialContent), findsOneWidget);
      });

      testWidgets('should handle Unicode and emoji content', (WidgetTester tester) async {
        const unicodeContent = 'Hello 🌍 世界 🚀 Привет मुझे 🎉';
        final message = Message(
          id: 'unicode_test',
          senderId: 'user',
          receiverId: 'other',
          content: unicodeContent,
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: false),
            ),
          ),
        );

        expect(find.text(unicodeContent), findsOneWidget);
      });

      testWidgets('should handle newlines in message content', (WidgetTester tester) async {
        const multilineContent = 'First line\\nSecond line\\nThird line';
        final message = Message(
          id: 'multiline_test',
          senderId: 'user',
          receiverId: 'other',
          content: multilineContent,
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: true),
            ),
          ),
        );

        expect(find.text(multilineContent), findsOneWidget);
      });
    });

    group('Layout and Constraints', () {
      testWidgets('should respect maximum width constraint', (WidgetTester tester) async {
        // Set a specific screen size
        tester.binding.window.physicalSizeTestValue = const Size(400, 800);
        tester.binding.window.devicePixelRatioTestValue = 1.0;

        final message = Message(
          id: 'width_constraint_test',
          senderId: 'user',
          receiverId: 'other',
          content: 'Test message for width constraint',
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: true),
            ),
          ),
        );

        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(MessageBubble),
            matching: find.byType(Container),
          ).first,
        );

        final constraints = container.constraints;
        expect(constraints?.maxWidth, equals(400 * 0.78)); // 78% of screen width

        // Clean up
        addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
        addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);
      });

      testWidgets('should have proper padding and margins', (WidgetTester tester) async {
        final message = Message(
          id: 'padding_test',
          senderId: 'user',
          receiverId: 'other',
          content: 'Padding test',
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: true),
            ),
          ),
        );

        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(MessageBubble),
            matching: find.byType(Container),
          ).first,
        );

        expect(container.margin, equals(const EdgeInsets.symmetric(vertical: 4, horizontal: 8)));
        expect(container.padding, equals(const EdgeInsets.symmetric(vertical: 10, horizontal: 14)));
      });
    });

    group('Border Radius and Shape', () {
      testWidgets('should have correct border radius for own messages', (WidgetTester tester) async {
        final message = Message(
          id: 'border_radius_my_test',
          senderId: 'me',
          receiverId: 'other',
          content: 'My border test',
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: true),
            ),
          ),
        );

        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(MessageBubble),
            matching: find.byType(Container),
          ).first,
        );

        final decoration = container.decoration as BoxDecoration;
        final borderRadius = decoration.borderRadius as BorderRadius;

        expect(borderRadius.topLeft, equals(const Radius.circular(18)));
        expect(borderRadius.topRight, equals(const Radius.circular(18)));
        expect(borderRadius.bottomLeft, equals(const Radius.circular(18)));
        expect(borderRadius.bottomRight, equals(const Radius.circular(6)));
      });

      testWidgets('should have correct border radius for other messages', (WidgetTester tester) async {
        final message = Message(
          id: 'border_radius_other_test',
          senderId: 'other',
          receiverId: 'me',
          content: 'Other border test',
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: false),
            ),
          ),
        );

        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(MessageBubble),
            matching: find.byType(Container),
          ).first,
        );

        final decoration = container.decoration as BoxDecoration;
        final borderRadius = decoration.borderRadius as BorderRadius;

        expect(borderRadius.topLeft, equals(const Radius.circular(18)));
        expect(borderRadius.topRight, equals(const Radius.circular(18)));
        expect(borderRadius.bottomLeft, equals(const Radius.circular(6)));
        expect(borderRadius.bottomRight, equals(const Radius.circular(18)));
      });
    });

    group('Accessibility', () {
      testWidgets('should be accessible for screen readers', (WidgetTester tester) async {
        final message = Message(
          id: 'accessibility_test',
          senderId: 'user',
          receiverId: 'other',
          content: 'Accessibility test message',
          timestamp: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(message: message, isMe: true),
            ),
          ),
        );

        // Widget should be found and have text content
        expect(find.byType(MessageBubble), findsOneWidget);
        expect(find.text('Accessibility test message'), findsOneWidget);
      });
    });

    group('Performance', () {
      testWidgets('should handle rapid rebuilds efficiently', (WidgetTester tester) async {
        final message = Message(
          id: 'performance_test',
          senderId: 'user',
          receiverId: 'other',
          content: 'Performance test',
          timestamp: DateTime.now(),
        );

        // Perform multiple rebuilds
        for (int i = 0; i < 100; i++) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: MessageBubble(message: message, isMe: i % 2 == 0),
              ),
            ),
          );
        }

        expect(find.byType(MessageBubble), findsOneWidget);
        expect(find.text('Performance test'), findsOneWidget);
      });
    });
  });
}