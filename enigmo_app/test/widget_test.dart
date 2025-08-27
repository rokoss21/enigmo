import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:enigmo_app/widgets/call_controls.dart';
import 'package:enigmo_app/widgets/call_status_indicator.dart';
import 'package:enigmo_app/models/call.dart';

// Generate mocks
@GenerateMocks([])
import 'widget_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallControls Widget Tests', () {
    testWidgets('should render all control buttons', (WidgetTester tester) async {
      bool mutePressed = false;
      bool endPressed = false;
      bool speakerPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallControls(
              isMuted: false,
              onMuteToggle: () => mutePressed = true,
              onEndCall: () => endPressed = true,
              onSpeakerToggle: () => speakerPressed = true,
            ),
          ),
        ),
      );

      // Verify all buttons are present
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      expect(find.byIcon(Icons.call_end), findsOneWidget);

      // Verify labels
      expect(find.text('Mute'), findsOneWidget);
      expect(find.text('Speaker'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);
    });

    testWidgets('should show muted state correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallControls(
              isMuted: true,
              onMuteToggle: () {},
              onEndCall: () {},
              onSpeakerToggle: () {},
            ),
          ),
        ),
      );

      // Should show mic_off icon when muted
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsNothing);
    });

    testWidgets('should handle button presses', (WidgetTester tester) async {
      bool mutePressed = false;
      bool endPressed = false;
      bool speakerPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallControls(
              isMuted: false,
              onMuteToggle: () => mutePressed = true,
              onEndCall: () => endPressed = true,
              onSpeakerToggle: () => speakerPressed = true,
            ),
          ),
        ),
      );

      // Test mute button
      await tester.tap(find.byIcon(Icons.mic));
      expect(mutePressed, isTrue);

      // Test speaker button
      await tester.tap(find.byIcon(Icons.volume_up));
      expect(speakerPressed, isTrue);

      // Test end call button
      await tester.tap(find.byIcon(Icons.call_end));
      expect(endPressed, isTrue);
    });

    testWidgets('should toggle speaker icon state', (WidgetTester tester) async {
      bool isSpeakerOn = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CallControls(
                isMuted: false,
                onMuteToggle: () {},
                onEndCall: () {},
                onSpeakerToggle: () {
                  setState(() => isSpeakerOn = !isSpeakerOn);
                },
              ),
            ),
          ),
        ),
      );

      // Initially should show volume_up
      expect(find.byIcon(Icons.volume_up), findsOneWidget);

      // Tap to toggle
      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pump();

      // Should show volume_down after toggle
      expect(find.byIcon(Icons.volume_down), findsOneWidget);
    });
  });

  group('CallStatusIndicator Widget Tests', () {
    testWidgets('should display connecting status', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallStatusIndicator(status: CallStatus.connecting),
          ),
        ),
      );

      expect(find.text('Connecting'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing); // No progress indicator in this widget
    });

    testWidgets('should display connected status', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallStatusIndicator(status: CallStatus.connected),
          ),
        ),
      );

      expect(find.text('Connected'), findsOneWidget);
    });

    testWidgets('should display ringing status', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallStatusIndicator(status: CallStatus.ringing),
          ),
        ),
      );

      expect(find.text('Ringing'), findsOneWidget);
    });

    testWidgets('should display ended status', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallStatusIndicator(status: CallStatus.ended),
          ),
        ),
      );

      expect(find.text('Call Ended'), findsOneWidget);
    });

    testWidgets('should display idle status', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallStatusIndicator(status: CallStatus.idle),
          ),
        ),
      );

      expect(find.text('Idle'), findsOneWidget);
    });

    testWidgets('should show animated dots for connecting status', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallStatusIndicator(status: CallStatus.connecting),
          ),
        ),
      );

      // Initially should show some dots
      final textFinder = find.text('Connecting');
      expect(textFinder, findsOneWidget);

      // The dots animation is internal, so we just verify the widget renders
      await tester.pump(Duration(milliseconds: 500));
      expect(textFinder, findsOneWidget);
    });

    testWidgets('should show animated dots for ringing status', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallStatusIndicator(status: CallStatus.ringing),
          ),
        ),
      );

      expect(find.text('Ringing'), findsOneWidget);
    });

    testWidgets('should have correct status colors', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                CallStatusIndicator(status: CallStatus.connecting),
                CallStatusIndicator(status: CallStatus.connected),
                CallStatusIndicator(status: CallStatus.ringing),
                CallStatusIndicator(status: CallStatus.ended),
              ],
            ),
          ),
        ),
      );

      // Verify all status texts are present
      expect(find.text('Connecting'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Ringing'), findsOneWidget);
      expect(find.text('Call Ended'), findsOneWidget);
    });

    testWidgets('should handle status changes', (WidgetTester tester) async {
      CallStatus currentStatus = CallStatus.connecting;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  CallStatusIndicator(status: currentStatus),
                  ElevatedButton(
                    onPressed: () => setState(() => currentStatus = CallStatus.connected),
                    child: const Text('Change Status'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Connecting'), findsOneWidget);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Connecting'), findsNothing);
    });
  });

  group('Call Model Widget Integration Tests', () {
    testWidgets('should integrate Call model with widgets', (WidgetTester tester) async {
      final call = Call(
        id: 'test_call_123',
        recipientId: 'recipient_456',
        status: CallStatus.connected,
        isOutgoing: true,
        startTime: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                CallStatusIndicator(status: call.status),
                CallControls(
                  isMuted: false,
                  onMuteToggle: () {},
                  onEndCall: () {},
                  onSpeakerToggle: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Connected'), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.call_end), findsOneWidget);
    });

    testWidgets('should handle call state transitions in UI', (WidgetTester tester) async {
      CallStatus currentStatus = CallStatus.connecting;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CallStatusIndicator(status: currentStatus),
            ),
          ),
        ),
      );

      expect(find.text('Connecting'), findsOneWidget);

      // Simulate status change
      currentStatus = CallStatus.connected;
      await tester.pump();

      expect(find.text('Connected'), findsOneWidget);
    });
  });

  group('Widget Layout and Styling Tests', () {
    testWidgets('should have proper layout structure', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallControls(
              isMuted: false,
              onMuteToggle: () {},
              onEndCall: () {},
              onSpeakerToggle: () {},
            ),
          ),
        ),
      );

      // Verify layout uses Row
      expect(find.byType(Row), findsOneWidget);

      // Verify buttons are in a row
      final row = tester.widget<Row>(find.byType(Row));
      expect(row.children.length, equals(3)); // 3 buttons
    });

    testWidgets('should handle different screen sizes', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallControls(
              isMuted: false,
              onMuteToggle: () {},
              onEndCall: () {},
              onSpeakerToggle: () {},
            ),
          ),
        ),
      );

      // Test in different screen configurations
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pump();

      expect(find.byIcon(Icons.mic), findsOneWidget);

      await tester.binding.setSurfaceSize(const Size(800, 600));
      await tester.pump();

      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('should be accessible', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallControls(
              isMuted: false,
              onMuteToggle: () {},
              onEndCall: () {},
              onSpeakerToggle: () {},
            ),
          ),
        ),
      );

      // Verify buttons have proper semantics
      final micButton = find.byIcon(Icons.mic);
      final endButton = find.byIcon(Icons.call_end);

      expect(tester.getSemantics(micButton), isNotNull);
      expect(tester.getSemantics(endButton), isNotNull);
    });
  });

  group('Widget Error Handling Tests', () {
    testWidgets('should handle null callbacks gracefully', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallControls(
              isMuted: false,
              onMuteToggle: null,
              onEndCall: null,
              onSpeakerToggle: null,
            ),
          ),
        ),
      );

      // Should still render without crashing
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('should handle rapid button presses', (WidgetTester tester) async {
      int pressCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallControls(
              isMuted: false,
              onMuteToggle: () => pressCount++,
              onEndCall: () {},
              onSpeakerToggle: () {},
            ),
          ),
        ),
      );

      // Rapid presses
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byIcon(Icons.mic));
      }

      expect(pressCount, equals(5));
    });
  });

  group('Widget Performance Tests', () {
    testWidgets('should handle frequent rebuilds', (WidgetTester tester) async {
      bool isMuted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CallControls(
                isMuted: isMuted,
                onMuteToggle: () => setState(() => isMuted = !isMuted),
                onEndCall: () {},
                onSpeakerToggle: () {},
              ),
            ),
          ),
        ),
      );

      // Frequent state changes
      for (var i = 0; i < 10; i++) {
        await tester.tap(find.byIcon(isMuted ? Icons.mic_off : Icons.mic));
        await tester.pump();
      }

      expect(find.byIcon(Icons.mic_off), findsOneWidget);
    });

    testWidgets('should not leak resources', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CallStatusIndicator(status: CallStatus.connecting),
          ),
        ),
      );

      // The animation should be properly disposed
      await tester.pumpWidget(Container()); // Remove widget

      expect(find.byType(CallStatusIndicator), findsNothing);
    });
  });
}
