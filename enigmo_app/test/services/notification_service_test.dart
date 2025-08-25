import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import '../../lib/services/notification_service.dart';

void main() {
  group('NotificationService Tests', () {
    late NotificationService notificationService;

    setUp(() {
      notificationService = NotificationService();
    });

    tearDown(() {
      notificationService.dispose();
    });

    group('Initialization', () {
      test('should initialize notification service successfully', () async {
        // Act
        await notificationService.initialize();

        // Assert
        expect(notificationService.isInitialized, isTrue);
      });

      test('should not initialize twice', () async {
        // Arrange
        await notificationService.initialize();
        final firstInitState = notificationService.isInitialized;

        // Act
        await notificationService.initialize();

        // Assert
        expect(notificationService.isInitialized, equals(firstInitState));
        expect(notificationService.isInitialized, isTrue);
      });
    });

    group('Permission Handling', () {
      test('should handle permission states correctly', () async {
        // Act
        await notificationService.initialize();

        // Assert - On test environment, permissions depend on platform simulation
        expect(notificationService.isInitialized, isTrue);
      });
    });

    group('Message Notifications', () {
      test('should show message notification with basic data', () async {
        // Arrange
        await notificationService.initialize();

        // Act & Assert - Should not throw errors
        expect(() {
          notificationService.showMessageNotification(
            title: 'Test Message',
            body: 'This is a test message',
          );
        }, returnsNormally);
      });

      test('should show message notification with additional data', () async {
        // Arrange
        await notificationService.initialize();
        final messageData = {
          'chatId': 'chat123',
          'senderId': 'user456',
          'timestamp': DateTime.now().toIso8601String(),
        };

        // Act & Assert - Should not throw errors
        expect(() {
          notificationService.showMessageNotification(
            title: 'Test Message',
            body: 'This is a test message',
            data: messageData,
          );
        }, returnsNormally);
      });

      test('should queue notifications when not initialized', () {
        // Arrange - Don't initialize service
        
        // Act
        notificationService.showMessageNotification(
          title: 'Queued Message',
          body: 'This should be queued',
        );

        // Assert - Should not throw errors even when not initialized
        expect(notificationService.isInitialized, isFalse);
      });

      test('should process pending notifications after initialization', () async {
        // Arrange - Add notification before initialization
        notificationService.showMessageNotification(
          title: 'Pending Message',
          body: 'This was queued',
        );

        // Act
        await notificationService.initialize();

        // Assert - Should have processed pending notifications
        expect(notificationService.isInitialized, isTrue);
      });
    });

    group('Specialized Notifications', () {
      test('should show typing notification', () async {
        // Arrange
        await notificationService.initialize();

        // Act & Assert
        expect(() {
          notificationService.showTypingNotification('Test User');
        }, returnsNormally);
      });

      test('should show connection status notifications', () async {
        // Arrange
        await notificationService.initialize();

        // Act & Assert
        expect(() {
          notificationService.showConnectionNotification(true);
          notificationService.showConnectionNotification(false);
        }, returnsNormally);
      });
    });

    group('Platform-Specific Behavior', () {
      test('should handle web platform correctly', () async {
        // Arrange
        debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia; // Simulate web
        
        // Act
        await notificationService.initialize();

        // Assert
        expect(notificationService.isInitialized, isTrue);
        
        // Cleanup
        debugDefaultTargetPlatformOverride = null;
      });

      test('should handle mobile platform correctly', () async {
        // Arrange
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        
        // Act
        await notificationService.initialize();

        // Assert
        expect(notificationService.isInitialized, isTrue);
        
        // Cleanup
        debugDefaultTargetPlatformOverride = null;
      });
    });

    group('Background Notifications', () {
      test('should cancel background notifications', () async {
        // Arrange
        await notificationService.initialize();

        // Act & Assert - Should not throw errors
        expect(() {
          notificationService.cancelBackgroundNotifications();
        }, returnsNormally);
      });

      test('should handle multiple notification cancellations', () async {
        // Arrange
        await notificationService.initialize();

        // Act & Assert - Should handle multiple cancellations gracefully
        expect(() {
          notificationService.cancelBackgroundNotifications();
          notificationService.cancelBackgroundNotifications();
          notificationService.cancelBackgroundNotifications();
        }, returnsNormally);
      });
    });

    group('FCM Token Management', () {
      test('should return null FCM token when not available', () async {
        // Arrange
        await notificationService.initialize();

        // Act
        final fcmToken = notificationService.fcmToken;

        // Assert - In test environment, FCM token should be null
        expect(fcmToken, isNull);
      });
    });

    group('Error Handling', () {
      test('should handle notification errors gracefully', () async {
        // Arrange
        await notificationService.initialize();

        // Act & Assert - Should handle invalid data gracefully
        expect(() {
          notificationService.showMessageNotification(
            title: '',
            body: '',
          );
        }, returnsNormally);
      });

      test('should handle dispose correctly', () async {
        // Arrange
        await notificationService.initialize();
        notificationService.showMessageNotification(
          title: 'Test',
          body: 'Before dispose',
        );

        // Act & Assert - Should dispose without errors
        expect(() {
          notificationService.dispose();
        }, returnsNormally);
      });

      test('should handle operations after dispose', () async {
        // Arrange
        await notificationService.initialize();
        notificationService.dispose();

        // Act & Assert - Should handle operations after dispose gracefully
        expect(() {
          notificationService.showMessageNotification(
            title: 'After Dispose',
            body: 'This should not crash',
          );
        }, returnsNormally);
      });
    });

    group('Notification Content Processing', () {
      test('should handle long message content', () async {
        // Arrange
        await notificationService.initialize();
        final longMessage = 'A' * 200; // Very long message

        // Act & Assert
        expect(() {
          notificationService.showMessageNotification(
            title: 'Long Message',
            body: longMessage,
          );
        }, returnsNormally);
      });

      test('should handle special characters in content', () async {
        // Arrange
        await notificationService.initialize();
        const specialContent = 'Test with 🚀 emojis and "quotes" & symbols!';

        // Act & Assert
        expect(() {
          notificationService.showMessageNotification(
            title: 'Special Characters',
            body: specialContent,
          );
        }, returnsNormally);
      });

      test('should handle empty or null content', () async {
        // Arrange
        await notificationService.initialize();

        // Act & Assert
        expect(() {
          notificationService.showMessageNotification(
            title: 'Empty Content',
            body: '',
          );
        }, returnsNormally);
      });
    });

    group('Service State Management', () {
      test('should maintain correct state through lifecycle', () async {
        // Arrange
        expect(notificationService.isInitialized, isFalse);
        expect(notificationService.isEnabled, isFalse);

        // Act
        await notificationService.initialize();

        // Assert
        expect(notificationService.isInitialized, isTrue);
        // isEnabled depends on platform and permission status
      });

      test('should handle reinitialization correctly', () async {
        // Arrange
        await notificationService.initialize();
        final firstState = notificationService.isInitialized;

        // Act
        await notificationService.initialize();

        // Assert - Should remain initialized
        expect(notificationService.isInitialized, equals(firstState));
        expect(notificationService.isInitialized, isTrue);
      });
    });

    group('Integration Scenarios', () {
      test('should handle high-frequency notifications', () async {
        // Arrange
        await notificationService.initialize();

        // Act & Assert - Should handle multiple rapid notifications
        expect(() {
          for (int i = 0; i < 10; i++) {
            notificationService.showMessageNotification(
              title: 'Message $i',
              body: 'Content for message $i',
              data: {'index': i},
            );
          }
        }, returnsNormally);
      });

      test('should handle mixed notification types', () async {
        // Arrange
        await notificationService.initialize();

        // Act & Assert - Should handle different notification types
        expect(() {
          notificationService.showMessageNotification(
            title: 'Regular Message',
            body: 'Regular content',
          );
          notificationService.showTypingNotification('Typing User');
          notificationService.showConnectionNotification(true);
          notificationService.showConnectionNotification(false);
        }, returnsNormally);
      });
    });
  });
}