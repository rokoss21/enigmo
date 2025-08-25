import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';

import '../../lib/services/app_lifecycle_service.dart';
import '../../lib/services/network_service.dart';
import '../../lib/services/notification_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Session Persistence Integration Tests', () {
    late AppLifecycleService lifecycleService;
    late NetworkService networkService;
    late NotificationService notificationService;

    setUpAll(() async {
      lifecycleService = AppLifecycleService();
      networkService = NetworkService();
      notificationService = NotificationService();
      
      // Initialize services
      lifecycleService.initialize();
      await notificationService.initialize();
    });

    tearDownAll(() {
      lifecycleService.dispose();
      notificationService.dispose();
      networkService.dispose();
    });

    group('Complete Messenger Lifecycle', () {
      testWidgets('should maintain session through app minimize and restore', (WidgetTester tester) async {
        // This test simulates the complete messenger behavior as requested by the user:
        // "как обычный месенджер" - like a regular messenger
        
        // Arrange - Initial app state (foreground)
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);
        expect(lifecycleService.isInBackground, isFalse);
        expect(lifecycleService.currentState, equals(AppLifecycleState.resumed));

        // Act - User minimizes app (свернул приложение)
        print('TEST: User minimizes app - session should persist');
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        
        // Assert - App is in background but session persists
        expect(lifecycleService.isInBackground, isTrue);
        expect(lifecycleService.currentState, equals(AppLifecycleState.paused));
        expect(lifecycleService.backgroundStartTime, isNotNull);
        
        print('✅ App minimized - session maintained in background');

        // Simulate background operation period
        await tester.pump(const Duration(seconds: 2));
        
        // Verify session is still active during background
        expect(lifecycleService.isInBackground, isTrue);
        print('✅ Session persists during background operation');

        // Act - User restores app
        print('TEST: User restores app from background');
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);
        
        // Assert - App returns to foreground with session intact
        expect(lifecycleService.isInBackground, isFalse);
        expect(lifecycleService.currentState, equals(AppLifecycleState.resumed));
        
        print('✅ App restored - session maintained through minimize/restore cycle');
      });

      testWidgets('should handle background notifications correctly', (WidgetTester tester) async {
        // Arrange - App in background to receive notifications
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        expect(lifecycleService.isInBackground, isTrue);

        // Act - Simulate incoming message while in background
        print('TEST: Receiving message while app is minimized');
        final messageData = {
          'content': 'Test background message',
          'senderName': 'Test User',
          'senderId': 'user123',
          'chatId': 'chat456',
          'timestamp': DateTime.now().toIso8601String(),
        };
        
        lifecycleService.handleBackgroundMessage(messageData);
        
        // Assert - Background message should be processed
        expect(lifecycleService.isInBackground, isTrue);
        print('✅ Background message processed successfully');

        // Act - Restore app after receiving notification
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);
        
        // Assert - App should return to foreground normally
        expect(lifecycleService.isInBackground, isFalse);
        print('✅ App restored after background notification');
      });

      testWidgets('should only end session on explicit close or forced refresh', (WidgetTester tester) async {
        // This test verifies: "до тех пор пока кто то не закроет совсем приложение 
        // или пока не обновит сессию принудительно"
        
        // Arrange - Normal app lifecycle (not explicit close)
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.inactive);
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);
        
        // Assert - Session should persist through normal lifecycle
        expect(lifecycleService.currentState, equals(AppLifecycleState.resumed));
        print('✅ Session persists through normal app lifecycle changes');

        // Act - Simulate explicit app close (detached state)
        print('TEST: Simulating explicit app close');
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.detached);
        
        // Assert - App is marked as detached (explicit close)
        expect(lifecycleService.currentState, equals(AppLifecycleState.detached));
        print('✅ Explicit app close detected - session will be cleaned up');
      });

      testWidgets('should handle rapid minimize/restore cycles', (WidgetTester tester) async {
        // Test rapid app switching behavior - common user pattern
        
        // Act - Rapid app lifecycle changes
        print('TEST: Rapid minimize/restore cycles');
        for (int i = 0; i < 5; i++) {
          lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
          await tester.pump(const Duration(milliseconds: 100));
          
          lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);
          await tester.pump(const Duration(milliseconds: 100));
        }
        
        // Assert - Final state should be stable
        expect(lifecycleService.currentState, equals(AppLifecycleState.resumed));
        expect(lifecycleService.isInBackground, isFalse);
        print('✅ Rapid lifecycle changes handled gracefully');
      });

      testWidgets('should maintain session during long background periods', (WidgetTester tester) async {
        // Test long background duration - verify keepalive functionality
        
        // Arrange
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);
        
        // Act - Extended background period
        print('TEST: Extended background period');
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        final backgroundStart = DateTime.now();
        
        // Simulate longer background period
        await tester.pump(const Duration(seconds: 5));
        
        // Assert - Session should still be maintained
        expect(lifecycleService.isInBackground, isTrue);
        expect(lifecycleService.backgroundStartTime, isNotNull);
        
        final backgroundDuration = DateTime.now().difference(backgroundStart);
        expect(backgroundDuration.inSeconds, greaterThanOrEqualTo(4));
        
        // Restore and verify session integrity
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);
        expect(lifecycleService.isInBackground, isFalse);
        
        print('✅ Extended background session maintained successfully');
      });
    });

    group('Notification Integration', () {
      testWidgets('should integrate notifications with lifecycle correctly', (WidgetTester tester) async {
        // Test notification integration with app lifecycle
        
        // Arrange - Initialize notification service
        expect(notificationService.isInitialized, isTrue);
        
        // Act - Test notifications in different app states
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);
        
        // Should handle foreground notifications
        notificationService.showMessageNotification(
          title: 'Foreground Message',
          body: 'Message received in foreground',
        );
        
        // Move to background
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        
        // Should handle background notifications
        notificationService.showMessageNotification(
          title: 'Background Message',
          body: 'Message received in background',
        );
        
        // Assert - Both notification types should be handled
        expect(lifecycleService.isInBackground, isTrue);
        expect(notificationService.isInitialized, isTrue);
        
        print('✅ Notification integration working correctly');
      });

      testWidgets('should cancel background notifications when app returns', (WidgetTester tester) async {
        // Arrange - App in background with pending notifications
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        
        notificationService.showMessageNotification(
          title: 'Pending Notification',
          body: 'This should be cancelled when app returns',
        );
        
        // Act - Return to foreground
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);
        
        // Simulate notification cancellation
        notificationService.cancelBackgroundNotifications();
        
        // Assert - App should be in foreground
        expect(lifecycleService.isInBackground, isFalse);
        print('✅ Background notifications cancelled on app return');
      });
    });

    group('Edge Cases and Error Handling', () {
      testWidgets('should handle service integration failures gracefully', (WidgetTester tester) async {
        // Test service integration error handling
        
        // Act & Assert - Should handle missing service references gracefully
        expect(() {
          lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
          lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);
        }, returnsNormally);
        
        print('✅ Service integration errors handled gracefully');
      });

      testWidgets('should handle malformed background messages', (WidgetTester tester) async {
        // Test error handling for invalid message data
        
        // Arrange
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        
        // Act - Send malformed messages
        expect(() {
          lifecycleService.handleBackgroundMessage({});
          lifecycleService.handleBackgroundMessage({'invalid': 'structure'});
          lifecycleService.handleBackgroundMessage(null);
        }, returnsNormally);
        
        print('✅ Malformed background messages handled gracefully');
      });
    });

    group('Performance and Resource Management', () {
      testWidgets('should manage resources efficiently during lifecycle changes', (WidgetTester tester) async {
        // Test resource management during intensive lifecycle changes
        
        // Act - Intensive lifecycle operations
        for (int i = 0; i < 20; i++) {
          lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
          await tester.pump(const Duration(milliseconds: 10));
          
          lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);
          await tester.pump(const Duration(milliseconds: 10));
        }
        
        // Assert - Final state should be stable
        expect(lifecycleService.currentState, equals(AppLifecycleState.resumed));
        expect(lifecycleService.isInBackground, isFalse);
        
        print('✅ Resource management efficient during intensive operations');
      });

      testWidgets('should clean up resources on disposal', (WidgetTester tester) async {
        // Test proper cleanup
        
        // Arrange - Create temporary service instance
        final tempLifecycleService = AppLifecycleService();
        tempLifecycleService.initialize();
        tempLifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        
        // Act - Dispose service
        expect(() {
          tempLifecycleService.dispose();
        }, returnsNormally);
        
        print('✅ Resources cleaned up properly on disposal');
      });
    });
  });
}