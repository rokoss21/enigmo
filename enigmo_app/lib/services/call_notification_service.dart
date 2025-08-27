import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:enigmo_app/services/audio_call_service.dart';
import 'package:enigmo_app/screens/incoming_call_screen.dart';
import 'package:enigmo_app/screens/audio_call_screen.dart';
import 'package:enigmo_app/models/call.dart';

class CallNotificationService {
  final AudioCallService _audioCallService;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  CallNotificationService(this._audioCallService) {
    // Set up listener for incoming calls
    _audioCallService.onIncomingCall = _handleIncomingCall;
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // macOS uses the same settings as iOS (Darwin)
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings, // macOS uses Darwin settings
    );

    final success = await _notificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (!success!) {
      print('Failed to initialize notifications');
    }
  }

  Future<void> _onNotificationTapped(NotificationResponse response) async {
    // Handle notification tap - could navigate to call screen
    print('Notification tapped: ${response.payload}');
  }
  
  void _handleIncomingCall(Call call) {
    // Show system notification for incoming call
    _showIncomingCallNotification(call);
  }

  Future<void> _showIncomingCallNotification(Call call) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'incoming_calls',
      'Incoming Calls',
      channelDescription: 'Notifications for incoming voice calls',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: false,
      ongoing: true,
      autoCancel: false,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
      actions: [
        AndroidNotificationAction('accept', 'Accept'),
        AndroidNotificationAction('reject', 'Reject'),
      ],
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.active,
      categoryIdentifier: 'incoming_call',
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: iosDetails, // macOS uses Darwin settings
    );

    await _notificationsPlugin.show(
      call.id.hashCode,
      'Incoming Call',
      'Call from ${call.recipientId}',
      details,
      payload: call.id,
    );
  }
  
  // Method to show incoming call UI
  void showIncomingCallScreen(BuildContext context, Call call) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (BuildContext context) {
        return IncomingCallScreen(
          call: call,
          onAccept: () => _acceptCall(context, call),
          onReject: () => _rejectCall(context, call),
        );
      },
    );
  }
  
  void _acceptCall(BuildContext context, Call call) async {
    // Cancel the notification
    await _cancelCallNotification(call.id);

    // Close the incoming call dialog
    Navigator.of(context).pop();

    // Accept the call through the audio call service
    await _audioCallService.acceptCall(call.id, call.recipientId);

    // Navigate to the call screen
    // Check if we're still in a valid context before navigating
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => AudioCallScreen(audioCallService: _audioCallService),
        ),
      );
    }
  }

  void _rejectCall(BuildContext context, Call call) {
    // Cancel the notification
    _cancelCallNotification(call.id);

    // Close the incoming call dialog
    Navigator.of(context).pop();

    // Send call rejection to the caller
    _audioCallService.endCall();
  }

  Future<void> _cancelCallNotification(String callId) async {
    await _notificationsPlugin.cancel(callId.hashCode);
  }
}