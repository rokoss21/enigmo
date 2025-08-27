import 'package:flutter/material.dart';
import 'package:enigmo_app/services/audio_call_service.dart';

class CallButton extends StatelessWidget {
  final String recipientId;
  final AudioCallService audioCallService;
  
  const CallButton({
    Key? key,
    required this.recipientId,
    required this.audioCallService,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.call, color: Colors.blue),
      onPressed: () => _initiateCall(context),
    );
  }
  
  void _initiateCall(BuildContext context) {
    // In a real implementation, you would navigate to the call screen
    // and initiate the call through the audioCallService
    audioCallService.initiateCall(recipientId);
    
    // Navigate to call screen
    // Navigator.push(
    //   context,
    //   MaterialPageRoute(
    //     builder: (context) => AudioCallScreen(
    //       audioCallService: audioCallService,
    //     ),
    //   ),
    // );
  }
}