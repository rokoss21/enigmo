import 'package:flutter/material.dart';
import 'package:enigmo_app/services/audio_call_service.dart';
import 'package:enigmo_app/services/call_notification_service.dart';
import 'package:enigmo_app/screens/chat_list_screen.dart';

class HomeScreen extends StatefulWidget {
  final AudioCallService audioCallService;
  final CallNotificationService callNotificationService;
  
  const HomeScreen({
    Key? key,
    required this.audioCallService,
    required this.callNotificationService,
  }) : super(key: key);
  
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    
    // Set up listener for incoming calls
    widget.audioCallService.onIncomingCall = _handleIncomingCall;
  }
  
  void _handleIncomingCall(Call call) {
    // Show incoming call screen
    widget.callNotificationService.showIncomingCallScreen(context, call);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enigmo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // Navigate to settings screen
            },
          ),
        ],
      ),
      body: ChatListScreen(audioCallService: widget.audioCallService),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Add new chat
        },
        child: const Icon(Icons.message),
      ),
    );
  }
}