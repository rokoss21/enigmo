import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Service for handling notifications in web environment (with mobile placeholders)
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  bool _isInitialized = false;
  bool _permissionGranted = false;
  bool _userEnabled = true; // user-controlled toggle
  final List<_PendingNotification> _pendingNotifications = [];
  
  // Mobile notification support (non-web platforms)
  dynamic _firebaseMessaging; // FirebaseMessaging
  dynamic _localNotifications; // FlutterLocalNotificationsPlugin
  String? _fcmToken;

  /// Initialize notification service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    print('INFO NotificationService(Web): Initializing notification service');
    
    if (kIsWeb) {
      await _initializeWebNotifications();
    } else {
      await _initializeMobileNotifications();
    }
    
    _isInitialized = true;
  }

  /// Initialize web notifications
  Future<void> _initializeWebNotifications() async {
    try {
      // Check if notifications are supported
      if (!_isNotificationSupported()) {
        print('WARNING NotificationService(Web): Notifications not supported in this browser');
        return;
      }

      // Load user preference (persisted)
      try {
        final saved = html.window.localStorage['notifications_enabled'];
        if (saved != null) {
          _userEnabled = saved == 'true';
        }
        print('INFO NotificationService(Web): User notifications enabled: '+ _userEnabled.toString());
      } catch (_) {}

      // Do not prompt user at startup; just read current permission state
      try {
        final current = html.Notification.permission; // 'default' | 'granted' | 'denied'
        _permissionGranted = current == 'granted';
        print('INFO NotificationService(Web): Web notification current permission: $current');
      } catch (e) {
        print('WARNING NotificationService(Web): Unable to read current permission: $e');
        _permissionGranted = false;
      }

      if (_permissionGranted) {
        _processPendingNotifications();
      }
    } catch (e) {
      print('ERROR NotificationService(Web): Failed to initialize web notifications: $e');
    }
  }

  /// Optionally request permission later (e.g., in response to a user action)
  Future<bool> requestPermissionIfNeeded() async {
    if (!_isNotificationSupported()) return false;
    if (_permissionGranted) return true;
    try {
      final granted = await _requestNotificationPermission();
      _permissionGranted = granted;
      if (granted) {
        _processPendingNotifications();
      }
      return granted;
    } catch (e) {
      print('ERROR NotificationService(Web): Permission request failed: $e');
      return false;
    }
  }

  /// Initialize mobile notifications (Firebase + Local Notifications)
  Future<void> _initializeMobileNotifications() async {
    try {
      if (!kIsWeb) {
        print('INFO NotificationService(Web): Initializing mobile notifications');
        
        // Initialize Firebase Messaging (placeholder)
        try {
          final firebaseMessaging = await _getFirebaseMessaging();
          if (firebaseMessaging != null) {
            _firebaseMessaging = firebaseMessaging;
            print('INFO NotificationService(Web): Firebase messaging placeholder initialized');
          }
        } catch (e) {
          print('WARNING NotificationService(Web): Firebase not available, using local notifications only: $e');
        }
        
        // Initialize local notifications (placeholder)
        try {
          final localNotifications = await _getLocalNotificationsPlugin();
          if (localNotifications != null) {
            _localNotifications = localNotifications;
            print('INFO NotificationService(Web): Local notifications placeholder initialized');
          }
        } catch (e) {
          print('WARNING NotificationService(Web): Local notifications not available: $e');
        }
        
        // For now, assume permissions are granted for testing
        _permissionGranted = true;
        print('INFO NotificationService(Web): Mobile notification permissions assumed granted (placeholder)');
      }
    } catch (e) {
      print('ERROR NotificationService(Web): Failed to initialize mobile notifications: $e');
    }
  }

  /// Dynamically get FirebaseMessaging to avoid web compilation issues
  Future<dynamic> _getFirebaseMessaging() async {
    if (kIsWeb) return null;
    
    try {
      print('INFO NotificationService(Web): Attempting to load Firebase Messaging');
      return null; // disabled for now
    } catch (e) {
      print('INFO NotificationService(Web): Firebase messaging not available on this platform: $e');
      return null;
    }
  }

  /// Get local notifications plugin dynamically
  Future<dynamic> _getLocalNotificationsPlugin() async {
    if (kIsWeb) return null;
    
    try {
      print('INFO NotificationService(Web): Attempting to load Local Notifications');
      return null; // disabled for now
    } catch (e) {
      print('INFO NotificationService(Web): Local notifications not available on this platform: $e');
      return null;
    }
  }

  /// Setup Firebase message handlers
  Future<void> _setupFirebaseHandlers() async {
    if (_firebaseMessaging == null) return;
    
    try {
      print('INFO NotificationService(Web): Setting up Firebase handlers (placeholder)');
    } catch (e) {
      print('ERROR NotificationService(Web): Error setting up Firebase handlers: $e');
    }
  }

  /// Handle Firebase messages
  void _handleFirebaseMessage(dynamic message, {required bool isBackground}) {
    try {
      print('INFO NotificationService(Web): Handling Firebase message (placeholder)');
    } catch (e) {
      print('ERROR NotificationService(Web): Error handling Firebase message: $e');
    }
  }

  /// Handle notification tap
  void _onNotificationTap(dynamic response) {
    try {
      print('INFO NotificationService(Web): Local notification tapped');
    } catch (e) {
      print('ERROR NotificationService(Web): Error handling notification tap: $e');
    }
  }

  /// Check if notifications are supported
  bool _isNotificationSupported() {
    return html.Notification.supported;
  }

  /// Request notification permission
  Future<bool> _requestNotificationPermission() async {
    try {
      final permission = await html.Notification.requestPermission();
      return permission == 'granted';
    } catch (e) {
      print('ERROR NotificationService(Web): Failed to request permission: $e');
      return false;
    }
  }

  /// Show message notification
  void showMessageNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) {
    final notification = _PendingNotification(
      title: title,
      body: body,
      data: data,
    );

    if (!_isInitialized || !_permissionGranted || !_userEnabled) {
      _pendingNotifications.add(notification);
      return;
    }

    if (kIsWeb) {
      _showWebNotification(notification);
    } else {
      _showLocalNotification(
        title: title,
        body: body,
        data: data ?? {},
      );
    }
  }

  /// Show web notification
  void _showWebNotification(_PendingNotification notification) {
    try {
      final title = notification.body.isNotEmpty
          ? '${notification.title}: ${notification.body}'
          : notification.title;
      final webNotification = html.Notification(title);
      
      // Auto-close after 10 seconds if not interacted
      Timer(const Duration(seconds: 10), () {
        try {
          webNotification.close();
        } catch (e) {}
      });

      // Handle notification click
      webNotification.onClick.listen((event) {
        print('INFO NotificationService(Web): Notification clicked');
        webNotification.close();
        
        if (notification.data != null) {
          _handleNotificationClick(notification.data!);
        }
      });

      print('INFO NotificationService(Web): Notification shown: ${notification.title}');
    } catch (e) {
      print('ERROR NotificationService(Web): Failed to show notification: $e');
    }
  }

  /// Show local notification (mobile platforms)
  void _showLocalNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) {
    if (_localNotifications == null || kIsWeb) return;
    
    try {
      print('INFO NotificationService(Web): Would show local notification: $title - $body');
    } catch (e) {
      print('ERROR NotificationService(Web): Failed to show local notification: $e');
    }
  }

  /// Handle notification click
  void _handleNotificationClick(Map<String, dynamic> data) {
    try {
      final chatId = data['chatId'] as String?;
      final senderId = data['senderId'] as String?;
      
      print('INFO NotificationService(Web): Handling notification click for chat: $chatId, sender: $senderId');
    } catch (e) {
      print('ERROR NotificationService(Web): Failed to handle notification click: $e');
    }
  }

  /// Process pending notifications
  void _processPendingNotifications() {
    if (_pendingNotifications.isEmpty) return;
    
    print('INFO NotificationService(Web): Processing ${_pendingNotifications.length} pending notifications');
    
    for (final notification in _pendingNotifications) {
      if (kIsWeb) {
        _showWebNotification(notification);
      } else {
        _showLocalNotification(
          title: notification.title,
          body: notification.body,
          data: notification.data ?? {},
        );
      }
    }
    
    _pendingNotifications.clear();
  }

  /// Cancel background notifications
  void cancelBackgroundNotifications() {
    _pendingNotifications.clear();
    print('INFO NotificationService(Web): Cancelled background notifications');
  }

  /// Show typing notification
  void showTypingNotification(String senderName) {
    if (!_userEnabled || !_permissionGranted) return;
    
    showMessageNotification(
      title: 'Enigmo',
      body: '$senderName is typing...',
    );
  }

  /// Show connection status notification
  void showConnectionNotification(bool isConnected) {
    if (!_userEnabled || !_permissionGranted) return;
    
    showMessageNotification(
      title: 'Enigmo',
      body: isConnected ? 'Connected to server' : 'Disconnected from server',
    );
  }

  /// Check if notifications are effectively enabled (permission AND user toggle)
  bool get isEnabled => _permissionGranted && _userEnabled;
  bool get userEnabled => _userEnabled;
  void setUserEnabled(bool enabled) {
    _userEnabled = enabled;
    try { html.window.localStorage['notifications_enabled'] = enabled.toString(); } catch (_) {}
    if (enabled && _permissionGranted) {
      _processPendingNotifications();
    }
  }
  
  /// Check if service is initialized
  bool get isInitialized => _isInitialized;
  
  /// Get FCM token for mobile push notifications
  String? get fcmToken => _fcmToken;

  /// Dispose resources
  void dispose() {
    _pendingNotifications.clear();
    print('INFO NotificationService(Web): Disposed notification service');
  }
}

/// Internal class for pending notifications
class _PendingNotification {
  final String title;
  final String body;
  final Map<String, dynamic>? data;

  _PendingNotification({
    required this.title,
    required this.body,
    this.data,
  });
}
