import 'package:flutter/material.dart';
import 'dart:async';
import 'network_service.dart';
import 'notification_service.dart';

/// Service to handle app lifecycle changes and maintain persistent connections
class AppLifecycleService {
  static final AppLifecycleService _instance = AppLifecycleService._internal();
  factory AppLifecycleService() => _instance;
  AppLifecycleService._internal();

  final NetworkService _networkService = NetworkService();
  final NotificationService _notificationService = NotificationService();
  
  AppLifecycleState? _currentState;
  Timer? _backgroundTimer;
  bool _isInBackground = false;
  DateTime? _backgroundStartTime;
  
  // Configuration
  static const Duration _backgroundKeepaliveInterval = Duration(minutes: 1);
  static const Duration _maxBackgroundDuration = Duration(hours: 2);
  
  /// Initialize the lifecycle service
  void initialize() {
    print('INFO AppLifecycleService: Initializing app lifecycle management');
    _notificationService.initialize();
    
    // Register with NetworkService for background message handling
    _networkService.setLifecycleService(this);
  }

  /// Handle app lifecycle state changes
  void handleAppLifecycleChange(AppLifecycleState state) {
    print('INFO AppLifecycleService: App lifecycle changed to $state');
    _currentState = state;

    switch (state) {
      case AppLifecycleState.resumed:
        _handleAppResumed();
        break;
      case AppLifecycleState.paused:
        _handleAppPaused();
        break;
      case AppLifecycleState.inactive:
        _handleAppInactive();
        break;
      case AppLifecycleState.detached:
        _handleAppDetached();
        break;
      case AppLifecycleState.hidden:
        _handleAppHidden();
        break;
    }
  }

  /// App was resumed (brought to foreground)
  void _handleAppResumed() {
    print('INFO AppLifecycleService: App resumed from background');
    _isInBackground = false;
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    
    // Calculate background duration
    if (_backgroundStartTime != null) {
      final backgroundDuration = DateTime.now().difference(_backgroundStartTime!);
      print('INFO AppLifecycleService: App was in background for ${backgroundDuration.inMinutes} minutes');
      
      // If app was in background for too long, might need to refresh connection
      if (backgroundDuration > _maxBackgroundDuration) {
        print('INFO AppLifecycleService: Long background duration, checking connection health');
        _checkConnectionHealth();
      }
    }
    
    // Cancel any background notifications
    _notificationService.cancelBackgroundNotifications();
    
    // Mark user as active again
    _notifyUserActive();
  }

  /// App was paused (sent to background)
  void _handleAppPaused() {
    print('INFO AppLifecycleService: App paused (going to background)');
    _isInBackground = true;
    _backgroundStartTime = DateTime.now();
    
    // Start background keepalive
    _startBackgroundKeepalive();
    
    // Notify user is now in background
    _notifyUserInBackground();
  }

  /// App became inactive (transitional state)
  void _handleAppInactive() {
    print('INFO AppLifecycleService: App became inactive');
    // Don't disconnect yet, might just be a temporary state
  }

  /// App was detached (being destroyed)
  void _handleAppDetached() {
    print('INFO AppLifecycleService: App detached, performing cleanup');
    _performCleanup();
    // Per privacy requirements, reset the session completely on app exit.
    _networkService.resetSession();
  }

  /// App was hidden (web-specific)
  void _handleAppHidden() {
    print('INFO AppLifecycleService: App hidden');
    // Similar to paused for web apps
    _handleAppPaused();
  }

  /// Start background keepalive to maintain connection
  void _startBackgroundKeepalive() {
    print('INFO AppLifecycleService: Starting background keepalive');
    
    _backgroundTimer = Timer.periodic(_backgroundKeepaliveInterval, (timer) {
      if (!_isInBackground) {
        timer.cancel();
        return;
      }
      
      final backgroundDuration = DateTime.now().difference(_backgroundStartTime!);
      
      // Stop keepalive after max duration to save resources
      if (backgroundDuration > _maxBackgroundDuration) {
        print('INFO AppLifecycleService: Max background duration reached, stopping keepalive');
        timer.cancel();
        return;
      }
      
      // Send keepalive ping if connection is active
      if (_networkService.isConnected) {
        _sendKeepalivePing();
      }
    });
  }

  /// Send keepalive ping to server
  void _sendKeepalivePing() {
    try {
      // Send a lightweight ping to keep connection alive
      print('DEBUG AppLifecycleService: Sending background keepalive ping');
      _networkService.sendKeepalivePing();
    } catch (e) {
      print('ERROR AppLifecycleService: Failed to send keepalive ping: $e');
    }
  }

  /// Check connection health after resuming
  void _checkConnectionHealth() {
    if (!_networkService.isConnected) {
      print('INFO AppLifecycleService: Connection lost during background, reconnecting');
      _networkService.reconnect();
    } else {
      print('INFO AppLifecycleService: Connection healthy after background');
    }
  }

  /// Notify server that user is active
  void _notifyUserActive() {
    if (_networkService.isConnected) {
      _networkService.setUserStatus(isActive: true);
    }
  }

  /// Notify server that user is in background
  void _notifyUserInBackground() {
    if (_networkService.isConnected) {
      _networkService.setUserStatus(isActive: false);
    }
  }

  /// Handle new message received while in background
  void handleBackgroundMessage(Map<String, dynamic> messageData) {
    if (!_isInBackground) return;
    
    print('INFO AppLifecycleService: Received message while in background');
    
    // Show notification
    _notificationService.showMessageNotification(
      title: 'New Message',
      body: _getNotificationBody(messageData),
      data: messageData,
    );
  }

  /// Get notification body from message data
  String _getNotificationBody(Map<String, dynamic> messageData) {
    try {
      final content = messageData['content'] as String?;
      final senderName = messageData['senderName'] as String? ?? 'Someone';
      
      if (content != null && content.isNotEmpty) {
        return '$senderName: ${content.length > 50 ? '${content.substring(0, 50)}...' : content}';
      } else {
        return '$senderName sent a message';
      }
    } catch (e) {
      return 'New message received';
    }
  }

  /// Perform cleanup when app is being destroyed
  void _performCleanup() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
    
    // Don't disconnect WebSocket immediately - user might be switching apps temporarily
    // Instead, set a longer timeout for cleanup
    Timer(const Duration(minutes: 5), () {
      if (_currentState == AppLifecycleState.detached) {
        print('INFO AppLifecycleService: Performing delayed cleanup after app detach');
        _networkService.disconnect();
      }
    });
  }

  /// Get current app state
  AppLifecycleState? get currentState => _currentState;
  
  /// Check if app is currently in background
  bool get isInBackground => _isInBackground;
  
  /// Get time when app went to background
  DateTime? get backgroundStartTime => _backgroundStartTime;

  /// Dispose resources
  void dispose() {
    print('INFO AppLifecycleService: Disposing lifecycle service');
    _backgroundTimer?.cancel();
    _notificationService.dispose();
  }
}