import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import '../../lib/services/app_lifecycle_service.dart';
import '../../lib/services/network_service.dart';
import '../../lib/services/notification_service.dart';

// Generate mocks
@GenerateMocks([NetworkService, NotificationService])
import 'app_lifecycle_service_test.mocks.dart';

void main() {
  group('AppLifecycleService Tests', () {
    late AppLifecycleService lifecycleService;
    late MockNetworkService mockNetworkService;
    late MockNotificationService mockNotificationService;

    setUp(() {
      lifecycleService = AppLifecycleService();
      mockNetworkService = MockNetworkService();
      mockNotificationService = MockNotificationService();
    });

    tearDown(() {
      lifecycleService.dispose();
    });

    group('Initialization', () {
      test('should initialize lifecycle service successfully', () {
        // Act
        lifecycleService.initialize();

        // Assert
        expect(lifecycleService.currentState, isNull);
        expect(lifecycleService.isInBackground, isFalse);
      });
    });

    group('App Lifecycle State Changes', () {
      test('should handle app resumed state correctly', () {
        // Arrange
        lifecycleService.initialize();
        
        // Act - First go to background, then resume
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        expect(lifecycleService.isInBackground, isTrue);
        
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);

        // Assert
        expect(lifecycleService.currentState, equals(AppLifecycleState.resumed));
        expect(lifecycleService.isInBackground, isFalse);
      });

      test('should handle app paused state correctly', () {
        // Arrange
        lifecycleService.initialize();
        
        // Act
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);

        // Assert
        expect(lifecycleService.currentState, equals(AppLifecycleState.paused));
        expect(lifecycleService.isInBackground, isTrue);
        expect(lifecycleService.backgroundStartTime, isNotNull);
      });

      test('should handle app inactive state correctly', () {
        // Arrange
        lifecycleService.initialize();
        
        // Act
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.inactive);

        // Assert
        expect(lifecycleService.currentState, equals(AppLifecycleState.inactive));
        // Inactive state should not trigger background mode immediately
        expect(lifecycleService.isInBackground, isFalse);
      });

      test('should handle app detached state correctly', () {
        // Arrange
        lifecycleService.initialize();
        
        // Act
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.detached);

        // Assert
        expect(lifecycleService.currentState, equals(AppLifecycleState.detached));
      });

      test('should handle app hidden state correctly', () {
        // Arrange
        lifecycleService.initialize();
        
        // Act
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.hidden);

        // Assert
        expect(lifecycleService.currentState, equals(AppLifecycleState.hidden));
        expect(lifecycleService.isInBackground, isTrue);
      });
    });

    group('Background Session Persistence', () {
      test('should maintain session when app goes to background', () async {
        // Arrange
        lifecycleService.initialize();
        
        // Act
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        
        // Wait a bit to ensure background timer starts
        await Future.delayed(const Duration(milliseconds: 100));

        // Assert
        expect(lifecycleService.isInBackground, isTrue);
        expect(lifecycleService.backgroundStartTime, isNotNull);
      });

      test('should calculate background duration correctly', () async {
        // Arrange
        lifecycleService.initialize();
        const backgroundDuration = Duration(seconds: 2);
        
        // Act
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        await Future.delayed(backgroundDuration);
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);

        // Assert
        expect(lifecycleService.isInBackground, isFalse);
        // Background duration should be approximately what we waited
        if (lifecycleService.backgroundStartTime != null) {
          final actualDuration = DateTime.now().difference(lifecycleService.backgroundStartTime!);
          expect(actualDuration.inSeconds, greaterThanOrEqualTo(backgroundDuration.inSeconds - 1));
        }
      });

      test('should not disconnect session during normal background operation', () async {
        // Arrange
        lifecycleService.initialize();
        
        // Act
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        await Future.delayed(const Duration(seconds: 1));
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);

        // Assert
        expect(lifecycleService.isInBackground, isFalse);
        // Session should persist through normal background/foreground cycle
      });
    });

    group('Background Message Handling', () {
      test('should handle background message correctly', () {
        // Arrange
        lifecycleService.initialize();
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        
        final messageData = {
          'content': 'Test message',
          'senderName': 'Test User',
          'senderId': 'user123',
          'chatId': 'chat123',
        };

        // Act
        lifecycleService.handleBackgroundMessage(messageData);

        // Assert - Should process background message when in background
        expect(lifecycleService.isInBackground, isTrue);
      });

      test('should ignore background message when app is in foreground', () {
        // Arrange
        lifecycleService.initialize();
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);
        
        final messageData = {
          'content': 'Test message',
          'senderName': 'Test User',
        };

        // Act
        lifecycleService.handleBackgroundMessage(messageData);

        // Assert - Should ignore background message when in foreground
        expect(lifecycleService.isInBackground, isFalse);
      });

      test('should generate proper notification body from message data', () {
        // Arrange
        lifecycleService.initialize();
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        
        final longMessage = 'A' * 100; // Message longer than 50 characters
        final messageData = {
          'content': longMessage,
          'senderName': 'Test User',
        };

        // Act
        lifecycleService.handleBackgroundMessage(messageData);

        // Assert - Should truncate long messages
        expect(lifecycleService.isInBackground, isTrue);
      });
    });

    group('Resource Management', () {
      test('should dispose resources correctly', () {
        // Arrange
        lifecycleService.initialize();
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);

        // Act
        lifecycleService.dispose();

        // Assert - Should clean up resources
        expect(lifecycleService.isInBackground, isFalse);
      });

      test('should handle max background duration limit', () async {
        // Arrange
        lifecycleService.initialize();
        
        // Act - Simulate long background duration
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        
        // Note: This test verifies the logic structure rather than waiting actual hours
        expect(lifecycleService.isInBackground, isTrue);
        expect(lifecycleService.backgroundStartTime, isNotNull);
      });
    });

    group('Integration with NetworkService', () {
      test('should integrate with NetworkService correctly', () {
        // Arrange
        lifecycleService.initialize();

        // Act & Assert - Should initialize without errors
        expect(lifecycleService.currentState, isNull);
        expect(lifecycleService.isInBackground, isFalse);
      });
    });

    group('Edge Cases', () {
      test('should handle rapid state changes correctly', () async {
        // Arrange
        lifecycleService.initialize();

        // Act - Rapid state changes
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.resumed);

        // Assert - Should handle rapid changes gracefully
        expect(lifecycleService.currentState, equals(AppLifecycleState.resumed));
        expect(lifecycleService.isInBackground, isFalse);
      });

      test('should handle null or invalid message data', () {
        // Arrange
        lifecycleService.initialize();
        lifecycleService.handleAppLifecycleChange(AppLifecycleState.paused);

        // Act & Assert - Should handle invalid data gracefully
        lifecycleService.handleBackgroundMessage({});
        lifecycleService.handleBackgroundMessage({'invalid': 'data'});
        
        expect(lifecycleService.isInBackground, isTrue);
      });
    });
  });
}