import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Service for handling notifications on mobile platforms (no dart:html)
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  bool _isInitialized = false;
  bool _permissionGranted = false;
  bool _userEnabled = true; // user-controlled toggle
  final List<_PendingNotification> _pendingNotifications = [];

  dynamic _firebaseMessaging; // FirebaseMessaging (placeholder)
  dynamic _localNotifications; // FlutterLocalNotificationsPlugin (placeholder)
  String? _fcmToken;

  Future<void> initialize() async {
    if (_isInitialized) return;

    print('INFO NotificationService(Mobile): Initializing notification service');
    await _initializeMobileNotifications();
    _isInitialized = true;
  }

  Future<void> _initializeMobileNotifications() async {
    try {
      // Initialize Firebase Messaging (placeholder)
      try {
        final firebaseMessaging = await _getFirebaseMessaging();
        if (firebaseMessaging != null) {
          _firebaseMessaging = firebaseMessaging;
          print('INFO NotificationService(Mobile): Firebase messaging placeholder initialized');
        }
      } catch (e) {
        print('WARNING NotificationService(Mobile): Firebase not available, using local notifications only: $e');
      }

      // Initialize local notifications (placeholder)
      try {
        final localNotifications = await _getLocalNotificationsPlugin();
        if (localNotifications != null) {
          _localNotifications = localNotifications;
          print('INFO NotificationService(Mobile): Local notifications placeholder initialized');
        }
      } catch (e) {
        print('WARNING NotificationService(Mobile): Local notifications not available: $e');
      }

      // Assume permissions granted for placeholder
      _permissionGranted = true;
      print('INFO NotificationService(Mobile): Notification permissions assumed granted (placeholder)');
    } catch (e) {
      print('ERROR NotificationService(Mobile): Failed to initialize mobile notifications: $e');
    }
  }

  Future<dynamic> _getFirebaseMessaging() async {
    try {
      print('INFO NotificationService(Mobile): Attempting to load Firebase Messaging');
      return null; // disabled for now
    } catch (e) {
      print('INFO NotificationService(Mobile): Firebase messaging not available on this platform: $e');
      return null;
    }
  }

  Future<dynamic> _getLocalNotificationsPlugin() async {
    try {
      print('INFO NotificationService(Mobile): Attempting to load Local Notifications');
      return null; // disabled for now
    } catch (e) {
      print('INFO NotificationService(Mobile): Local notifications not available on this platform: $e');
      return null;
    }
  }

  Future<void> _setupFirebaseHandlers() async {
    if (_firebaseMessaging == null) return;
    try {
      print('INFO NotificationService(Mobile): Setting up Firebase handlers (placeholder)');
    } catch (e) {
      print('ERROR NotificationService(Mobile): Error setting up Firebase handlers: $e');
    }
  }

  void _handleFirebaseMessage(dynamic message, {required bool isBackground}) {
    try {
      print('INFO NotificationService(Mobile): Handling Firebase message (placeholder)');
    } catch (e) {
      print('ERROR NotificationService(Mobile): Error handling Firebase message: $e');
    }
  }

  void _onNotificationTap(dynamic response) {
    try {
      print('INFO NotificationService(Mobile): Local notification tapped');
    } catch (e) {
      print('ERROR NotificationService(Mobile): Error handling notification tap: $e');
    }
  }

  // No web support checks on mobile
  bool _isNotificationSupported() => true;

  Future<bool> requestPermissionIfNeeded() async {
    return _permissionGranted;
  }

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

    _showLocalNotification(
      title: title,
      body: body,
      data: data ?? {},
    );
  }

  void _showLocalNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) {
    try {
      print('INFO NotificationService(Mobile): Would show local notification: $title - $body');
    } catch (e) {
      print('ERROR NotificationService(Mobile): Failed to show local notification: $e');
    }
  }

  void _handleNotificationClick(Map<String, dynamic> data) {
    try {
      final chatId = data['chatId'] as String?;
      final senderId = data['senderId'] as String?;
      print('INFO NotificationService(Mobile): Handling notification click for chat: $chatId, sender: $senderId');
    } catch (e) {
      print('ERROR NotificationService(Mobile): Failed to handle notification click: $e');
    }
  }

  void _processPendingNotifications() {
    if (_pendingNotifications.isEmpty) return;
    print('INFO NotificationService(Mobile): Processing ${_pendingNotifications.length} pending notifications');
    for (final notification in _pendingNotifications) {
      _showLocalNotification(
        title: notification.title,
        body: notification.body,
        data: notification.data ?? {},
      );
    }
    _pendingNotifications.clear();
  }

  void cancelBackgroundNotifications() {
    _pendingNotifications.clear();
    print('INFO NotificationService(Mobile): Cancelled background notifications');
  }

  void showTypingNotification(String senderName) {
    if (!_userEnabled || !_permissionGranted) return;
    showMessageNotification(
      title: 'Enigmo',
      body: '$senderName is typing...',
    );
  }

  void showConnectionNotification(bool isConnected) {
    if (!_userEnabled || !_permissionGranted) return;
    showMessageNotification(
      title: 'Enigmo',
      body: isConnected ? 'Connected to server' : 'Disconnected from server',
    );
  }

  bool get isEnabled => _permissionGranted && _userEnabled;
  bool get userEnabled => _userEnabled;
  void setUserEnabled(bool enabled) {
    _userEnabled = enabled;
    if (enabled && _permissionGranted) {
      _processPendingNotifications();
    }
  }

  bool get isInitialized => _isInitialized;
  String? get fcmToken => _fcmToken;

  void dispose() {
    _pendingNotifications.clear();
    print('INFO NotificationService(Mobile): Disposed notification service');
  }
}

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
