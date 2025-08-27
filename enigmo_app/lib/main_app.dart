import 'package:flutter/material.dart';
import 'package:enigmo_app/services/audio_call_service.dart';
import 'package:enigmo_app/services/call_notification_service.dart';

class MainApp extends StatefulWidget {
  final AudioCallService audioCallService;
  
  const MainApp({Key? key, required this.audioCallService}) : super(key: key);
  
  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late CallNotificationService _callNotificationService;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize call notification service
    _callNotificationService = CallNotificationService(widget.audioCallService);
    
    // Set up listener for call status changes
    widget.audioCallService.onCallStatusChange = _handleCallStatusChange;
    
    // Set up listener for incoming calls
    widget.audioCallService.onIncomingCall = _handleIncomingCall;
  }
  
  void _handleCallStatusChange(Call call) {
    // Handle call status changes
    // For example, navigate to call screen when connected
    if (call.status == CallStatus.connected) {
      // Navigation would be handled here
    }
    
    // Update UI state
    setState(() {});
  }
  
  void _handleIncomingCall(Call call) {
    // Show incoming call screen
    _callNotificationService.showIncomingCallScreen(context, call);
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Enigmo',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Enigmo'),
        ),
        body: const Center(
          child: Text('Main App Screen'),
        ),
      ),
    );
  }
}