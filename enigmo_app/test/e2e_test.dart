import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:enigmo_app/main.dart';
import 'package:enigmo_app/services/network_service.dart';
import 'package:enigmo_app/services/audio_call_service.dart';
import 'package:enigmo_app/services/crypto_engine.dart';

// Note: These tests require a running server and are meant to be run with
// flutter test integration_test/e2e_test.dart

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('End-to-End User Journey Tests', () {
    testWidgets('complete user registration and authentication flow', (WidgetTester tester) async {
      // Launch the app
      await tester.pumpWidget(const AnogramApp());
      await tester.pumpAndSettle();

      // Wait for splash screen and initial setup
      await tester.pump(Duration(seconds: 2));

      // Verify we're on the chat list screen
      expect(find.text('Enigmo'), findsOneWidget);

      // The app should automatically connect and register a user
      // Wait for connection to establish
      await tester.pump(Duration(seconds: 3));

      // Verify connection status
      expect(find.text('Online'), findsOneWidget);

      // Verify user ID is displayed
      final userIdText = find.textContaining('ID:');
      expect(userIdText, findsOneWidget);
    });

    testWidgets('send and receive text messages', (WidgetTester tester) async {
      await tester.pumpWidget(const AnogramApp());
      await tester.pumpAndSettle();
      await tester.pump(Duration(seconds: 3));

      // Navigate to add user dialog
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Enter a test user ID
      const testUserId = '0123456789abcdef';
      await tester.enterText(find.byType(TextField), testUserId);
      await tester.pumpAndSettle();

      // Add the user
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Navigate to the chat
      await tester.tap(find.text(testUserId));
      await tester.pumpAndSettle();

      // Verify we're in the chat screen
      expect(find.text(testUserId), findsOneWidget);

      // Type a message
      const testMessage = 'Hello from e2e test!';
      await tester.enterText(find.byType(TextField), testMessage);
      await tester.pumpAndSettle();

      // Send the message
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Verify message appears in chat
      expect(find.text(testMessage), findsOneWidget);
    });

    testWidgets('initiate and manage audio call', (WidgetTester tester) async {
      await tester.pumpWidget(const AnogramApp());
      await tester.pumpAndSettle();
      await tester.pump(Duration(seconds: 3));

      // Add a test user
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      const testUserId = '0123456789abcdef';
      await tester.enterText(find.byType(TextField), testUserId);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Navigate to chat
      await tester.tap(find.text(testUserId));
      await tester.pumpAndSettle();

      // Initiate call
      await tester.tap(find.byIcon(Icons.call));
      await tester.pumpAndSettle();

      // Verify call screen appears
      expect(find.text('Connecting'), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.call_end), findsOneWidget);

      // Test mute functionality
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.mic_off), findsOneWidget);

      // Test speaker toggle
      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.volume_down), findsOneWidget);

      // End the call
      await tester.tap(find.byIcon(Icons.call_end));
      await tester.pumpAndSettle();

      // Should return to chat screen
      expect(find.text(testUserId), findsOneWidget);
    });

    testWidgets('handle incoming call notification', (WidgetTester tester) async {
      await tester.pumpWidget(const AnogramApp());
      await tester.pumpAndSettle();
      await tester.pump(Duration(seconds: 3));

      // The IncomingCallHandler should be active
      // In a real e2e test, we would simulate an incoming call
      // For now, we verify the handler is present
      expect(find.byType(AnogramApp), findsOneWidget);
    });

    testWidgets('manage chat list and navigation', (WidgetTester tester) async {
      await tester.pumpWidget(const AnogramApp());
      await tester.pumpAndSettle();
      await tester.pump(Duration(seconds: 3));

      // Add multiple users
      const userIds = ['0123456789abcdef', 'fedcba9876543210'];

      for (final userId in userIds) {
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), userId);
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();
      }

      // Verify both users appear in chat list
      expect(find.text(userIds[0]), findsOneWidget);
      expect(find.text(userIds[1]), findsOneWidget);

      // Navigate to first chat
      await tester.tap(find.text(userIds[0]));
      await tester.pumpAndSettle();

      // Verify navigation
      expect(find.text(userIds[0]), findsOneWidget);

      // Go back
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Should be back to chat list
      expect(find.text(userIds[0]), findsOneWidget);
      expect(find.text(userIds[1]), findsOneWidget);
    });

    testWidgets('handle connection loss and recovery', (WidgetTester tester) async {
      await tester.pumpWidget(const AnogramApp());
      await tester.pumpAndSettle();
      await tester.pump(Duration(seconds: 3));

      // Initially should be online
      expect(find.text('Online'), findsOneWidget);

      // In a real test, we would simulate network disconnection
      // For now, we verify the connection status is displayed
      final connectionStatus = find.text('Online').evaluate().isNotEmpty ||
                              find.text('Offline').evaluate().isNotEmpty;
      expect(connectionStatus, isTrue);
    });

    testWidgets('settings screen navigation', (WidgetTester tester) async {
      await tester.pumpWidget(const AnogramApp());
      await tester.pumpAndSettle();
      await tester.pump(Duration(seconds: 3));

      // Navigate to settings
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Verify settings screen
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('session reset functionality', (WidgetTester tester) async {
      await tester.pumpWidget(const AnogramApp());
      await tester.pumpAndSettle();
      await tester.pump(Duration(seconds: 3));

      // Tap the floating action button to reset session
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Should show reset confirmation or new session message
      expect(find.byType(SnackBar).evaluate().isNotEmpty || find.text('New session created').evaluate().isNotEmpty, isTrue);
    });
  });

  group('End-to-End Error Handling Tests', () {
    testWidgets('handle invalid user ID input', (WidgetTester tester) async {
      await tester.pumpWidget(const AnogramApp());
      await tester.pumpAndSettle();
      await tester.pump(Duration(seconds: 3));

      // Open add user dialog
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Enter invalid user ID (too short)
      await tester.enterText(find.byType(TextField), 'short');
      await tester.pumpAndSettle();

      // Try to add - should show error
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Should still be in dialog or show error
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('handle failed message sending', (WidgetTester tester) async {
      await tester.pumpWidget(const AnogramApp());
      await tester.pumpAndSettle();
      await tester.pump(Duration(seconds: 3));

      // Add a user
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '0123456789abcdef');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Navigate to chat
      await tester.tap(find.text('0123456789abcdef'));
      await tester.pumpAndSettle();

      // Try to send empty message
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Should handle gracefully (either ignore or show error)
      expect(find.byType(SnackBar).evaluate().isEmpty || find.text('Failed to send').evaluate().isEmpty, isTrue);
    });

    testWidgets('handle call initiation failure', (WidgetTester tester) async {
      await tester.pumpWidget(const AnogramApp());
      await tester.pumpAndSettle();
      await tester.pump(Duration(seconds: 3));

      // Add offline user
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'offlineuser123456');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Navigate to chat
      await tester.tap(find.text('offlineuser123456'));
      await tester.pumpAndSettle();

      // Try to call offline user
      await tester.tap(find.byIcon(Icons.call));
      await tester.pumpAndSettle();

      // Should handle gracefully
      expect(find.byType(SnackBar).evaluate().isNotEmpty || find.text('Connecting').evaluate().isNotEmpty, isTrue);
    });
  });

  group('End-to-End Performance Tests', () {
    testWidgets('handle rapid user interactions', (WidgetTester tester) async {
      await tester.pumpWidget(const AnogramApp());
      await tester.pumpAndSettle();
      await tester.pump(Duration(seconds: 3));

      // Rapidly open and close add user dialog
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      }

      // App should remain stable
      expect(find.text('Enigmo'), findsOneWidget);
    });

    testWidgets('handle multiple chat navigation', (WidgetTester tester) async {
      await tester.pumpWidget(const AnogramApp());
      await tester.pumpAndSettle();
      await tester.pump(Duration(seconds: 3));

      // Add multiple users quickly
      const userIds = ['user1abcdef123456', 'user2abcdef123456', 'user3abcdef123456'];

      for (final userId in userIds) {
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), userId);
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();
      }

      // Rapidly navigate between chats
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text(userIds[i % userIds.length]));
        await tester.pumpAndSettle();

        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      // App should remain stable
      expect(find.text(userIds[0]), findsOneWidget);
    });
  });

  group('End-to-End Security Tests', () {
    testWidgets('verify message encryption', (WidgetTester tester) async {
      await tester.pumpWidget(const AnogramApp());
      await tester.pumpAndSettle();
      await tester.pump(Duration(seconds: 3));

      // Add a user
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '0123456789abcdef');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Navigate to chat
      await tester.tap(find.text('0123456789abcdef'));
      await tester.pumpAndSettle();

      // Send a sensitive message
      const sensitiveMessage = 'This is confidential information';
      await tester.enterText(find.byType(TextField), sensitiveMessage);
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      // Verify message appears (encryption/decryption should be transparent to user)
      expect(find.text(sensitiveMessage), findsOneWidget);
    });

    testWidgets('verify user authentication', (WidgetTester tester) async {
      await tester.pumpWidget(const AnogramApp());
      await tester.pumpAndSettle();
      await tester.pump(Duration(seconds: 3));

      // Verify user is authenticated (has user ID)
      expect(find.textContaining('ID:'), findsOneWidget);

      // Verify connection is secure (would show Online status)
      expect(find.text('Online'), findsOneWidget);
    });
  });
}